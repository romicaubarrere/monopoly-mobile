import 'dart:convert';

import 'package:board_game_contracts/game_contracts.dart';
import 'package:board_game_core/game_core.dart';

import 'semantic_fingerprint.dart';

final class ClientAuthorityContractViolation implements Exception {
  const ClientAuthorityContractViolation(this.code);

  final String code;

  @override
  String toString() => 'ClientAuthorityContractViolation: $code';
}

enum AuthorityCommandFamily {
  room('room'),
  game('game');

  const AuthorityCommandFamily(this.wireValue);

  final String wireValue;
}

enum AuthorityCommandStatus {
  accepted('accepted'),
  rejected('rejected'),
  duplicate('duplicate');

  const AuthorityCommandStatus(this.wireValue);

  final String wireValue;
}

/// Transport-neutral client request for one authoritative command.
///
/// The embedded command remains the canonical RoomCommand/GameCommand wire
/// envelope. Authentication is deliberately absent: a concrete transport adds
/// credentials out-of-band and Authority derives the actor UID from them.
/// [inputHash] covers semantic material only, so retrying after a lost ACK must
/// reuse this exact request instead of minting a new command identity.
final class AuthorityCommandRequest {
  AuthorityCommandRequest._({
    required this.family,
    required Map<String, Object?> command,
    required this._roomCommand,
    required this._gameCommand,
  }) : command = _immutableJson(command),
       inputHashVersion = ProtocolFoundation.inputHashVersion,
       inputHash = SemanticFingerprintV1.sha256Hex(
         _semanticMaterial(family, command),
       ) {
    _validateCommand(family, this.command);
    if ((family == AuthorityCommandFamily.room) != (_roomCommand != null) ||
        (family == AuthorityCommandFamily.game) != (_gameCommand != null)) {
      throw const ClientAuthorityContractViolation('commandFamilyMismatch');
    }
  }

  factory AuthorityCommandRequest.room(RoomCommand command) =>
      AuthorityCommandRequest._(
        family: AuthorityCommandFamily.room,
        command: command.toJson(),
        roomCommand: command,
        gameCommand: null,
      );

  /// Builds the client wire envelope from Engine's canonical GameCommand.
  ///
  /// Importing the pure-Dart contract does not run Engine logic in Flutter. It
  /// prevents this transport boundary from maintaining a second command schema
  /// or command-type catalog.
  factory AuthorityCommandRequest.game(GameCommand command) =>
      AuthorityCommandRequest._(
        family: AuthorityCommandFamily.game,
        command: command.toJson(),
        roomCommand: null,
        gameCommand: command,
      );

  /// Decodes the exact public wire envelope at Authority ingress.
  ///
  /// The semantic fingerprint is recomputed from the canonical command rather
  /// than trusted from the network. This keeps the HTTP boundary on the same
  /// schema and collision rules as the Flutter adapter.
  factory AuthorityCommandRequest.fromWireJson(Map<String, Object?> value) {
    _requireExactKeys(value, const <String>{
      'family',
      'inputHashVersion',
      'inputHash',
      'command',
    });
    final family = switch (value['family']) {
      'room' => AuthorityCommandFamily.room,
      'game' => AuthorityCommandFamily.game,
      _ => throw const ClientAuthorityContractViolation('invalidCommandFamily'),
    };
    if (value['inputHashVersion'] != ProtocolFoundation.inputHashVersion) {
      throw const ClientAuthorityContractViolation(
        'unsupportedInputHashVersion',
      );
    }
    final inputHash = value['inputHash'];
    if (inputHash is! String || !_sha256Pattern.hasMatch(inputHash)) {
      throw const ClientAuthorityContractViolation('invalidInputHash');
    }
    final command = _jsonObject(value['command'], 'invalidCommand');
    final request = switch (family) {
      AuthorityCommandFamily.room => AuthorityCommandRequest.room(
        _decodeRoomCommand(command),
      ),
      AuthorityCommandFamily.game => AuthorityCommandRequest.game(
        _decodeGameCommand(command),
      ),
    };
    if (request.inputHash != inputHash) {
      throw const ClientAuthorityContractViolation(
        'semanticFingerprintMismatch',
      );
    }
    return request;
  }

  final AuthorityCommandFamily family;
  final Map<String, Object?> command;
  final RoomCommand? _roomCommand;
  final GameCommand? _gameCommand;
  final int inputHashVersion;
  final String inputHash;

  String get commandId => command['commandId']! as String;

  /// Returns the already validated canonical room command.
  ///
  /// Authority executors use this instead of decoding [command] again and
  /// accidentally maintaining a second wire schema.
  RoomCommand get asRoomCommand {
    final value = _roomCommand;
    if (family != AuthorityCommandFamily.room || value == null) {
      throw const ClientAuthorityContractViolation('commandFamilyMismatch');
    }
    return value;
  }

  /// Returns the already validated canonical game command.
  ///
  /// The Engine receives this exact object, while [command] remains the
  /// immutable transport representation used for hashing and diagnostics.
  GameCommand get asGameCommand {
    final value = _gameCommand;
    if (family != AuthorityCommandFamily.game || value == null) {
      throw const ClientAuthorityContractViolation('commandFamilyMismatch');
    }
    return value;
  }

  Map<String, Object?> toWireJson() => <String, Object?>{
    'family': family.wireValue,
    'inputHashVersion': inputHashVersion,
    'inputHash': inputHash,
    'command': command,
  };

  String toCanonicalWireJson() =>
      SemanticFingerprintV1.canonicalJson(toWireJson());

  UncertainCommandIdentity get uncertainIdentity => UncertainCommandIdentity(
    commandId: commandId,
    inputHashVersion: inputHashVersion,
    inputHash: inputHash,
  );
}

/// Complete public game snapshot received from Authority.
///
/// The client replaces its cached snapshot with this value. There is no API for
/// submitting or merging client-owned state. Full domain validation remains in
/// Engine/Authority; this boundary validates protocol versions and privacy.
final class AuthorityPublicSnapshot {
  AuthorityPublicSnapshot(Map<String, Object?> snapshot)
    : snapshot = _immutableJson(snapshot) {
    final schemaVersion = this.snapshot['schemaVersion'];
    final stateVersion = this.snapshot['stateVersion'];
    final gameId = this.snapshot['gameId'];
    if (schemaVersion != 1) {
      throw const ClientAuthorityContractViolation(
        'unsupportedSnapshotSchemaVersion',
      );
    }
    if (stateVersion is! int || stateVersion < 0) {
      throw const ClientAuthorityContractViolation('invalidSnapshotVersion');
    }
    if (gameId is! String || gameId.isEmpty) {
      throw const ClientAuthorityContractViolation('invalidSnapshotGameId');
    }
    _rejectPrivateMaterial(this.snapshot);
  }

  final Map<String, Object?> snapshot;

  int get schemaVersion => snapshot['schemaVersion']! as int;
  int get stateVersion => snapshot['stateVersion']! as int;
  String get gameId => snapshot['gameId']! as String;

  Map<String, Object?> toWireJson() => snapshot;

  String toCanonicalJson() => SemanticFingerprintV1.canonicalJson(snapshot);
}

/// Complete public lobby snapshot received from Authority.
///
/// Flutter replaces its confirmed room context with this value before issuing
/// Ready/Start commands. Membership is expressed only with Authority-owned
/// player IDs; Firebase UIDs and private mappings are rejected recursively.
final class AuthorityPublicRoomSnapshot {
  AuthorityPublicRoomSnapshot(Map<String, Object?> snapshot)
    : snapshot = _immutableJson(snapshot) {
    final schemaVersion = this.snapshot['schemaVersion'];
    final roomVersion = this.snapshot['roomVersion'];
    final roomId = this.snapshot['roomId'];
    final status = this.snapshot['status'];
    final gameId = this.snapshot['gameId'];
    final hostPlayerId = this.snapshot['hostPlayerId'];
    final actorPlayerId = this.snapshot['actorPlayerId'];
    final presetId = this.snapshot['presetId'];
    final rulesVersion = this.snapshot['rulesVersion'];
    final members = this.snapshot['members'];
    if (schemaVersion != 1) {
      throw const ClientAuthorityContractViolation(
        'unsupportedRoomSnapshotSchemaVersion',
      );
    }
    if (roomVersion is! int || roomVersion < 1) {
      throw const ClientAuthorityContractViolation(
        'invalidRoomSnapshotVersion',
      );
    }
    if (roomId is! String || roomId.isEmpty) {
      throw const ClientAuthorityContractViolation('invalidRoomSnapshotRoomId');
    }
    if (gameId != null && (gameId is! String || gameId.isEmpty)) {
      throw const ClientAuthorityContractViolation('invalidRoomSnapshotGameId');
    }
    if (status is! String ||
        (status != 'open' && status != 'active') ||
        hostPlayerId is! String ||
        hostPlayerId.isEmpty ||
        actorPlayerId is! String ||
        actorPlayerId.isEmpty ||
        presetId is! String ||
        presetId.isEmpty ||
        rulesVersion is! String ||
        rulesVersion.isEmpty) {
      throw const ClientAuthorityContractViolation(
        'invalidRoomSnapshotMetadata',
      );
    }
    if ((status == 'open' && gameId != null) ||
        (status == 'active' && gameId == null)) {
      throw const ClientAuthorityContractViolation(
        'inconsistentRoomSnapshotGameRouting',
      );
    }
    if (members is! List<Object?> ||
        members.isEmpty ||
        members.any((member) {
          if (member is! Map<String, Object?>) return true;
          final playerId = member['playerId'];
          return playerId is! String ||
              playerId.isEmpty ||
              member['ready'] is! bool ||
              member['kind'] is! String;
        })) {
      throw const ClientAuthorityContractViolation(
        'invalidRoomSnapshotMembers',
      );
    }
    final playerIds = members
        .whereType<Map<String, Object?>>()
        .map((member) => member['playerId']! as String)
        .toList(growable: false);
    if (playerIds.toSet().length != playerIds.length ||
        !playerIds.contains(hostPlayerId) ||
        !playerIds.contains(actorPlayerId)) {
      throw const ClientAuthorityContractViolation(
        'inconsistentRoomSnapshotMembership',
      );
    }
    _rejectPrivateMaterial(this.snapshot);
  }

  final Map<String, Object?> snapshot;

  int get schemaVersion => snapshot['schemaVersion']! as int;
  int get roomVersion => snapshot['roomVersion']! as int;
  String get roomId => snapshot['roomId']! as String;

  /// Null while the confirmed lobby is still open; set once Authority starts
  /// its single game for this room. This value is public routing metadata, not
  /// a client-supplied session identifier.
  String? get gameId => snapshot['gameId'] as String?;

  Map<String, Object?> toWireJson() => snapshot;

  String toCanonicalJson() => SemanticFingerprintV1.canonicalJson(snapshot);
}

/// Safe command outcome returned to Flutter.
///
/// Accepted results advance exactly once; rejections do not mutate; duplicates
/// replay the durable result and may report either delta. Flutter never applies
/// events optimistically and instead converges on [snapshot] or its snapshot
/// stream.
final class AuthorityCommandReply {
  AuthorityCommandReply({
    required this.commandId,
    required this.status,
    required this.versionBefore,
    required this.versionAfter,
    this.errorCode,
    Map<String, Object?> publicResult = const <String, Object?>{},
    this.snapshot,
  }) : publicResult = _immutableJson(publicResult) {
    _identifier(commandId, 'invalidReplyCommandId');
    if (versionBefore < 0 || versionAfter < versionBefore) {
      throw const ClientAuthorityContractViolation('invalidReplyVersion');
    }
    final delta = versionAfter - versionBefore;
    if (delta > 1 ||
        status == AuthorityCommandStatus.accepted && delta != 1 ||
        status == AuthorityCommandStatus.rejected && delta != 0) {
      throw const ClientAuthorityContractViolation('invalidReplyVersion');
    }
    if (status == AuthorityCommandStatus.rejected &&
        (errorCode == null || errorCode!.isEmpty)) {
      throw const ClientAuthorityContractViolation('missingSafeErrorCode');
    }
    if (snapshot != null && snapshot!.stateVersion != versionAfter) {
      throw const ClientAuthorityContractViolation('replySnapshotMismatch');
    }
    _rejectPrivateMaterial(this.publicResult);
  }

  final String commandId;
  final AuthorityCommandStatus status;
  final int versionBefore;
  final int versionAfter;
  final String? errorCode;
  final Map<String, Object?> publicResult;
  final AuthorityPublicSnapshot? snapshot;

  /// Whether Authority's durable result is a safe rejection.
  ///
  /// A duplicate is deliberately kept as a transport/idempotency status, but
  /// it replays the original durable result in [publicResult]. A lost ACK for
  /// a rejected command must therefore remain rejected when the client retries
  /// the same command identity.
  bool get isRejectedOutcome =>
      status == AuthorityCommandStatus.rejected ||
      (status == AuthorityCommandStatus.duplicate &&
          publicResult['status'] == AuthorityCommandStatus.rejected.wireValue);

  Map<String, Object?> toWireJson() => <String, Object?>{
    'commandId': commandId,
    'status': status.wireValue,
    'versionBefore': versionBefore,
    'versionAfter': versionAfter,
    if (errorCode != null) 'errorCode': errorCode,
    'publicResult': publicResult,
    if (snapshot != null) 'snapshot': snapshot!.toWireJson(),
  };
}

final class UncertainCommandIdentity {
  UncertainCommandIdentity({
    required this.commandId,
    required this.inputHashVersion,
    required this.inputHash,
  }) {
    _identifier(commandId, 'invalidUncertainCommandId');
    if (inputHashVersion != ProtocolFoundation.inputHashVersion) {
      throw const ClientAuthorityContractViolation(
        'unsupportedInputHashVersion',
      );
    }
    if (!_sha256Pattern.hasMatch(inputHash)) {
      throw const ClientAuthorityContractViolation('invalidInputHash');
    }
  }

  final String commandId;
  final int inputHashVersion;
  final String inputHash;

  Map<String, Object?> toWireJson() => <String, Object?>{
    'commandId': commandId,
    'inputHashVersion': inputHashVersion,
    'inputHash': inputHash,
  };
}

final class AuthorityReconnectRequest {
  AuthorityReconnectRequest({
    required this.gameId,
    required this.observedStateVersion,
    this.uncertainCommand,
  }) {
    _identifier(gameId, 'invalidReconnectGameId');
    if (observedStateVersion < 0) {
      throw const ClientAuthorityContractViolation(
        'invalidObservedStateVersion',
      );
    }
  }

  factory AuthorityReconnectRequest.fromWireJson(Map<String, Object?> value) {
    _requireExactKeys(
      value,
      const <String>{'gameId', 'observedStateVersion', 'uncertainCommand'},
      optional: const <String>{'uncertainCommand'},
    );
    final gameId = value['gameId'];
    final observedStateVersion = value['observedStateVersion'];
    if (gameId is! String || gameId.isEmpty) {
      throw const ClientAuthorityContractViolation('invalidReconnectGameId');
    }
    if (observedStateVersion is! int || observedStateVersion < 0) {
      throw const ClientAuthorityContractViolation(
        'invalidObservedStateVersion',
      );
    }
    final uncertain = value['uncertainCommand'];
    UncertainCommandIdentity? identity;
    if (uncertain != null) {
      final object = _jsonObject(uncertain, 'invalidUncertainIdentity');
      _requireExactKeys(object, const <String>{
        'commandId',
        'inputHashVersion',
        'inputHash',
      });
      final commandId = object['commandId'];
      final inputHashVersion = object['inputHashVersion'];
      final inputHash = object['inputHash'];
      if (commandId is! String ||
          inputHashVersion is! int ||
          inputHash is! String) {
        throw const ClientAuthorityContractViolation(
          'invalidUncertainIdentity',
        );
      }
      identity = UncertainCommandIdentity(
        commandId: commandId,
        inputHashVersion: inputHashVersion,
        inputHash: inputHash,
      );
    }
    return AuthorityReconnectRequest(
      gameId: gameId,
      observedStateVersion: observedStateVersion,
      uncertainCommand: identity,
    );
  }

  final String gameId;
  final int observedStateVersion;
  final UncertainCommandIdentity? uncertainCommand;

  Map<String, Object?> toWireJson() => <String, Object?>{
    'gameId': gameId,
    'observedStateVersion': observedStateVersion,
    if (uncertainCommand != null)
      'uncertainCommand': uncertainCommand!.toWireJson(),
  };
}

enum ReconnectDisposition {
  upToDate('upToDate'),
  snapshotAdvanced('snapshotAdvanced'),
  uncertainConfirmed('uncertainConfirmed'),
  uncertainRejected('uncertainRejected'),
  retrySameCommand('retrySameCommand'),
  semanticCollision('semanticCollision');

  const ReconnectDisposition(this.wireValue);

  final String wireValue;
}

enum CommandResolutionAction {
  useDurableResult('useDurableResult'),
  retrySameCommand('retrySameCommand'),
  failClosed('failClosed');

  const CommandResolutionAction(this.wireValue);

  final String wireValue;
}

final class ReconnectCommandResolution {
  ReconnectCommandResolution({
    required this.identity,
    required this.action,
    Map<String, Object?>? publicResult,
    this.errorCode,
  }) : publicResult = publicResult == null
           ? null
           : _immutableJson(publicResult) {
    if (action == CommandResolutionAction.useDurableResult &&
        this.publicResult == null) {
      throw const ClientAuthorityContractViolation('missingDurableResult');
    }
    if (action != CommandResolutionAction.useDurableResult &&
        this.publicResult != null) {
      throw const ClientAuthorityContractViolation('unexpectedDurableResult');
    }
    if (action == CommandResolutionAction.failClosed &&
        (errorCode == null || errorCode!.isEmpty)) {
      throw const ClientAuthorityContractViolation('missingSafeErrorCode');
    }
    if (this.publicResult != null) {
      _rejectPrivateMaterial(this.publicResult!);
    }
  }

  final UncertainCommandIdentity identity;
  final CommandResolutionAction action;
  final Map<String, Object?>? publicResult;
  final String? errorCode;

  Map<String, Object?> toWireJson() => <String, Object?>{
    'identity': identity.toWireJson(),
    'action': action.wireValue,
    if (publicResult != null) 'publicResult': publicResult,
    if (errorCode != null) 'errorCode': errorCode,
  };
}

final class AuthorityReconnectReply {
  AuthorityReconnectReply({
    required this.disposition,
    required this.snapshot,
    this.commandResolution,
  }) {
    final expectedAction = switch (disposition) {
      ReconnectDisposition.uncertainConfirmed ||
      ReconnectDisposition.uncertainRejected =>
        CommandResolutionAction.useDurableResult,
      ReconnectDisposition.retrySameCommand =>
        CommandResolutionAction.retrySameCommand,
      ReconnectDisposition.semanticCollision =>
        CommandResolutionAction.failClosed,
      ReconnectDisposition.upToDate ||
      ReconnectDisposition.snapshotAdvanced => null,
    };
    if (expectedAction != commandResolution?.action) {
      throw const ClientAuthorityContractViolation(
        'reconnectResolutionMismatch',
      );
    }
  }

  final ReconnectDisposition disposition;
  final AuthorityPublicSnapshot snapshot;
  final ReconnectCommandResolution? commandResolution;

  Map<String, Object?> toWireJson() => <String, Object?>{
    'disposition': disposition.wireValue,
    'snapshot': snapshot.toWireJson(),
    if (commandResolution != null)
      'commandResolution': commandResolution!.toWireJson(),
  };
}

/// Port implemented by HTTP/Firebase infrastructure and consumed by Flutter.
///
/// A concrete adapter may attach authentication and transport metadata, but it
/// must send [request.command] and its command identity unchanged across retry.
abstract interface class CommandGateway {
  Future<AuthorityCommandReply> send(AuthorityCommandRequest request);
}

/// Flutter repository port for authoritative public state and reconnect.
///
/// Implementations expose replacement snapshots only. Private state and
/// client-to-authority snapshot merge are intentionally unrepresentable.
abstract interface class AuthoritySnapshotRepository {
  Stream<AuthorityPublicSnapshot> watchGame(String gameId);

  Future<AuthorityReconnectReply> reconnect(AuthorityReconnectRequest request);
}

/// Flutter repository port for authoritative public lobby replacement.
abstract interface class AuthorityRoomSnapshotRepository {
  Stream<AuthorityPublicRoomSnapshot> watchRoom(String roomId);
}

Map<String, Object?> _semanticMaterial(
  AuthorityCommandFamily family,
  Map<String, Object?> command,
) {
  final payload = command['payload'];
  if (payload is! Map<String, Object?>) {
    throw const ClientAuthorityContractViolation('invalidCommandPayload');
  }
  if (family == AuthorityCommandFamily.game) {
    return <String, Object?>{
      'v': ProtocolFoundation.inputHashVersion,
      'family': family.wireValue,
      'type': command['type'],
      'target': command['gameId'],
      'expectedVersion': command['expectedStateVersion'],
      'actorPlayerId': command['actorPlayerId'],
      'payload': payload,
    };
  }
  return <String, Object?>{
    'v': ProtocolFoundation.inputHashVersion,
    'family': family.wireValue,
    'type': command['type'],
    'target': payload['roomId'] ?? payload['roomCode'] ?? 'new-room',
    'expectedVersion': command['expectedRoomVersion'],
    'payload': payload,
  };
}

void _validateCommand(
  AuthorityCommandFamily family,
  Map<String, Object?> command,
) {
  _identifier(command['commandId'], 'invalidCommandId');
  _identifier(command['clientInstanceId'], 'invalidClientInstanceId');
  _identifier(command['type'], 'invalidCommandType');
  if (command['schemaVersion'] != 1) {
    throw const ClientAuthorityContractViolation(
      'unsupportedCommandSchemaVersion',
    );
  }
  if (command['payload'] is! Map<String, Object?>) {
    throw const ClientAuthorityContractViolation('invalidCommandPayload');
  }
  if (family == AuthorityCommandFamily.game) {
    _identifier(command['gameId'], 'invalidGameId');
    _identifier(command['actorPlayerId'], 'invalidActorPlayerId');
    final expected = command['expectedStateVersion'];
    if (expected is! int || expected < 0) {
      throw const ClientAuthorityContractViolation('invalidExpectedVersion');
    }
  } else {
    final expected = command['expectedRoomVersion'];
    if (expected != null && (expected is! int || expected < 0)) {
      throw const ClientAuthorityContractViolation('invalidExpectedVersion');
    }
  }
  _rejectPrivateMaterial(command);
}

Map<String, Object?> _immutableJson(Map<String, Object?> source) {
  try {
    return _freezeJson(jsonDecode(SemanticFingerprintV1.canonicalJson(source)))
        as Map<String, Object?>;
  } on ArgumentError {
    throw const ClientAuthorityContractViolation('invalidJsonMaterial');
  }
}

Object? _freezeJson(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final entry in value.entries) entry.key: _freezeJson(entry.value),
    });
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(_freezeJson));
  }
  return value;
}

void _identifier(Object? value, String code) {
  if (value is! String || value.isEmpty) {
    throw ClientAuthorityContractViolation(code);
  }
}

void _rejectPrivateMaterial(Object? value, [String? key]) {
  if (key != null && _privateKeys.contains(key.toLowerCase())) {
    throw const ClientAuthorityContractViolation('privateMaterialForbidden');
  }
  if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      _rejectPrivateMaterial(entry.value, entry.key);
    }
  } else if (value is List<Object?>) {
    for (final item in value) {
      _rejectPrivateMaterial(item);
    }
  }
}

/// Freezes and privacy-validates a public Authority response before egress.
Map<String, Object?> validatedAuthorityPublicWireObject(
  Map<String, Object?> value,
) {
  final result = _immutableJson(value);
  _rejectPrivateMaterial(result);
  return result;
}

Map<String, Object?> _jsonObject(Object? value, String code) {
  if (value is Map<String, Object?>) return value;
  throw ClientAuthorityContractViolation(code);
}

RoomCommand _decodeRoomCommand(Map<String, Object?> value) {
  try {
    _requireExactKeys(
      value,
      const <String>{
        'commandId',
        'schemaVersion',
        'expectedRoomVersion',
        'clientInstanceId',
        'type',
        'payload',
        'sentAt',
      },
      optional: const <String>{'expectedRoomVersion', 'sentAt'},
    );
    final type = RoomCommandType.values.singleWhere(
      (candidate) => candidate.wireValue == value['type'],
    );
    return RoomCommand(
      commandId: value['commandId']! as String,
      schemaVersion: value['schemaVersion']! as int,
      expectedRoomVersion: value['expectedRoomVersion'] as int?,
      clientInstanceId: value['clientInstanceId']! as String,
      type: type,
      payload: _jsonObject(value['payload'], 'invalidCommandPayload'),
      sentAt: _optionalWireDateTime(value['sentAt']),
    );
  } on ClientAuthorityContractViolation {
    rethrow;
  } on Object {
    throw const ClientAuthorityContractViolation('invalidCommand');
  }
}

GameCommand _decodeGameCommand(Map<String, Object?> value) {
  try {
    _requireExactKeys(
      value,
      const <String>{
        'commandId',
        'schemaVersion',
        'expectedStateVersion',
        'clientInstanceId',
        'gameId',
        'actorPlayerId',
        'type',
        'payload',
        'sentAt',
      },
      optional: const <String>{'sentAt'},
    );
    final type = GameCommandType.values.singleWhere(
      (candidate) => candidate.wireValue == value['type'],
    );
    return GameCommand(
      commandId: value['commandId']! as String,
      schemaVersion: value['schemaVersion']! as int,
      expectedStateVersion: value['expectedStateVersion']! as int,
      clientInstanceId: value['clientInstanceId']! as String,
      gameId: value['gameId']! as String,
      actorPlayerId: value['actorPlayerId']! as String,
      type: type,
      payload: _jsonObject(value['payload'], 'invalidCommandPayload'),
      sentAt: _optionalWireDateTime(value['sentAt']),
    );
  } on ClientAuthorityContractViolation {
    rethrow;
  } on Object {
    throw const ClientAuthorityContractViolation('invalidCommand');
  }
}

DateTime? _optionalWireDateTime(Object? value) {
  if (value == null) return null;
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  throw const ClientAuthorityContractViolation('invalidCommand');
}

void _requireExactKeys(
  Map<String, Object?> value,
  Set<String> allowed, {
  Set<String> optional = const <String>{},
}) {
  if (value.keys.any((key) => !allowed.contains(key)) ||
      allowed.difference(optional).any((key) => !value.containsKey(key))) {
    throw const ClientAuthorityContractViolation('invalidWireEnvelope');
  }
}

const Set<String> _privateKeys = <String>{
  'authorization',
  'authtoken',
  'authenticatedactoruid',
  'actoruid',
  'gamesecrets',
  'memberuidbyplayerid',
  'memberuids',
  'privatedeckstate',
  'seed',
  'seedbytes',
  'streamcounters',
  'futuredeck',
  'futuredeckorder',
  'token',
  'uid',
};

final RegExp _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');
