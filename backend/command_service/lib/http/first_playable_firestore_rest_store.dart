import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:board_game_core/game_core.dart';

import '../ingress/command_ingress.dart';
import '../ready_start_planner.dart';
import '../reconnect_planner.dart';
import '../rng_operation_planner.dart';
import 'first_playable_authority_executor.dart';
import 'first_playable_persistence_codec.dart';

typedef FirstPlayableFirestoreAccessTokenProvider = Future<String> Function();

final class FirstPlayableFirestoreStoreViolation implements Exception {
  const FirstPlayableFirestoreStoreViolation(this.code);

  final String code;

  @override
  String toString() => 'FirstPlayableFirestoreStoreViolation: $code';
}

/// Server-side Firestore configuration for the first-playable Authority store.
///
/// Production uses the canonical HTTPS endpoint and an injected short-lived
/// OAuth access token. Emulator mode is deliberately restricted to numeric
/// loopback so a configuration error cannot silently send unsigned/admin test
/// traffic to another host.
final class FirstPlayableFirestoreRestConfig {
  FirstPlayableFirestoreRestConfig.production({
    required this.projectId,
    this.databaseId = '(default)',
    required FirstPlayableFirestoreAccessTokenProvider accessTokenProvider,
    this.maxAttempts = 5,
  }) : endpoint = Uri.https('firestore.googleapis.com'),
       // The field is nullable only because Emulator mode has no OAuth token.
       // ignore: prefer_initializing_formals
       accessTokenProvider = accessTokenProvider {
    _validate();
  }

  FirstPlayableFirestoreRestConfig.emulator({
    required this.projectId,
    required String host,
    this.databaseId = '(default)',
    this.maxAttempts = 5,
  }) : endpoint = _emulatorEndpoint(host),
       accessTokenProvider = null {
    _validate();
  }

  final String projectId;
  final String databaseId;
  final Uri endpoint;
  final FirstPlayableFirestoreAccessTokenProvider? accessTokenProvider;
  final int maxAttempts;

  bool get isEmulator => endpoint.scheme == 'http';

  void _validate() {
    if (!_identifier.hasMatch(projectId) ||
        databaseId.isEmpty ||
        databaseId.contains('/') ||
        maxAttempts < 1 ||
        maxAttempts > 10 ||
        !isEmulator && accessTokenProvider == null) {
      throw const FirstPlayableFirestoreStoreViolation(
        'invalidFirestoreConfiguration',
      );
    }
  }

  static Uri _emulatorEndpoint(String host) {
    if (!RegExp(r'^(127\.0\.0\.1|\[::1\]):[1-9][0-9]{0,4}$').hasMatch(host)) {
      throw const FirstPlayableFirestoreStoreViolation(
        'emulatorHostMustBeNumericLoopback',
      );
    }
    final endpoint = Uri.parse('http://$host');
    if (endpoint.port > 65535) {
      throw const FirstPlayableFirestoreStoreViolation(
        'invalidFirestoreConfiguration',
      );
    }
    return endpoint;
  }
}

/// Executable pure-Dart binding between Authority and Firestore.
///
/// The adapter uses Firestore's beginTransaction/batchGet/commit REST contract.
/// It invokes the existing typed evaluator after consistent reads and projects
/// only [FirstPlayablePersistenceCodec] decisions. Engine rules, identities and
/// private material stay in the Dart Authority process.
final class FirstPlayableFirestoreRestStore
    implements FirstPlayableAuthorityStore, FirstPlayableRoomSnapshotStore {
  FirstPlayableFirestoreRestStore({
    required FirstPlayableFirestoreRestConfig config,
    HttpClient? httpClient,
  }) : // The public parameter intentionally does not expose a private name.
       // ignore: prefer_initializing_formals
       _config = config,
       _http = httpClient ?? HttpClient();

  final FirstPlayableFirestoreRestConfig _config;
  final HttpClient _http;

  String get _database =>
      'projects/${_config.projectId}/databases/${_config.databaseId}';

  String _documentName(String path) => '$_database/documents/$path';

  @override
  Future<FirstPlayableRoomEntryTransactionResult> transactRoomEntry({
    required FirstPlayableRoomEntryKind kind,
    required String codeHash,
    String? roomId,
    required String commandId,
    required FirstPlayableRoomEntryTransactionCallback evaluate,
  }) async {
    _requirePathSegment(codeHash, 'invalidCodeHash');
    _requirePathSegment(commandId, 'invalidCommandId');
    if (kind == FirstPlayableRoomEntryKind.create) {
      _requirePathSegment(roomId, 'invalidRoomId');
    } else if (roomId != null) {
      throw const FirstPlayableFirestoreStoreViolation(
        'joinRoomIdMustComeFromLocator',
      );
    }

    return _retryingTransaction((transaction, attempt) async {
      final locatorPath = 'roomCodes/$codeHash';
      final receiptPath = 'roomCommands/$commandId';
      final firstRead = await transaction.batchGet(<String>[
        locatorPath,
        receiptPath,
      ]);
      final locatorData = firstRead[locatorPath];
      if (locatorData != null &&
          _requiredString(locatorData, 'codeHash') != codeHash) {
        throw const FirstPlayableFirestoreStoreViolation(
          'roomLocatorHashMismatch',
        );
      }
      final resolvedRoomId = kind == FirstPlayableRoomEntryKind.create
          ? roomId
          : _optionalString(locatorData, 'roomId');
      Map<String, Object?>? publicRoom;
      Map<String, Object?>? privateRoom;
      if (resolvedRoomId != null) {
        _requirePathSegment(resolvedRoomId, 'invalidRoomId');
        final roomRead = await transaction.batchGet(<String>[
          'rooms/$resolvedRoomId',
          'roomSecrets/$resolvedRoomId',
        ]);
        publicRoom = roomRead['rooms/$resolvedRoomId'];
        privateRoom = roomRead['roomSecrets/$resolvedRoomId'];
      }
      final view = FirstPlayableRoomEntryTransactionView(
        locator: _decodeLocator(locatorData),
        room: _decodeRoomEntryRoom(publicRoom, privateRoom),
        storedReceipt: _decodeReceipt(
          firstRead[receiptPath],
          expectedCommandId: commandId,
        ),
      );
      final decision = evaluate(view);
      final writes = _roomEntryWrites(
        decision,
        expectedKind: kind,
        expectedCodeHash: codeHash,
        expectedRoomId: resolvedRoomId,
      );
      await transaction.finish(writes);
      return FirstPlayableRoomEntryTransactionResult(
        decision: decision,
        metrics: transaction.metrics(
          attempt: attempt,
          schemaVersion: FirstPlayablePersistenceCodec.schemaVersion,
          stateVersion: decision.reply.versionAfter,
        ),
      );
    });
  }

  @override
  Future<FirstPlayableRoomTransactionResult> transactRoom({
    required String roomId,
    required String commandId,
    required FirstPlayableRoomTransactionCallback evaluate,
  }) async {
    _requirePathSegment(roomId, 'invalidRoomId');
    _requirePathSegment(commandId, 'invalidCommandId');
    return _retryingTransaction((transaction, attempt) async {
      final roomPath = 'rooms/$roomId';
      final privateRoomPath = 'roomSecrets/$roomId';
      final receiptPath = 'roomCommands/$commandId';
      final read = await transaction.batchGet(<String>[
        roomPath,
        privateRoomPath,
        receiptPath,
      ]);
      final room = _decodeRoomTransaction(
        read[roomPath],
        read[privateRoomPath],
        _decodeReceipt(read[receiptPath], expectedCommandId: commandId),
      );
      final decision = evaluate(room);
      final writes = _roomWrites(
        roomId: roomId,
        commandId: commandId,
        decision: decision,
      );
      await transaction.finish(writes);
      return FirstPlayableRoomTransactionResult(
        decision: decision,
        metrics: transaction.metrics(
          attempt: attempt,
          schemaVersion: FirstPlayablePersistenceCodec.schemaVersion,
          stateVersion: decision.reply.versionAfter,
        ),
      );
    });
  }

  @override
  Future<FirstPlayableGameTransactionResult> transactGame({
    required String gameId,
    required String commandId,
    required FirstPlayableGameTransactionCallback evaluate,
  }) async {
    _requirePathSegment(gameId, 'invalidGameId');
    _requirePathSegment(commandId, 'invalidCommandId');
    return _retryingTransaction((transaction, attempt) async {
      final publicPath = 'games/$gameId';
      final privatePath = 'gameSecrets/$gameId';
      final receiptPath = 'games/$gameId/commands/$commandId';
      final read = await transaction.batchGet(<String>[
        publicPath,
        privatePath,
        receiptPath,
      ]);
      final view = _decodeGame(
        publicGame: read[publicPath],
        privateGame: read[privatePath],
        receipt: read[receiptPath],
        expectedGameId: gameId,
        expectedCommandId: commandId,
      );
      final decision = evaluate(view);
      final writes = _gameWrites(
        gameId: gameId,
        commandId: commandId,
        decision: decision,
      );
      await transaction.finish(writes);
      return FirstPlayableGameTransactionResult(
        decision: decision,
        metrics: transaction.metrics(
          attempt: attempt,
          schemaVersion: view.publicState.header.schemaVersion,
          stateVersion: decision.reply.versionAfter,
        ),
      );
    });
  }

  @override
  Future<FirstPlayableGameReadResult> readGame({
    required String gameId,
    String? commandId,
  }) async {
    _requirePathSegment(gameId, 'invalidGameId');
    if (commandId != null) {
      _requirePathSegment(commandId, 'invalidCommandId');
    }
    final transaction = await _beginTransaction(readOnly: true);
    try {
      final publicPath = 'games/$gameId';
      final privatePath = 'gameSecrets/$gameId';
      final receiptPath = commandId == null
          ? null
          : 'games/$gameId/commands/$commandId';
      final read = await transaction.batchGet(<String>[
        publicPath,
        privatePath,
        ?receiptPath,
      ]);
      final view = _decodeGame(
        publicGame: read[publicPath],
        privateGame: read[privatePath],
        receipt: receiptPath == null ? null : read[receiptPath],
        expectedGameId: gameId,
        expectedCommandId: commandId,
      );
      await transaction.rollback();
      return FirstPlayableGameReadResult(
        view: view,
        metrics: transaction.metrics(
          attempt: 0,
          schemaVersion: view.publicState.header.schemaVersion,
          stateVersion: view.publicState.header.stateVersion,
        ),
      );
    } on Object {
      await transaction.rollbackBestEffort();
      rethrow;
    }
  }

  @override
  Future<FirstPlayableRoomReadResult> readRoom({required String roomId}) async {
    _requirePathSegment(roomId, 'invalidRoomId');
    final transaction = await _beginTransaction(readOnly: true);
    try {
      final publicPath = 'rooms/$roomId';
      final privatePath = 'roomSecrets/$roomId';
      final read = await transaction.batchGet(<String>[
        publicPath,
        privatePath,
      ]);
      final view = _decodeRoomTransaction(
        read[publicPath],
        read[privatePath],
        null,
      );
      await transaction.rollback();
      return FirstPlayableRoomReadResult(
        view: view,
        metrics: transaction.metrics(
          attempt: 0,
          schemaVersion: FirstPlayablePersistenceCodec.schemaVersion,
          stateVersion: view.roomVersion,
        ),
      );
    } on Object {
      await transaction.rollbackBestEffort();
      rethrow;
    }
  }

  Future<T> _retryingTransaction<T>(
    Future<T> Function(_FirestoreRestTransaction transaction, int attempt) body,
  ) async {
    for (var attempt = 0; attempt < _config.maxAttempts; attempt += 1) {
      final transaction = await _beginTransaction();
      try {
        return await body(transaction, attempt);
      } on _FirestoreRestException catch (error) {
        await transaction.rollbackBestEffort();
        if (error.isConflict && attempt + 1 < _config.maxAttempts) {
          continue;
        }
        throw FirstPlayableFirestoreStoreViolation(
          error.isConflict ? 'transactionConflict' : 'firestoreUnavailable',
        );
      } on Object {
        await transaction.rollbackBestEffort();
        rethrow;
      }
    }
    throw const FirstPlayableFirestoreStoreViolation('transactionConflict');
  }

  Future<_FirestoreRestTransaction> _beginTransaction({
    bool readOnly = false,
  }) async {
    final response = await _request(
      method: 'POST',
      suffix: '/documents:beginTransaction',
      body: <String, Object?>{
        if (readOnly)
          'options': <String, Object?>{'readOnly': <String, Object?>{}},
      },
    );
    final transaction = response.value['transaction'];
    if (transaction is! String || transaction.isEmpty) {
      throw const FirstPlayableFirestoreStoreViolation(
        'invalidFirestoreResponse',
      );
    }
    return _FirestoreRestTransaction(
      store: this,
      id: transaction,
      initialBytesRead: response.bytesRead,
      initialBytesWritten: response.bytesWritten,
    );
  }

  Future<_FirestoreResponse> _request({
    required String method,
    required String suffix,
    Map<String, Object?>? body,
  }) async {
    final uri = _config.endpoint.replace(path: '/v1/$_database$suffix');
    final request = await _http.openUrl(method, uri);
    request.headers.contentType = ContentType.json;
    final tokenProvider = _config.accessTokenProvider;
    if (tokenProvider != null) {
      final token = await tokenProvider();
      if (token.isEmpty || token.contains(RegExp(r'\s'))) {
        throw const FirstPlayableFirestoreStoreViolation(
          'invalidFirestoreCredential',
        );
      }
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    } else if (_config.isEmulator) {
      // Firestore Emulator's documented owner credential gives this
      // server-side adapter Admin-SDK-equivalent access. The configuration
      // constructor prevents it from ever being sent beyond numeric loopback.
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
    }
    final encoded = body == null ? null : utf8.encode(jsonEncode(body));
    if (encoded != null) request.add(encoded);
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    final text = utf8.decode(bytes);
    Object? decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        throw _FirestoreRestException(response.statusCode, 'invalidJson');
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? code;
      if (decoded is Map<String, Object?>) {
        final error = decoded['error'];
        if (error is Map) code = error['status']?.toString();
      }
      throw _FirestoreRestException(response.statusCode, code ?? 'httpError');
    }
    return _FirestoreResponse(
      value: decoded is Map<String, Object?>
          ? decoded
          : <String, Object?>{'responses': decoded},
      bytesRead: bytes.length,
      bytesWritten: encoded?.length ?? 0,
    );
  }

  List<Map<String, Object?>> _roomEntryWrites(
    FirstPlayableRoomEntryTransactionDecision decision, {
    required FirstPlayableRoomEntryKind expectedKind,
    required String expectedCodeHash,
    required String? expectedRoomId,
  }) {
    final encoded = FirstPlayablePersistenceCodec.encodeRoomEntryDecision(
      decision,
    );
    final entry = _optionalMap(encoded, 'roomEntry');
    final receipt = _optionalMap(encoded, 'receipt');
    if (entry == null) {
      return receipt == null
          ? const <Map<String, Object?>>[]
          : <Map<String, Object?>>[
              _replaceWrite(
                'roomCommands/${decision.reply.commandId}',
                receipt,
              ),
            ];
    }
    final kind = _requiredString(entry, 'kind');
    final codeHash = _requiredString(entry, 'codeHash');
    final roomId = _requiredString(entry, 'roomId');
    if (kind != expectedKind.name ||
        codeHash != expectedCodeHash ||
        roomId != expectedRoomId ||
        receipt == null) {
      throw const FirstPlayableFirestoreStoreViolation(
        'roomEntryDecisionMismatch',
      );
    }
    final publicRoom = _requiredMap(entry, 'publicRoom');
    final privateRoom = _requiredMap(entry, 'privateRoom');
    _assertPublicOnly(publicRoom);
    final writes = <Map<String, Object?>>[];
    if (expectedKind == FirstPlayableRoomEntryKind.create) {
      final updatedAt = _requiredInt(entry, 'updatedAtMs');
      final expiresAt = _requiredInt(entry, 'expiresAtMs');
      writes.add(
        _replaceWrite('roomCodes/$codeHash', <String, Object?>{
          'codeHash': codeHash,
          'roomId': roomId,
          'updatedAt': DateTime.fromMillisecondsSinceEpoch(
            updatedAt,
            isUtc: true,
          ),
          'expiresAt': DateTime.fromMillisecondsSinceEpoch(
            expiresAt,
            isUtc: true,
          ),
        }),
      );
      writes.add(_replaceWrite('rooms/$roomId', publicRoom));
      writes.add(_replaceWrite('roomSecrets/$roomId', privateRoom));
    } else {
      writes.add(_mergeWrite('rooms/$roomId', publicRoom));
      writes.add(_mergeWrite('roomSecrets/$roomId', privateRoom));
    }
    writes.add(
      _replaceWrite('roomCommands/${decision.reply.commandId}', receipt),
    );
    return writes;
  }

  List<Map<String, Object?>> _roomWrites({
    required String roomId,
    required String commandId,
    required FirstPlayableRoomTransactionDecision decision,
  }) {
    final encoded = FirstPlayablePersistenceCodec.encodeRoomDecision(decision);
    final roomPatch = _optionalMap(encoded, 'roomPatch');
    final startGame = _optionalMap(encoded, 'startGame');
    final receipt = _optionalMap(encoded, 'receipt');
    if (roomPatch == null) {
      return receipt == null
          ? const <Map<String, Object?>>[]
          : <Map<String, Object?>>[
              _replaceWrite('roomCommands/$commandId', receipt),
            ];
    }
    if (receipt == null) {
      throw const FirstPlayableFirestoreStoreViolation(
        'acceptedDecisionMissingReceipt',
      );
    }
    final writes = <Map<String, Object?>>[
      _mergeWrite('rooms/$roomId', roomPatch),
    ];
    if (startGame != null) {
      final gameId = _requiredString(startGame, 'gameId');
      final publicGame = _requiredMap(startGame, 'publicGame');
      final privateGame = _requiredMap(startGame, 'privateGame');
      _assertPublicOnly(publicGame);
      writes.add(_replaceWrite('games/$gameId', publicGame));
      writes.add(_replaceWrite('gameSecrets/$gameId', privateGame));
    }
    writes.add(_replaceWrite('roomCommands/$commandId', receipt));
    return writes;
  }

  List<Map<String, Object?>> _gameWrites({
    required String gameId,
    required String commandId,
    required FirstPlayableGameTransactionDecision decision,
  }) {
    final encoded = FirstPlayablePersistenceCodec.encodeGameDecision(decision);
    final publicPatch = _optionalMap(encoded, 'publicPatch');
    final privatePatch = _optionalMap(encoded, 'privatePatch');
    final receipt = _optionalMap(encoded, 'receipt');
    if (publicPatch == null) {
      return receipt == null
          ? const <Map<String, Object?>>[]
          : <Map<String, Object?>>[
              _replaceWrite('games/$gameId/commands/$commandId', receipt),
            ];
    }
    if (receipt == null) {
      throw const FirstPlayableFirestoreStoreViolation(
        'acceptedDecisionMissingReceipt',
      );
    }
    _assertPublicOnly(publicPatch);
    return <Map<String, Object?>>[
      _mergeWrite('games/$gameId', publicPatch),
      if (privatePatch != null)
        _mergeWrite('gameSecrets/$gameId', privatePatch),
      _replaceWrite('games/$gameId/commands/$commandId', receipt),
    ];
  }

  Map<String, Object?> _replaceWrite(
    String path,
    Map<String, Object?> fields,
  ) => <String, Object?>{
    'update': <String, Object?>{
      'name': _documentName(path),
      'fields': _encodeFields(fields),
    },
  };

  Map<String, Object?> _mergeWrite(String path, Map<String, Object?> fields) =>
      <String, Object?>{
        'update': <String, Object?>{
          'name': _documentName(path),
          'fields': _encodeFields(fields),
        },
        'updateMask': <String, Object?>{
          'fieldPaths': fields.keys.toList(growable: false),
        },
      };

  static void _requirePathSegment(String? value, String code) {
    if (value == null ||
        value.isEmpty ||
        value.contains('/') ||
        value == '.' ||
        value == '..') {
      throw FirstPlayableFirestoreStoreViolation(code);
    }
  }
}

final class _FirestoreRestTransaction {
  _FirestoreRestTransaction({
    required this.store,
    required this.id,
    required int initialBytesRead,
    required int initialBytesWritten,
  }) : bytesRead = initialBytesRead,
       bytesWritten = initialBytesWritten;

  final FirstPlayableFirestoreRestStore store;
  final String id;
  int readCount = 0;
  int writeCount = 0;
  int bytesRead;
  int bytesWritten;
  bool _closed = false;

  Future<Map<String, Map<String, Object?>?>> batchGet(
    List<String> paths,
  ) async {
    if (_closed || paths.isEmpty) {
      throw const FirstPlayableFirestoreStoreViolation(
        'invalidTransactionState',
      );
    }
    final response = await store._request(
      method: 'POST',
      suffix: '/documents:batchGet',
      body: <String, Object?>{
        'documents': paths.map(store._documentName).toList(growable: false),
        'transaction': id,
      },
    );
    bytesRead += response.bytesRead;
    bytesWritten += response.bytesWritten;
    readCount += paths.length;
    final rawResponses = response.value['responses'];
    if (rawResponses is! List<Object?>) {
      throw const FirstPlayableFirestoreStoreViolation(
        'invalidFirestoreResponse',
      );
    }
    final byPath = <String, Map<String, Object?>?>{
      for (final path in paths) path: null,
    };
    for (final raw in rawResponses) {
      final item = _asStringMap(raw, 'invalidFirestoreResponse');
      final found = item['found'];
      final missing = item['missing'];
      if (found != null) {
        final document = _asStringMap(found, 'invalidFirestoreResponse');
        final path = _relativeDocumentPath(
          _requiredString(document, 'name'),
          store._database,
        );
        if (!byPath.containsKey(path)) {
          throw const FirstPlayableFirestoreStoreViolation(
            'unexpectedFirestoreDocument',
          );
        }
        byPath[path] = _decodeFields(
          _asStringMap(document['fields'], 'invalidFirestoreResponse'),
        );
      } else if (missing is String) {
        final path = _relativeDocumentPath(missing, store._database);
        if (!byPath.containsKey(path)) {
          throw const FirstPlayableFirestoreStoreViolation(
            'unexpectedFirestoreDocument',
          );
        }
      } else {
        throw const FirstPlayableFirestoreStoreViolation(
          'invalidFirestoreResponse',
        );
      }
    }
    return byPath;
  }

  Future<void> finish(List<Map<String, Object?>> writes) async {
    if (_closed) {
      throw const FirstPlayableFirestoreStoreViolation(
        'invalidTransactionState',
      );
    }
    if (writes.isEmpty) {
      await rollback();
      return;
    }
    final response = await store._request(
      method: 'POST',
      suffix: '/documents:commit',
      body: <String, Object?>{'writes': writes, 'transaction': id},
    );
    bytesRead += response.bytesRead;
    bytesWritten += response.bytesWritten;
    writeCount += writes.length;
    _closed = true;
  }

  Future<void> rollback() async {
    if (_closed) return;
    final response = await store._request(
      method: 'POST',
      suffix: '/documents:rollback',
      body: <String, Object?>{'transaction': id},
    );
    bytesRead += response.bytesRead;
    bytesWritten += response.bytesWritten;
    _closed = true;
  }

  Future<void> rollbackBestEffort() async {
    try {
      await rollback();
    } on Object {
      _closed = true;
    }
  }

  AuthorityExecutionMetrics metrics({
    required int attempt,
    required int schemaVersion,
    required int stateVersion,
  }) => AuthorityExecutionMetrics(
    retryCount: attempt,
    conflictCount: attempt,
    firestoreReadCount: readCount,
    firestoreWriteCount: writeCount,
    bytesRead: bytesRead,
    bytesWritten: bytesWritten,
    schemaVersion: schemaVersion,
    stateVersion: stateVersion,
  );
}

final class _FirestoreResponse {
  const _FirestoreResponse({
    required this.value,
    required this.bytesRead,
    required this.bytesWritten,
  });

  final Map<String, Object?> value;
  final int bytesRead;
  final int bytesWritten;
}

final class _FirestoreRestException implements Exception {
  const _FirestoreRestException(this.statusCode, this.code);

  final int statusCode;
  final String code;

  bool get isConflict => statusCode == HttpStatus.conflict || code == 'ABORTED';
}

FirstPlayableRoomLocatorView? _decodeLocator(Map<String, Object?>? value) {
  if (value == null) return null;
  return FirstPlayableRoomLocatorView(
    roomId: _requiredString(value, 'roomId'),
    expiresAt: _requiredDateTime(value, 'expiresAt'),
  );
}

FirstPlayableRoomEntryRoomView? _decodeRoomEntryRoom(
  Map<String, Object?>? publicRoom,
  Map<String, Object?>? privateRoom,
) {
  if (publicRoom == null && privateRoom == null) return null;
  final decoded = _decodeRoomMembers(publicRoom, privateRoom);
  return FirstPlayableRoomEntryRoomView(
    roomId: _requiredString(publicRoom!, 'roomId'),
    roomVersion: _requiredInt(publicRoom, 'roomVersion'),
    status: _requiredString(publicRoom, 'status'),
    hostUid: _requiredString(publicRoom, 'hostUid'),
    presetId: _requiredString(publicRoom, 'presetId'),
    rulesVersion: _requiredString(publicRoom, 'frozenRulesVersion'),
    members: decoded,
  );
}

FirstPlayableRoomTransactionView _decodeRoomTransaction(
  Map<String, Object?>? publicRoom,
  Map<String, Object?>? privateRoom,
  StoredAuthorityCommandReceipt? receipt,
) {
  if (publicRoom == null || privateRoom == null) {
    throw const FirstPlayableFirestoreStoreViolation('roomUnavailable');
  }
  return FirstPlayableRoomTransactionView(
    roomId: _requiredString(publicRoom, 'roomId'),
    roomVersion: _requiredInt(publicRoom, 'roomVersion'),
    status: _requiredString(publicRoom, 'status'),
    hostUid: _requiredString(publicRoom, 'hostUid'),
    presetId: _requiredString(publicRoom, 'presetId'),
    rulesVersion: _requiredString(publicRoom, 'frozenRulesVersion'),
    members: _decodeRoomMembers(publicRoom, privateRoom),
    storedReceipt: receipt,
  );
}

List<ReadyRoomMember> _decodeRoomMembers(
  Map<String, Object?>? publicRoom,
  Map<String, Object?>? privateRoom,
) {
  if (publicRoom == null || privateRoom == null) {
    throw const FirstPlayableFirestoreStoreViolation(
      'inconsistentRoomBoundary',
    );
  }
  _requireSchema(publicRoom);
  _requireSchema(privateRoom);
  final memberUids = _requiredList(
    publicRoom,
    'memberUids',
  ).map((value) => value is String ? value : '').toList(growable: false);
  final readyByUid = _requiredMap(publicRoom, 'readyByUid');
  final memberUidByPlayerId = _requiredMap(
    privateRoom,
    'memberUidByPlayerId',
  ).map((key, value) => MapEntry(key, value is String ? value : ''));
  final playerIdByUid = <String, String>{
    for (final entry in memberUidByPlayerId.entries) entry.value: entry.key,
  };
  if (memberUids.isEmpty ||
      memberUids.any((uid) => uid.isEmpty) ||
      memberUids.toSet().length != memberUids.length ||
      playerIdByUid.length != memberUidByPlayerId.length ||
      playerIdByUid.keys.toSet().difference(memberUids.toSet()).isNotEmpty ||
      memberUids.toSet().difference(playerIdByUid.keys.toSet()).isNotEmpty ||
      readyByUid.keys.toSet().difference(memberUids.toSet()).isNotEmpty ||
      memberUids.toSet().difference(readyByUid.keys.toSet()).isNotEmpty) {
    throw const FirstPlayableFirestoreStoreViolation(
      'inconsistentRoomMembership',
    );
  }
  return <ReadyRoomMember>[
    for (final uid in memberUids)
      ReadyRoomMember(
        uid: uid,
        playerId: playerIdByUid[uid]!,
        kind: PlayerKind.human,
        ready: _requiredBool(readyByUid, uid),
      ),
  ];
}

FirstPlayableGameTransactionView _decodeGame({
  required Map<String, Object?>? publicGame,
  required Map<String, Object?>? privateGame,
  required Map<String, Object?>? receipt,
  required String expectedGameId,
  required String? expectedCommandId,
}) {
  if (publicGame == null || privateGame == null) {
    throw const FirstPlayableFirestoreStoreViolation('gameUnavailable');
  }
  _requireSchema(publicGame);
  _requireSchema(privateGame);
  final state = _decodePublicGameState(_requiredMap(publicGame, 'publicState'));
  if (state.header.gameId != expectedGameId ||
      _requiredInt(publicGame, 'stateVersion') != state.header.stateVersion ||
      _requiredInt(publicGame, 'schemaVersion') != state.header.schemaVersion) {
    throw const FirstPlayableFirestoreStoreViolation(
      'publicGameEnvelopeMismatch',
    );
  }
  final membership = _requiredMap(
    privateGame,
    'memberUidByPlayerId',
  ).map((key, value) => MapEntry(key, value is String ? value : ''));
  final publicMemberUidList = _requiredList(publicGame, 'memberUids');
  if (publicMemberUidList.any((value) => value is! String || value.isEmpty)) {
    throw const FirstPlayableFirestoreStoreViolation(
      'inconsistentGameMembership',
    );
  }
  final publicMemberUids = publicMemberUidList.cast<String>().toSet();
  final statePlayerIds = state.players.map((player) => player.playerId).toSet();
  if (membership.entries.any(
        (entry) => entry.key.isEmpty || entry.value.isEmpty,
      ) ||
      membership.values.toSet().length != membership.length ||
      publicMemberUids.length != publicMemberUidList.length ||
      membership.values.toSet().difference(publicMemberUids).isNotEmpty ||
      publicMemberUids.difference(membership.values.toSet()).isNotEmpty ||
      statePlayerIds.difference(membership.keys.toSet()).isNotEmpty ||
      membership.keys.toSet().difference(statePlayerIds).isNotEmpty) {
    throw const FirstPlayableFirestoreStoreViolation(
      'inconsistentGameMembership',
    );
  }
  final rngVersion = _requiredString(privateGame, 'rngVersion');
  final seed = privateGame['seedBytes'];
  final counters = _requiredMap(privateGame, 'streamCounters');
  if (seed is! Uint8List || seed.length != 32) {
    throw const FirstPlayableFirestoreStoreViolation('invalidPrivateRng');
  }
  final privateRng = AuthorityPrivateRngSnapshot(
    rngVersion: rngVersion,
    seed: seed,
    streamCounters: <RngStream, int>{
      for (final stream in RngStream.values)
        stream: _optionalInt(counters, stream.label) ?? 0,
    },
  );
  if (privateRng.streamCounters.values.any((counter) => counter < 0)) {
    throw const FirstPlayableFirestoreStoreViolation('invalidPrivateRng');
  }
  return FirstPlayableGameTransactionView(
    publicState: state,
    memberUidByPlayerId: membership,
    privateRng: privateRng,
    storedReceipt: _decodeReceipt(
      receipt,
      expectedCommandId: expectedCommandId,
    ),
  );
}

StoredAuthorityCommandReceipt? _decodeReceipt(
  Map<String, Object?>? value, {
  required String? expectedCommandId,
}) {
  if (value == null) return null;
  _requireSchema(value);
  final commandId = _requiredString(value, 'commandId');
  if (expectedCommandId != null && commandId != expectedCommandId) {
    throw const FirstPlayableFirestoreStoreViolation('receiptIdentityMismatch');
  }
  final roomEntryCodeHash = _optionalString(value, 'roomEntryCodeHash');
  if (roomEntryCodeHash != null &&
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(roomEntryCodeHash)) {
    throw const FirstPlayableFirestoreStoreViolation('receiptIdentityMismatch');
  }
  return StoredAuthorityCommandReceipt(
    actorUid: _requiredString(value, 'actorUid'),
    roomEntryCodeHash: roomEntryCodeHash,
    receipt: DurableCommandReceipt(
      commandId: commandId,
      inputHashVersion: _requiredInt(value, 'inputHashVersion'),
      inputHash: _requiredString(value, 'inputHash'),
      publicResult: _requiredMap(value, 'resultSummary'),
    ),
  );
}

PublicGameState _decodePublicGameState(
  Map<String, Object?> value,
) => PublicGameState(
  header: GameStateHeader(
    schemaVersion: _requiredInt(value, 'schemaVersion'),
    stateVersion: _requiredInt(value, 'stateVersion'),
    rulesVersion: _requiredString(value, 'rulesVersion'),
    rngVersion: _requiredString(value, 'rngVersion'),
    rngCommitment: _requiredString(value, 'rngCommitment'),
    gameId: _requiredString(value, 'gameId'),
    roomId: _requiredString(value, 'roomId'),
    status: _enumByWire(
      GameStatus.values,
      _requiredString(value, 'status'),
      (entry) => entry.wireValue,
    ),
  ),
  presetConfig: _requiredMap(value, 'presetConfig'),
  roundState: _requiredMap(value, 'roundState'),
  turnState: _requiredMap(value, 'turnState'),
  players: _requiredList(value, 'players')
      .map((raw) => _decodePlayer(_asStringMap(raw, 'invalidPublicGameState')))
      .toList(growable: false),
  seatControllers: _requiredList(value, 'seatControllers')
      .map(
        (raw) =>
            _decodeSeatController(_asStringMap(raw, 'invalidPublicGameState')),
      )
      .toList(growable: false),
  board: _requiredMap(value, 'board'),
  ownership: _requiredMap(value, 'ownership'),
  bank: _requiredMap(value, 'bank'),
  freeParkingPot: _requiredInt(value, 'freeParkingPot'),
  deckPublicState: _requiredMap(value, 'deckPublicState'),
  pendingDecision: _optionalMap(value, 'pendingDecision'),
  activeAuction: _optionalMap(value, 'activeAuction'),
  activeTrade: _optionalMap(value, 'activeTrade'),
  debtCase: _optionalMap(value, 'debtCase'),
  result: _optionalMap(value, 'result'),
  lastMutation: _requiredMap(value, 'lastMutation'),
);

PlayerState _decodePlayer(Map<String, Object?> value) => PlayerState(
  playerId: _requiredString(value, 'playerId'),
  seat: _requiredInt(value, 'seat'),
  kind: _enumByWire(
    PlayerKind.values,
    _requiredString(value, 'kind'),
    (entry) => entry.wireValue,
  ),
  status: _enumByWire(
    PlayerStatus.values,
    _requiredString(value, 'status'),
    (entry) => entry.wireValue,
  ),
  cash: _requiredInt(value, 'cash'),
  position: _requiredInt(value, 'position'),
  ownedPropertyIds: _stringList(value, 'ownedPropertyIds'),
  keepCardIds: _stringList(value, 'keepCards'),
  inCucha: _requiredBool(value, 'inCucha'),
  cuchaAttempts: _requiredInt(value, 'cuchaAttempts'),
  consecutiveDoubles: _requiredInt(value, 'consecutiveDoubles'),
  connectivityStatus: _enumByWire(
    ConnectivityStatus.values,
    _requiredString(value, 'connectivityStatus'),
    (entry) => entry.wireValue,
  ),
);

SeatControllerState _decodeSeatController(Map<String, Object?> value) {
  final takeoverReason = _optionalString(value, 'takeoverReason');
  final takeoverStartedAt = _optionalString(value, 'takeoverStartedAt');
  return SeatControllerState(
    playerId: _requiredString(value, 'playerId'),
    controller: _enumByWire(
      SeatController.values,
      _requiredString(value, 'controller'),
      (entry) => entry.wireValue,
    ),
    botPolicyId: _optionalString(value, 'botPolicyId'),
    takeoverReason: takeoverReason == null
        ? null
        : _enumByWire<TakeoverReason>(
            TakeoverReason.values,
            takeoverReason,
            (entry) => entry.wireValue,
          ),
    takeoverStartedAt: takeoverStartedAt == null
        ? null
        : DateTime.tryParse(takeoverStartedAt)?.toUtc() ??
              (throw const FirstPlayableFirestoreStoreViolation(
                'invalidPublicGameState',
              )),
    humanReclaimPending: _requiredBool(value, 'humanReclaimPending'),
  );
}

T _enumByWire<T>(List<T> values, String wire, String Function(T) encode) {
  for (final value in values) {
    if (encode(value) == wire) return value;
  }
  throw const FirstPlayableFirestoreStoreViolation('invalidPublicGameState');
}

Map<String, Object?> _encodeFields(Map<String, Object?> value) =>
    <String, Object?>{
      for (final entry in value.entries) entry.key: _encodeValue(entry.value),
    };

Map<String, Object?> _encodeValue(Object? value) {
  if (value == null) return <String, Object?>{'nullValue': null};
  if (value is bool) return <String, Object?>{'booleanValue': value};
  if (value is int) return <String, Object?>{'integerValue': value.toString()};
  if (value is String) return <String, Object?>{'stringValue': value};
  if (value is DateTime) {
    return <String, Object?>{'timestampValue': value.toUtc().toIso8601String()};
  }
  if (value is Uint8List) {
    return <String, Object?>{'bytesValue': base64Encode(value)};
  }
  if (value is List<Object?>) {
    return <String, Object?>{
      'arrayValue': <String, Object?>{
        'values': value.map(_encodeValue).toList(growable: false),
      },
    };
  }
  if (value is Map<String, Object?>) {
    return <String, Object?>{
      'mapValue': <String, Object?>{'fields': _encodeFields(value)},
    };
  }
  throw const FirstPlayableFirestoreStoreViolation('unsupportedFirestoreValue');
}

Map<String, Object?> _decodeFields(Map<String, Object?> fields) =>
    <String, Object?>{
      for (final entry in fields.entries) entry.key: _decodeValue(entry.value),
    };

Object? _decodeValue(Object? raw) {
  final value = _asStringMap(raw, 'invalidFirestoreValue');
  if (value.length != 1) {
    throw const FirstPlayableFirestoreStoreViolation('invalidFirestoreValue');
  }
  if (value.containsKey('nullValue')) return null;
  if (value['booleanValue'] case final bool boolean) return boolean;
  if (value['integerValue'] case final String integer) {
    return int.tryParse(integer) ??
        (throw const FirstPlayableFirestoreStoreViolation(
          'invalidFirestoreValue',
        ));
  }
  if (value['stringValue'] case final String string) return string;
  if (value['timestampValue'] case final String timestamp) {
    return DateTime.tryParse(timestamp)?.toUtc() ??
        (throw const FirstPlayableFirestoreStoreViolation(
          'invalidFirestoreValue',
        ));
  }
  if (value['bytesValue'] case final String bytes) {
    try {
      return Uint8List.fromList(base64Decode(bytes));
    } on FormatException {
      throw const FirstPlayableFirestoreStoreViolation('invalidFirestoreValue');
    }
  }
  if (value['arrayValue'] case final Object array) {
    final arrayMap = _asStringMap(array, 'invalidFirestoreValue');
    final values = arrayMap['values'];
    if (values == null) return <Object?>[];
    if (values is! List<Object?>) {
      throw const FirstPlayableFirestoreStoreViolation('invalidFirestoreValue');
    }
    return values.map(_decodeValue).toList(growable: false);
  }
  if (value['mapValue'] case final Object map) {
    final mapValue = _asStringMap(map, 'invalidFirestoreValue');
    final fields = mapValue['fields'];
    if (fields == null) return <String, Object?>{};
    return _decodeFields(_asStringMap(fields, 'invalidFirestoreValue'));
  }
  throw const FirstPlayableFirestoreStoreViolation('invalidFirestoreValue');
}

Map<String, Object?> _asStringMap(Object? value, String code) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    try {
      return value.cast<String, Object?>();
    } on TypeError {
      // Fall through to the stable safe error below.
    }
  }
  throw FirstPlayableFirestoreStoreViolation(code);
}

String _relativeDocumentPath(String name, String database) {
  final prefix = '$database/documents/';
  if (!name.startsWith(prefix) || name.length == prefix.length) {
    throw const FirstPlayableFirestoreStoreViolation(
      'invalidFirestoreResponse',
    );
  }
  return name.substring(prefix.length);
}

void _requireSchema(Map<String, Object?> value) {
  if (_requiredInt(value, 'schemaVersion') !=
      FirstPlayablePersistenceCodec.schemaVersion) {
    throw const FirstPlayableFirestoreStoreViolation(
      'unsupportedPersistenceSchema',
    );
  }
}

Map<String, Object?> _requiredMap(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is Map<String, Object?>) return result;
  if (result is Map) {
    try {
      return result.cast<String, Object?>();
    } on TypeError {
      // Fall through.
    }
  }
  throw const FirstPlayableFirestoreStoreViolation('invalidPersistedDocument');
}

Map<String, Object?>? _optionalMap(Map<String, Object?> value, String key) {
  if (!value.containsKey(key) || value[key] == null) return null;
  return _requiredMap(value, key);
}

List<Object?> _requiredList(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is List<Object?>) return result;
  throw const FirstPlayableFirestoreStoreViolation('invalidPersistedDocument');
}

List<String> _stringList(Map<String, Object?> value, String key) =>
    _requiredList(value, key)
        .map(
          (entry) => entry is String
              ? entry
              : throw const FirstPlayableFirestoreStoreViolation(
                  'invalidPersistedDocument',
                ),
        )
        .toList(growable: false);

String _requiredString(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is String && result.isNotEmpty) return result;
  throw const FirstPlayableFirestoreStoreViolation('invalidPersistedDocument');
}

String? _optionalString(Map<String, Object?>? value, String key) {
  if (value == null || !value.containsKey(key) || value[key] == null) {
    return null;
  }
  return _requiredString(value, key);
}

int _requiredInt(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is int) return result;
  throw const FirstPlayableFirestoreStoreViolation('invalidPersistedDocument');
}

int? _optionalInt(Map<String, Object?> value, String key) {
  if (!value.containsKey(key) || value[key] == null) return null;
  return _requiredInt(value, key);
}

bool _requiredBool(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is bool) return result;
  throw const FirstPlayableFirestoreStoreViolation('invalidPersistedDocument');
}

DateTime _requiredDateTime(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is DateTime) return result.toUtc();
  throw const FirstPlayableFirestoreStoreViolation('invalidPersistedDocument');
}

void _assertPublicOnly(Object? value, [String path = 'public']) {
  if (value is List<Object?>) {
    for (var index = 0; index < value.length; index += 1) {
      _assertPublicOnly(value[index], '$path[$index]');
    }
    return;
  }
  if (value is! Map<String, Object?>) return;
  for (final entry in value.entries) {
    if (_forbiddenPublicKeys.contains(entry.key)) {
      throw const FirstPlayableFirestoreStoreViolation(
        'privateFieldInPublicDocument',
      );
    }
    _assertPublicOnly(entry.value, '$path.${entry.key}');
  }
}

const Set<String> _forbiddenPublicKeys = <String>{
  'actorUid',
  'futureDeck',
  'memberUidByPlayerId',
  'privateDeckState',
  'seed',
  'seedBytes',
  'streamCounters',
};

final RegExp _identifier = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
