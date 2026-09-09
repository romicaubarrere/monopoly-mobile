import 'dart:convert';
import 'dart:io';

import 'package:board_backend_api/backend_api.dart' as api;
import 'package:board_command_service/command_service.dart';
import 'package:board_command_service/ingress/command_ingress.dart';
import 'package:board_command_service/observability/authority_observability.dart';
import 'package:board_game_contracts/game_contracts.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_roll_fixture.dart';

// Real executor and REST store, scripted numeric-loopback persistence. Receipts
// below come from actual first executions, not fabricated duplicate decisions.
// This peer measures adapter I/O; it is not Firestore atomicity/cloud evidence.
void main() {
  for (final accepted in [true, false]) {
    for (final failure in _DependencyFailure.values) {
      test(
        '${accepted ? 'accepted' : 'rejected'} replay survives ${failure.name}',
        () async {
          final peer = await _Peer.start(guestReady: accepted);
          addTearDown(peer.close);
          final material = _Material();
          final catalogs = _Catalogs();
          final executor = _executor(peer, material, catalogs);
          final request = _request();
          final initial = await _execute(executor, request);
          expect(
            initial.value.status,
            accepted
                ? api.AuthorityCommandStatus.accepted
                : api.AuthorityCommandStatus.rejected,
          );
          expect(peer.confirmedWrites, accepted ? 4 : 1);
          expect(peer.hasReceipt, isTrue);
          expect(peer.hasGame, accepted);
          if (!accepted) {
            expect(initial.value.errorCode, 'notAllPlayersReady');
          }
          final before = peer.documentSnapshot;
          peer.resetCounters();
          material.calls = 0;
          material.fail = failure != _DependencyFailure.catalog;
          catalogs.calls = 0;
          catalogs.fail = failure != _DependencyFailure.material;
          final capture = AuthorityExecutionMetricsCapture();

          final replay = await capture.run(() => _execute(executor, request));

          expect(replay.value.status, api.AuthorityCommandStatus.duplicate);
          expect(replay.outcome, AuthorityOutcome.duplicate);
          expect(replay.reason, AuthorityReason.duplicateCommand);
          expect(replay.value.errorCode, initial.value.errorCode);
          expect(replay.value.isRejectedOutcome, !accepted);
          expect(replay.value.versionBefore, initial.value.versionBefore);
          expect(replay.value.versionAfter, initial.value.versionAfter);
          expect(
            CanonicalDomainJson.encode(replay.value.publicResult) ==
                CanonicalDomainJson.encode(initial.value.publicResult),
            isTrue,
            reason: 'the exact durable result, including rejection, wins',
          );
          expect(peer.documentSnapshot == before, isTrue);
          expect(material.calls, 1);
          expect(catalogs.calls, 0);
          _counters(replay.metrics, peer, writes: 0);
          _counters(capture.metrics, peer, writes: 0);
          expect(replay.metrics.snapshotBytes, 0);
          expect(replay.metrics.stateVersion, initial.value.versionAfter);
          _captureMetadata(capture);
          expect(peer.commits, 0);
          expect(peer.rollbacks, 1);
        },
      );
    }
  }

  for (final differentActor in [true, false]) {
    test(
      '${differentActor ? 'actor' : 'hash'} collision survives both failed dependencies',
      () async {
        final peer = await _Peer.start();
        addTearDown(peer.close);
        final material = _Material();
        final catalogs = _Catalogs();
        final executor = _executor(peer, material, catalogs);
        final request = _request();
        final initial = await _execute(executor, request);
        expect(initial.value.status, api.AuthorityCommandStatus.accepted);
        expect(peer.hasReceipt, isTrue);
        final before = peer.documentSnapshot;
        peer.resetCounters();
        material.calls = 0;
        material.fail = true;
        catalogs.calls = 0;
        catalogs.fail = true;
        final collisionRequest = differentActor
            ? request
            : _request(expectedVersion: _roomVersion + 1);
        if (!differentActor) {
          expect(collisionRequest.inputHash != request.inputHash, isTrue);
        }
        final capture = AuthorityExecutionMetricsCapture();

        final collision = await capture.run(
          () => _execute(
            executor,
            collisionRequest,
            uid: differentActor ? 'uid-p2' : 'uid-p1',
          ),
        );

        expect(collision.outcome, AuthorityOutcome.collision);
        expect(collision.reason, AuthorityReason.commandIdCollision);
        expect(collision.value.status, api.AuthorityCommandStatus.rejected);
        expect(collision.value.errorCode, 'commandIdCollision');
        expect(collision.value.publicResult.containsKey('gameId'), isFalse);
        expect(peer.documentSnapshot == before, isTrue);
        expect(material.calls, 1);
        expect(catalogs.calls, 0);
        _counters(collision.metrics, peer, writes: 0);
        _counters(capture.metrics, peer, writes: 0);
        expect(collision.metrics.snapshotBytes, 0);
        _captureMetadata(capture);
        expect(peer.commits, 0);
        expect(peer.rollbacks, 1);
      },
    );
  }

  test(
    'missing receipt retains material error and stack after measured rollback',
    () async {
      final peer = await _Peer.start();
      addTearDown(peer.close);
      final material = _Material()..fail = true;
      final catalogs = _Catalogs()..fail = true;
      final executor = _executor(peer, material, catalogs);
      final before = peer.documentSnapshot;
      final capture = AuthorityExecutionMetricsCapture();
      Object? propagated;
      StackTrace? propagatedStack;

      try {
        await capture.run(() => _execute(executor, _request()));
      } on Object catch (error, stack) {
        propagated = error;
        propagatedStack = stack;
      }

      expect(identical(propagated, material.error), isTrue);
      expect(propagatedStack.toString(), material.stack.toString());
      expect(peer.documentSnapshot == before, isTrue);
      expect(peer.hasReceipt, isFalse);
      expect(peer.hasGame, isFalse);
      expect(material.calls, 1);
      expect(catalogs.calls, 0);
      _counters(capture.metrics, peer, writes: 0);
      _captureMetadata(capture);
      expect(peer.commits, 0);
      expect(peer.rollbacks, 1);
    },
  );

  for (final conflicts in [0, 1, 2]) {
    test(
      'healthy StartGame keeps one material through $conflicts conflicts',
      () async {
        final peer = await _Peer.start(conflicts: conflicts);
        addTearDown(peer.close);
        final material = _Material();
        final catalogs = _Catalogs();
        final executor = _executor(peer, material, catalogs);
        final capture = AuthorityExecutionMetricsCapture();

        final result = await capture.run(() => _execute(executor, _request()));

        expect(result.value.status, api.AuthorityCommandStatus.accepted);
        expect(result.value.publicResult['gameId'], _gameId);
        expect(peer.hasReceipt, isTrue);
        expect(peer.hasGame, isTrue);
        expect(material.calls, 1);
        expect(catalogs.calls, conflicts + 1);
        _counters(result.metrics, peer, attempts: conflicts + 1, writes: 4);
        _counters(capture.metrics, peer, attempts: conflicts + 1, writes: 4);
        final publicState = peer.publicState;
        expect(publicState['stateVersion'], 0);
        expect(result.metrics.stateVersion, _roomVersion + 1);
        expect(
          result.metrics.snapshotBytes,
          utf8.encode(CanonicalDomainJson.encode(publicState)).length,
        );
        _captureMetadata(capture);
        expect(peer.commits, conflicts + 1);
        expect(peer.rollbacks, conflicts);
        expect(peer.attemptedWrites, hasLength(conflicts + 1));
        expect(
          peer.attemptedWrites.every(
            (writes) => writes == peer.attemptedWrites.first,
          ),
          isTrue,
          reason:
              'retries must not reshuffle or replace candidate private data',
        );
      },
    );
  }
}

enum _DependencyFailure { material, catalog, both }

api.AuthorityCommandRequest _request({int expectedVersion = _roomVersion}) =>
    api.AuthorityCommandRequest.room(
      RoomCommand(
        commandId: _commandId,
        schemaVersion: 1,
        expectedRoomVersion: expectedVersion,
        clientInstanceId: 'synthetic-replay-client',
        type: RoomCommandType.startGame,
        payload: const {'roomId': _roomId},
      ),
    );

FirstPlayableAuthorityExecutor _executor(
  _Peer peer,
  _Material material,
  _Catalogs catalogs,
) => FirstPlayableAuthorityExecutor(
  store: peer.store,
  rulesCatalogRepository: catalogs,
  startMaterialFactory: material.call,
);

Future<AuthorityExecutionResult<api.AuthorityCommandReply>> _execute(
  FirstPlayableAuthorityExecutor executor,
  api.AuthorityCommandRequest request, {
  String uid = 'uid-p1',
}) => executor.executeCommand(
  context: IngressContext(requestReceivedAt: DateTime.utc(2026, 8, 25, 2)),
  identity: VerifiedIdentity(
    uid: uid,
    authTime: DateTime.utc(2026, 8, 25, 1, 59),
  ),
  request: request,
);

final class _Material {
  int calls = 0;
  bool fail = false;
  final error = StateError('synthetic-material-failure');
  final stack = StackTrace.fromString('synthetic material origin');

  Future<FirstPlayableStartMaterial> call(RoomCommand command) {
    calls += 1;
    if (fail) return Future.error(error, stack);
    return Future.value(
      FirstPlayableStartMaterial(gameId: _gameId, seed: syntheticRollSeed),
    );
  }
}

final class _Catalogs implements FirstPlayableRulesCatalogRepository {
  _Catalogs() {
    final catalog = syntheticRollCatalog();
    delegate = PinnedFirstPlayableRulesCatalogRepository(
      activeRulesVersion: catalog.rulesVersion,
      catalogs: [catalog],
    );
  }

  late final PinnedFirstPlayableRulesCatalogRepository delegate;
  int calls = 0;
  bool fail = false;

  @override
  RulesCatalog catalogForRoom({
    required String rulesVersion,
    required String presetId,
  }) {
    calls += 1;
    if (fail) {
      throw const FirstPlayableRulesCatalogRepositoryViolation(
        'rulesCatalogUnavailable',
      );
    }
    return delegate.catalogForRoom(
      rulesVersion: rulesVersion,
      presetId: presetId,
    );
  }

  @override
  RulesCatalog catalogForNewRoom({required String presetId}) =>
      delegate.catalogForNewRoom(presetId: presetId);

  @override
  RulesCatalog catalogForGame(PublicGameState state) =>
      delegate.catalogForGame(state);
}

void _counters(
  AuthorityExecutionMetrics metrics,
  _Peer peer, {
  int attempts = 1,
  required int writes,
}) {
  expect(metrics.retryCount, attempts - 1);
  expect(metrics.conflictCount, attempts - 1);
  expect(metrics.firestoreReadCount, 3 * attempts);
  expect(metrics.firestoreWriteCount, writes);
  expect(metrics.bytesRead, peer.responseBytes);
  expect(metrics.bytesWritten, peer.requestBytes);
  expect(metrics.bytesRead, greaterThan(0));
  expect(metrics.bytesWritten, greaterThan(0));
  expect(metrics.coldStart, isFalse);
  expect(peer.confirmedWrites, writes);
  expect(peer.begins, attempts);
  expect(peer.requestedDocuments, hasLength(attempts));
  for (final batch in peer.requestedDocuments) {
    expect(batch, [
      'rooms/$_roomId',
      'roomSecrets/$_roomId',
      'roomCommands/$_commandId',
    ]);
  }
}

void _captureMetadata(AuthorityExecutionMetricsCapture capture) {
  expect(capture.metrics.snapshotBytes, 0);
  expect(capture.metrics.schemaVersion, isNull);
  expect(capture.metrics.stateVersion, isNull);
}

final class _Peer {
  _Peer(this.server, this.conflicts, bool guestReady) {
    _documents.addAll({
      'rooms/$_roomId': _fields({
        'schemaVersion': 1,
        'roomId': _roomId,
        'roomVersion': _roomVersion,
        'status': 'open',
        'hostUid': 'uid-p1',
        'presetId': 'express',
        'frozenRulesVersion': 'synthetic-rules-vp0',
        'memberUids': ['uid-p1', 'uid-p2'],
        'readyByUid': {'uid-p1': true, 'uid-p2': guestReady},
      }),
      'roomSecrets/$_roomId': _fields({
        'schemaVersion': 1,
        'memberUidByPlayerId': {'p1': 'uid-p1', 'p2': 'uid-p2'},
      }),
    });
    store = FirstPlayableFirestoreRestStore(
      config: FirstPlayableFirestoreRestConfig.emulator(
        projectId: 'demo-room-replay-dependency',
        host: '127.0.0.1:${server.port}',
        maxAttempts: 3,
      ),
      httpClient: client,
    );
    server.listen(_handle);
  }

  static Future<_Peer> start({
    int conflicts = 0,
    bool guestReady = true,
  }) async => _Peer(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    conflicts,
    guestReady,
  );

  final HttpServer server;
  final HttpClient client = HttpClient();
  late final FirstPlayableFirestoreRestStore store;
  final _documents = <String, Map<String, Object?>>{};
  final requestedDocuments = <List<String>>[];
  final attemptedWrites = <String>[];
  int conflicts;
  int begins = 0;
  int commits = 0;
  int rollbacks = 0;
  int confirmedWrites = 0;
  int requestBytes = 0;
  int responseBytes = 0;

  bool get hasReceipt => _documents.containsKey('roomCommands/$_commandId');
  bool get hasGame => _documents.containsKey('games/$_gameId');
  String get documentSnapshot => CanonicalDomainJson.encode(_documents);
  Map<String, Object?> get publicState =>
      _decodeValue(_documents['games/$_gameId']!['publicState'])
          as Map<String, Object?>;

  void resetCounters() {
    begins = 0;
    commits = 0;
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
        response = {'transaction': 'synthetic-replay-${++begins}'};
      case 'batchGet':
        final names = (body['documents']! as List).cast<String>();
        requestedDocuments.add([
          for (final name in names) name.split('/documents/').last,
        ]);
        response = [
          for (final name in names)
            if (_documents[name.split('/documents/').last] case final fields?)
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
            'error': {'status': 'ABORTED', 'message': 'synthetic ñ'},
          };
        } else {
          for (final write in writes) {
            final update = write['update']! as Map<String, Object?>;
            final path = (update['name']! as String).split('/documents/').last;
            final fields = update['fields']! as Map<String, Object?>;
            // This peer supports the store's top-level field masks only.
            if (write['updateMask'] case final Map<String, Object?> mask) {
              final paths = (mask['fieldPaths']! as List).cast<String>();
              if (paths.any((path) => !fields.containsKey(path))) {
                throw StateError('unsupportedSyntheticFieldMask');
              }
              _documents[path] = {...?_documents[path], ...fields};
            } else {
              _documents[path] = {...fields};
            }
          }
          confirmedWrites += writes.length;
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

Map<String, Object?> _fields(Map<String, Object?> value) => {
  for (final entry in value.entries) entry.key: _value(entry.value),
};

Map<String, Object?> _value(Object? value) => switch (value) {
  final String value => {'stringValue': value},
  final int value => {'integerValue': value.toString()},
  final bool value => {'booleanValue': value},
  final List<Object?> value => {
    'arrayValue': {'values': value.map(_value).toList()},
  },
  final Map<String, Object?> value => {
    'mapValue': {'fields': _fields(value)},
  },
  null => {'nullValue': null},
  _ => throw StateError('unsupportedSyntheticRoomFixture'),
};

Object? _decodeValue(Object? encoded) {
  final value = encoded! as Map<String, Object?>;
  if (value.containsKey('stringValue')) return value['stringValue'];
  if (value.containsKey('integerValue')) {
    return int.parse(value['integerValue']! as String);
  }
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
  throw StateError('unsupportedSyntheticPublicField');
}

const _roomId = 'room-replay-dependency';
const _roomVersion = 7;
const _commandId = 'cmd-start-replay-dependency';
const _gameId = 'game-replay-dependency';
