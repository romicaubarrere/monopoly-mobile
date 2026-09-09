import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:board_backend_api/backend_api.dart' as api;
import 'package:board_command_service/command_service.dart';
import 'package:board_command_service/ingress/command_ingress.dart';
import 'package:board_command_service/observability/authority_observability.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_roll_fixture.dart';

// Real executor, Engine, catalog repository, codec and REST store. A scripted
// numeric-loopback peer persists their actual writes in memory; it does not
// prove Firestore isolation, billed traffic, production behavior or DEC-065.
void main() {
  for (final accepted in [true, false]) {
    for (final mode in _unavailableModes) {
      test('${accepted ? 'accepted' : 'rejected'} durable replay survives '
          '${mode.name} catalog', () async {
        final peer = await _Peer.start();
        addTearDown(peer.close);
        final catalogs = _Catalogs();
        final executor = _executor(peer, catalogs);
        final request = _request(expectedVersion: accepted ? 0 : 7);
        final initial = await _execute(executor, request);
        expect(
          initial.value.status,
          accepted
              ? api.AuthorityCommandStatus.accepted
              : api.AuthorityCommandStatus.rejected,
        );
        expect(peer.confirmedWrites, accepted ? 3 : 1);
        expect(peer.hasReceipt, isTrue);
        if (!accepted) expect(initial.value.errorCode, 'staleVersion');
        final before = peer.documentSnapshot;
        peer.resetCounters();
        catalogs.mode = mode;
        catalogs.calls = 0;
        _assertCatalogUnavailable(catalogs);
        final capture = AuthorityExecutionMetricsCapture();

        final replay = await capture.run(() => _execute(executor, request));

        expect(replay.outcome, AuthorityOutcome.duplicate);
        expect(replay.reason, AuthorityReason.duplicateCommand);
        expect(replay.value.status, api.AuthorityCommandStatus.duplicate);
        expect(replay.value.isRejectedOutcome, !accepted);
        expect(replay.value.errorCode, initial.value.errorCode);
        expect(replay.value.versionBefore, initial.value.versionBefore);
        expect(replay.value.versionAfter, initial.value.versionAfter);
        expect(
          CanonicalDomainJson.encode(replay.value.publicResult) ==
              CanonicalDomainJson.encode(initial.value.publicResult),
          isTrue,
          reason: 'replay must return the exact historical public result',
        );
        expect(
          replay.value.snapshot,
          isNull,
          reason: 'replay does not certify or replace the current snapshot',
        );
        expect(
          peer.documentSnapshot == before,
          isTrue,
          reason: 'public, private RNG and receipt documents stay identical',
        );
        expect(catalogs.calls, 0);
        _counters(replay.metrics, peer, writes: 0);
        _counters(capture.metrics, peer, writes: 0);
        expect(replay.metrics.snapshotBytes, 0);
        _captureDefaults(capture);
        expect(peer.commits, 0);
        expect(peer.rollbacks, 1);
      });
    }
  }

  for (final differentActor in [true, false]) {
    test(
      '${differentActor ? 'actor' : 'hash'} collision survives missing catalog '
      'without exposing the original result',
      () async {
        final peer = await _Peer.start();
        addTearDown(peer.close);
        final catalogs = _Catalogs();
        final executor = _executor(peer, catalogs);
        final original = _request();
        final initial = await _execute(executor, original);
        expect(initial.value.status, api.AuthorityCommandStatus.accepted);
        expect(peer.hasReceipt, isTrue);
        final before = peer.documentSnapshot;
        peer.resetCounters();
        catalogs.mode = _CatalogMode.missing;
        catalogs.calls = 0;
        final request = differentActor
            ? original
            : _request(expectedVersion: 1);
        if (!differentActor) {
          expect(request.inputHash != original.inputHash, isTrue);
        }
        final capture = AuthorityExecutionMetricsCapture();

        final collision = await capture.run(
          () => _execute(
            executor,
            request,
            uid: differentActor ? 'uid-p2' : 'uid-p1',
          ),
        );

        expect(collision.outcome, AuthorityOutcome.collision);
        expect(collision.reason, AuthorityReason.commandIdCollision);
        expect(collision.value.status, api.AuthorityCommandStatus.rejected);
        expect(collision.value.errorCode, 'commandIdCollision');
        expect(
          collision.value.publicResult.keys,
          unorderedEquals([
            'commandId',
            'status',
            'stateVersionBefore',
            'stateVersionAfter',
            'errorCode',
          ]),
        );
        expect(collision.value.snapshot, isNull);
        expect(peer.documentSnapshot == before, isTrue);
        expect(catalogs.calls, 0);
        _counters(collision.metrics, peer, writes: 0);
        _counters(capture.metrics, peer, writes: 0);
        expect(collision.metrics.snapshotBytes, 0);
        _captureDefaults(capture);
        expect(peer.commits, 0);
        expect(peer.rollbacks, 1);
      },
    );
  }

  test(
    'without a receipt catalog errors retain original identity and stack',
    () async {
      final peer = await _Peer.start();
      addTearDown(peer.close);
      final catalogs = _Catalogs();
      final executor = _executor(peer, catalogs);
      final before = peer.documentSnapshot;
      for (final mode in _unavailableModes) {
        peer.resetCounters();
        catalogs.mode = mode;
        catalogs.calls = 0;
        final capture = AuthorityExecutionMetricsCapture();
        final failure = await _catchFailure(
          capture.run(() => _execute(executor, _request())),
        );
        expect(identical(failure.$1, catalogs.originalError), isTrue);
        expect(failure.$2.toString(), catalogs.originalStack.toString());
        expect(
          failure.$1,
          isA<FirstPlayableRulesCatalogRepositoryViolation>().having(
            (error) => error.code,
            'code',
            mode.errorCode,
          ),
        );
        expect(catalogs.calls, 1);
        expect(peer.documentSnapshot == before, isTrue);
        expect(peer.hasReceipt, isFalse);
        _counters(capture.metrics, peer, writes: 0);
        _captureDefaults(capture);
        expect(peer.commits, 0);
        expect(peer.rollbacks, 1);
      }
    },
  );

  test('same current view still requires catalog for a new command, GET and reconnect', () async {
    final peer = await _Peer.start();
    addTearDown(peer.close);
    final catalogs = _Catalogs();
    final executor = _executor(peer, catalogs);
    final request = _request();
    final initial = await _execute(executor, request);
    expect(initial.value.status, api.AuthorityCommandStatus.accepted);
    final receipt = peer.documents[_receiptPath]!;
    final context = IngressContext(requestReceivedAt: DateTime.utc(2026, 9, 9));
    final identity = VerifiedIdentity(
      uid: 'uid-p1',
      authTime: DateTime.utc(2026, 9, 8),
    );
    for (final mode in _unavailableModes) {
      for (final operation in ['withoutReceipt', 'GET', 'reconnect']) {
        // Deliberate fixture-only receipt absence; public/private state remains
        // exactly the same as the successful Roll. Reads retain the receipt.
        if (operation == 'withoutReceipt') {
          peer.documents.remove(_receiptPath);
        } else {
          peer.documents[_receiptPath] = receipt;
        }
        final before = peer.documentSnapshot;
        peer.resetCounters();
        catalogs.mode = mode;
        catalogs.calls = 0;
        final capture = AuthorityExecutionMetricsCapture();
        final failure = await _catchFailure(
          capture.run<Object?>(
            () async => switch (operation) {
              'withoutReceipt' => await _execute(executor, request),
              'GET' => await executor.readPublicGame(
                context: context,
                identity: identity,
                gameId: _gameId,
              ),
              _ => await executor.reconnect(
                context: context,
                identity: identity,
                request: api.AuthorityReconnectRequest(
                  gameId: _gameId,
                  observedStateVersion: 1,
                  uncertainCommand: request.uncertainIdentity,
                ),
              ),
            },
          ),
        );
        expect(identical(failure.$1, catalogs.originalError), isTrue);
        expect(failure.$2.toString(), catalogs.originalStack.toString());
        expect(
          failure.$1,
          isA<FirstPlayableRulesCatalogRepositoryViolation>().having(
            (error) => error.code,
            'code',
            mode.errorCode,
          ),
        );
        expect(catalogs.calls, 1);
        expect(peer.documentSnapshot == before, isTrue);
        _counters(
          capture.metrics,
          peer,
          writes: 0,
          includeReceipt: operation != 'GET',
        );
        _captureDefaults(capture);
        expect(peer.commits, 0);
        expect(peer.rollbacks, 1);
      }
    }
  });

  for (final invalid in ['receipt', 'public', 'private']) {
    test(
      '$invalid document corruption is not bypassed by a persisted receipt',
      () async {
        final peer = await _Peer.start();
        addTearDown(peer.close);
        final catalogs = _Catalogs();
        final executor = _executor(peer, catalogs);
        final request = _request();
        final initial = await _execute(executor, request);
        expect(initial.value.status, api.AuthorityCommandStatus.accepted);
        expect(peer.hasReceipt, isTrue);
        if (invalid == 'receipt') {
          // Deliberately invalid persisted fingerprint, never a fabricated v2.
          peer.documents[_receiptPath]!['inputHash'] = _value('invalid-hash');
        } else {
          peer.documents.remove(
            invalid == 'public' ? _publicPath : _privatePath,
          );
        }
        final before = peer.documentSnapshot;
        peer.resetCounters();
        catalogs.mode = _CatalogMode.missing;
        catalogs.calls = 0;
        final capture = AuthorityExecutionMetricsCapture();
        final failure = await _catchFailure(
          capture.run(() => _execute(executor, request)),
        );
        if (invalid == 'receipt') {
          expect(
            failure.$1,
            isA<AuthorityReconnectViolation>().having(
              (error) => error.code,
              'code',
              'invalidDurableReceipt',
            ),
          );
        } else {
          expect(
            failure.$1,
            isA<FirstPlayableFirestoreStoreViolation>().having(
              (error) => error.code,
              'code',
              'gameUnavailable',
            ),
          );
        }
        expect(
          catalogs.calls,
          0,
          reason: 'decode fails before the evaluator callback',
        );
        expect(peer.documentSnapshot == before, isTrue);
        _counters(capture.metrics, peer, writes: 0);
        _captureDefaults(capture);
        expect(peer.commits, 0);
        expect(peer.rollbacks, 1);
      },
    );
  }

  for (final conflicts in [0, 1, 2]) {
    test(
      'healthy Roll retries $conflicts conflicts with one confirmed RNG advance',
      () async {
        final peer = await _Peer.start(conflicts: conflicts);
        addTearDown(peer.close);
        final catalogs = _Catalogs();
        final capture = AuthorityExecutionMetricsCapture();
        final result = await capture.run(
          () => _execute(_executor(peer, catalogs), _request()),
        );
        expect(result.value.status, api.AuthorityCommandStatus.accepted);
        expect(result.value.versionBefore, 0);
        expect(result.value.versionAfter, 1);
        expect(peer.hasReceipt, isTrue);
        expect(peer.confirmedCommits, 1);
        expect(peer.commits, conflicts + 1);
        expect(peer.rollbacks, conflicts);
        expect(catalogs.calls, conflicts + 1);
        expect(peer.attemptedWrites, hasLength(conflicts + 1));
        expect(
          peer.attemptedWrites.every(
            (value) => value == peer.attemptedWrites.first,
          ),
          isTrue,
          reason: 'retry payload, receipt and RNG successor must be identical',
        );
        final publicState = _decodeValue(
          peer.documents[_publicPath]!['publicState'],
        ) as Map<String, Object?>;
        expect(publicState['stateVersion'], 1);
        final counters = _decodeValue(
          peer.documents[_privatePath]!['streamCounters'],
        ) as Map<String, Object?>;
        expect((counters[RngStream.dice.label]! as int) > 0, isTrue);
        expect(
          _decodeValue(peer.documents[_privatePath]!['seedBytes']) ==
              base64Encode(syntheticRollSeed),
          isTrue,
        );
        _counters(result.metrics, peer, attempts: conflicts + 1, writes: 3);
        _counters(capture.metrics, peer, attempts: conflicts + 1, writes: 3);
        expect(
          result.metrics.snapshotBytes,
          utf8.encode(CanonicalDomainJson.encode(publicState)).length,
        );
        _captureDefaults(capture);
      },
    );
  }
}

api.AuthorityCommandRequest _request({int expectedVersion = 0}) =>
    api.AuthorityCommandRequest.game(
      syntheticRollCommand(
        commandId: _commandId,
        expectedStateVersion: expectedVersion,
      ),
    );

FirstPlayableAuthorityExecutor _executor(_Peer peer, _Catalogs catalogs) =>
    FirstPlayableAuthorityExecutor(
      store: peer.store,
      rulesCatalogRepository: catalogs,
    );

Future<AuthorityExecutionResult<api.AuthorityCommandReply>> _execute(
  FirstPlayableAuthorityExecutor executor,
  api.AuthorityCommandRequest request, {
  String uid = 'uid-p1',
}) => executor.executeCommand(
  context: IngressContext(requestReceivedAt: DateTime.utc(2026, 9, 9)),
  identity: VerifiedIdentity(uid: uid, authTime: DateTime.utc(2026, 9, 8)),
  request: request,
);

Future<(Object, StackTrace)> _catchFailure(Future<Object?> operation) async {
  try {
    await operation;
  } on Object catch (error, stack) {
    return (error, stack);
  }
  fail('Expected the operation to fail');
}

void _captureDefaults(AuthorityExecutionMetricsCapture capture) {
  expect(capture.metrics.snapshotBytes, 0);
  expect(capture.metrics.schemaVersion, isNull);
  expect(capture.metrics.stateVersion, isNull);
}

void _counters(
  AuthorityExecutionMetrics metrics,
  _Peer peer, {
  int attempts = 1,
  required int writes,
  bool includeReceipt = true,
}) {
  expect(metrics.retryCount, attempts - 1);
  expect(metrics.conflictCount, attempts - 1);
  expect(metrics.firestoreReadCount, (includeReceipt ? 3 : 2) * attempts);
  expect(metrics.firestoreWriteCount, writes);
  expect(metrics.bytesRead, peer.responseBytes);
  expect(metrics.bytesWritten, peer.requestBytes);
  expect(metrics.bytesRead, greaterThan(0));
  expect(metrics.bytesWritten, greaterThan(0));
  expect(metrics.coldStart, isFalse);
  expect(peer.confirmedWrites, writes);
  expect(peer.requestedDocuments, hasLength(attempts));
  for (final paths in peer.requestedDocuments) {
    expect(paths, [
      _publicPath,
      _privatePath,
      if (includeReceipt) _receiptPath,
    ]);
  }
}

enum _CatalogMode {
  healthy,
  missing,
  mismatch,
  presetMismatch;

  String get errorCode => switch (this) {
    missing => 'rulesCatalogUnavailable',
    mismatch => 'persistedBoardCatalogMismatch',
    presetMismatch => 'persistedPresetCatalogMismatch',
    healthy => throw StateError('healthyHasNoFailure'),
  };
}

const _unavailableModes = [
  _CatalogMode.missing,
  _CatalogMode.mismatch,
  _CatalogMode.presetMismatch,
];

void _assertCatalogUnavailable(_Catalogs catalogs) {
  expect(
    () => catalogs.current.catalogForGame(syntheticRollState()),
    throwsA(
      isA<FirstPlayableRulesCatalogRepositoryViolation>().having(
        (error) => error.code,
        'code',
        catalogs.mode.errorCode,
      ),
    ),
  );
}

final class _Catalogs implements FirstPlayableRulesCatalogRepository {
  _Catalogs() {
    final base = syntheticRollCatalog();
    for (final mode in _CatalogMode.values) {
      final catalog = RulesCatalog(
        rulesVersion: mode == _CatalogMode.missing
            ? 'synthetic-other-rules'
            : base.rulesVersion,
        boardDefinitionVersion: base.boardDefinitionVersion,
        economyVersion: base.economyVersion,
        deckCatalogVersion: base.deckCatalogVersion,
        presetCatalogVersion: mode == _CatalogMode.presetMismatch
            ? 'synthetic-other-presets'
            : base.presetCatalogVersion,
        ruleFlags: base.ruleFlags,
        boardDefinition: mode == _CatalogMode.mismatch
            ? BoardDefinition(
                boardId: 'synthetic-other-board',
                spaces: base.boardDefinition.spaces,
                groups: base.boardDefinition.groups,
              )
            : base.boardDefinition,
        economyCatalog: base.economyCatalog,
        deckCatalog: base.deckCatalog,
        presets: base.presets,
      );
      repositories[mode] = PinnedFirstPlayableRulesCatalogRepository(
        activeRulesVersion: catalog.rulesVersion,
        catalogs: [catalog],
      );
    }
  }
  final repositories =
      <_CatalogMode, PinnedFirstPlayableRulesCatalogRepository>{};
  _CatalogMode mode = _CatalogMode.healthy;
  var calls = 0;
  Object? originalError;
  StackTrace? originalStack;
  PinnedFirstPlayableRulesCatalogRepository get current => repositories[mode]!;
  @override
  RulesCatalog catalogForGame(PublicGameState state) {
    calls += 1;
    try {
      return current.catalogForGame(state);
    } on Object catch (error, stack) {
      originalError = error;
      originalStack = stack;
      rethrow;
    }
  }

  @override
  RulesCatalog catalogForNewRoom({required String presetId}) =>
      throw UnsupportedError('unusedRoomPath');
  @override
  RulesCatalog catalogForRoom({
    required String rulesVersion,
    required String presetId,
  }) => throw UnsupportedError('unusedRoomPath');
}

final class _Peer {
  _Peer(this.server, this.conflicts) {
    store = FirstPlayableFirestoreRestStore(
      config: FirstPlayableFirestoreRestConfig.emulator(
        projectId: 'demo-game-replay-catalog',
        host: '127.0.0.1:${server.port}',
        maxAttempts: 3,
      ),
      httpClient: client,
    );
    documents.addAll({
      _publicPath: _fields({
        'schemaVersion': 1,
        'stateVersion': 0,
        'memberUids': ['uid-p1', 'uid-p2'],
        'publicState': syntheticRollState().toJson(),
      }),
      _privatePath: _fields({
        'schemaVersion': 1,
        'rngVersion': canonicalRngVersion,
        'seedBytes': Uint8List.fromList(syntheticRollSeed),
        'streamCounters': {
          for (final stream in RngStream.values) stream.label: 0,
        },
        'memberUidByPlayerId': {'p1': 'uid-p1', 'p2': 'uid-p2'},
      }),
    });
    server.listen(_handle);
  }
  static Future<_Peer> start({int conflicts = 0}) async =>
      _Peer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0), conflicts);
  final HttpServer server;
  final HttpClient client = HttpClient();
  late final FirstPlayableFirestoreRestStore store;
  final documents = <String, Map<String, Object?>>{};
  final requestedDocuments = <List<String>>[];
  final attemptedWrites = <String>[];
  int conflicts;
  var begins = 0;
  var commits = 0;
  var confirmedCommits = 0;
  var rollbacks = 0;
  var confirmedWrites = 0;
  var requestBytes = 0;
  var responseBytes = 0;
  bool get hasReceipt => documents.containsKey(_receiptPath);
  // Canonical snapshots include private bytes but are compared only in memory;
  // assertions deliberately print a boolean, never these document strings.
  String get documentSnapshot => CanonicalDomainJson.encode(documents);
  void resetCounters() {
    begins = 0;
    commits = 0;
    confirmedCommits = 0;
    rollbacks = 0;
    confirmedWrites = 0;
    requestBytes = 0;
    responseBytes = 0;
    requestedDocuments.clear();
    attemptedWrites.clear();
  }

  Future<void> _handle(HttpRequest request) async {
    final bytes = await request.fold<List<int>>(
      [],
      (all, chunk) => all..addAll(chunk),
    );
    final body = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    requestBytes += bytes.length;
    Object response = <String, Object?>{};
    var status = HttpStatus.ok;
    switch (request.uri.path.split(':').last) {
      case 'beginTransaction':
        response = {'transaction': 'synthetic-game-replay-${++begins}'};
      case 'batchGet':
        final names = (body['documents']! as List).cast<String>();
        requestedDocuments.add([
          for (final name in names) name.split('/documents/').last,
        ]);
        response = [
          for (final name in names)
            if (documents[name.split('/documents/').last] case final fields?)
              {
                'found': {'name': name, 'fields': fields},
              }
            else
              {'missing': name},
        ];
      case 'commit':
        commits += 1;
        final writes = (body['writes']! as List).cast<Map<String, Object?>>();
        attemptedWrites.add(CanonicalDomainJson.encode({'writes': writes}));
        if (conflicts > 0) {
          conflicts -= 1;
          status = HttpStatus.conflict;
          response = {
            'error': {'status': 'ABORTED', 'message': 'synthetic ñ🎲'},
          };
        } else {
          for (final write in writes) {
            final update = write['update']! as Map<String, Object?>;
            final path = (update['name']! as String).split('/documents/').last;
            final fields = update['fields']! as Map<String, Object?>;
            // Only the adapter's top-level update masks are implemented here.
            if (write['updateMask'] case final Map<String, Object?> mask) {
              final paths = (mask['fieldPaths']! as List).cast<String>();
              if (paths.any((path) => !fields.containsKey(path))) {
                throw StateError('unsupportedSyntheticFieldMask');
              }
              documents[path] = {...?documents[path], ...fields};
            } else {
              documents[path] = {...fields};
            }
          }
          confirmedWrites += writes.length;
          confirmedCommits += 1;
        }
      case 'rollback':
        rollbacks += 1;
      default:
        status = HttpStatus.notFound;
    }
    final encoded = utf8.encode(jsonEncode(response));
    responseBytes += encoded.length;
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.add(encoded);
    await request.response.close();
  }

  Future<void> close() async {
    client.close(force: true);
    await server.close(force: true);
  }
}

Map<String, Object?> _fields(Map<String, Object?> fields) => {
  for (final entry in fields.entries) entry.key: _value(entry.value),
};
Map<String, Object?> _value(Object? value) => switch (value) {
  null => {'nullValue': null},
  final String value => {'stringValue': value},
  final int value => {'integerValue': value.toString()},
  final bool value => {'booleanValue': value},
  final Uint8List value => {'bytesValue': base64Encode(value)},
  final List<Object?> value => {
    'arrayValue': {'values': value.map(_value).toList()},
  },
  final Map<String, Object?> value => {
    'mapValue': {'fields': _fields(value)},
  },
  _ => throw StateError('unsupportedSyntheticValue'),
};
Object? _decodeValue(Object? encoded) {
  final value = encoded! as Map<String, Object?>;
  if (value.containsKey('stringValue')) return value['stringValue'];
  if (value.containsKey('integerValue')) {
    return int.parse(value['integerValue']! as String);
  }
  if (value.containsKey('bytesValue')) return value['bytesValue'];
  if (value.containsKey('booleanValue')) return value['booleanValue'];
  if (value.containsKey('nullValue')) return null;
  if (value['mapValue'] case final Map<String, Object?> map) {
    final fields = map['fields']! as Map<String, Object?>;
    return <String, Object?>{
      for (final entry in fields.entries) entry.key: _decodeValue(entry.value),
    };
  }
  if (value['arrayValue'] case final Map<String, Object?> array) {
    return (array['values']! as List).map(_decodeValue).toList();
  }
  throw StateError('unsupportedSyntheticField');
}

const _gameId = 'game-vp0';
const _commandId = 'cmd-game-replay';
const _publicPath = 'games/$_gameId';
const _privatePath = 'gameSecrets/$_gameId';
const _receiptPath = 'games/$_gameId/commands/$_commandId';
