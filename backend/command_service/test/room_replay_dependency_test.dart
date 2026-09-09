import 'dart:async';

import 'package:board_backend_api/backend_api.dart' as api;
import 'package:board_command_service/command_service.dart' as service;
import 'package:board_command_service/ingress/command_ingress.dart';
import 'package:board_command_service/observability/authority_observability.dart';
import 'package:board_game_contracts/game_contracts.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_roll_fixture.dart';

// Real executor/planner, synthetic catalog and in-memory transaction callbacks.
// Logical reads/writes below model the adapter contract; they are not measured
// Firestore traffic, durable concurrency, a deployed service or DEC-065 content.
void main() {
  for (final accepted in <bool>[true, false]) {
    for (final unavailable in <String>[
      'missingFactory',
      'syncFactory',
      'asyncFactory',
      'catalog',
    ]) {
      test('${accepted ? 'accepted' : 'rejected'} receipt replays despite '
          '$unavailable', () async {
        final fixture = _Fixture(ready: accepted);
        final request = _request();
        final first = await _execute(fixture.executor(), request);
        final receipt = fixture.room.receipts[request.commandId]!;
        final before = fixture.room.persistenceSummary;
        expect(
          first.value.status,
          accepted
              ? api.AuthorityCommandStatus.accepted
              : api.AuthorityCommandStatus.rejected,
        );
        fixture.catalog.calls = 0;
        if (unavailable == 'catalog') {
          fixture.catalog.failure = _Failure(
            'catalog',
            cause: const service.FirstPlayableRulesCatalogRepositoryViolation(
              'rulesCatalogUnavailable',
            ),
          );
        }
        final factoryFailure = _Failure(unavailable);
        final replay = await _execute(
          fixture.executor(
            factory: switch (unavailable) {
              'missingFactory' => null,
              'syncFactory' => factoryFailure.syncFactory,
              'asyncFactory' => factoryFailure.asyncFactory,
              _ => _materialFactory,
            },
          ),
          request,
        );

        expect(replay.outcome, AuthorityOutcome.duplicate);
        expect(replay.reason, AuthorityReason.duplicateCommand);
        expect(replay.value.status, api.AuthorityCommandStatus.duplicate);
        expect(replay.value.publicResult, receipt.receipt.publicResult);
        expect(replay.value.versionBefore, first.value.versionBefore);
        expect(replay.value.versionAfter, first.value.versionAfter);
        expect(replay.value.errorCode, accepted ? null : 'notAllPlayersReady');
        expect(replay.metrics.firestoreWriteCount, 0);
        expect(fixture.catalog.calls, 0);
        expect(fixture.room.persistenceSummary, before);
        expect(fixture.room.receipts[request.commandId], same(receipt));
      });
    }
  }

  for (final collision in <String>['actor', 'hash', 'commandId']) {
    test('$collision collision wins over unavailable replay dependencies', () async {
      final fixture = _Fixture();
      final original = _request();
      await _execute(fixture.executor(), original);
      if (collision == 'commandId') {
        final stored = fixture.room.receipts[original.commandId]!;
        // Deliberately misbound store record, not a claim that an adapter
        // normally fetches a different document. Hash version remains valid v1.
        fixture.room.receipts[original.commandId] =
            service.StoredAuthorityCommandReceipt(
              actorUid: stored.actorUid,
              receipt: service.DurableCommandReceipt(
                commandId: 'different-command',
                inputHashVersion: stored.receipt.inputHashVersion,
                inputHash: stored.receipt.inputHash,
                publicResult: <String, Object?>{
                  ...stored.receipt.publicResult,
                  'commandId': 'different-command',
                },
              ),
            );
      }
      fixture.catalog.failure = _Failure('catalog');
      fixture.catalog.calls = 0;
      final before = fixture.room.persistenceSummary;
      final result = await _execute(
        fixture.executor(factory: _Failure('factory').asyncFactory),
        collision == 'hash' ? _request(version: 11) : original,
        actorUid: collision == 'actor' ? 'uid-p2' : 'uid-p1',
      );
      expect(result.outcome, AuthorityOutcome.collision);
      expect(result.value.errorCode, 'commandIdCollision');
      expect(result.value.publicResult, isNot(contains('gameId')));
      expect(result.value.publicResult, isNot(contains('starterAllocation')));
      expect(result.metrics.firestoreWriteCount, 0);
      expect(fixture.catalog.calls, 0);
      expect(fixture.room.persistenceSummary, before);
    });
  }

  test('SetReady receipt replays without loading the catalog', () async {
    final fixture = _Fixture(ready: false);
    final request = _request(type: RoomCommandType.setReady);
    final first = await _execute(
      fixture.executor(),
      request,
      actorUid: 'uid-p2',
    );
    fixture.catalog.failure = _Failure('catalog');
    fixture.catalog.calls = 0;
    final before = fixture.room.persistenceSummary;
    final replay = await _execute(
      fixture.executor(factory: null),
      request,
      actorUid: 'uid-p2',
    );
    expect(replay.value.status, api.AuthorityCommandStatus.duplicate);
    expect(replay.value.publicResult, first.value.publicResult);
    expect(fixture.catalog.calls, 0);
    expect(replay.metrics.firestoreWriteCount, 0);
    expect(fixture.room.persistenceSummary, before);
  });

  test(
    'missing factory without receipt still fails after the room read',
    () async {
      final fixture = _Fixture();
      await expectLater(
        _execute(fixture.executor(factory: null), _request()),
        throwsA(
          isA<service.FirstPlayableAuthorityExecutorViolation>().having(
            (error) => error.code,
            'code',
            'startMaterialUnavailable',
          ),
        ),
      );
      expect(fixture.store.logicalReads, 3);
      expect(fixture.room.writes, 0);
      expect(fixture.room.receipts, isEmpty);
    },
  );

  for (final asyncFailure in <bool>[false, true]) {
    test(
      '${asyncFailure ? 'async' : 'sync'} preparation failure retains original '
      'error and stack after the no-receipt read',
      () async {
        final fixture = _Fixture();
        final failure = _Failure('preparation');
        final caught = await _catchFailure(
          _execute(
            fixture.executor(
              factory: asyncFailure
                  ? failure.asyncFactory
                  : failure.syncFactory,
            ),
            _request(),
          ),
        );
        _expectOriginal(caught, failure);
        expect(fixture.store.logicalReads, 3);
        expect(fixture.room.writes, 0);
        expect(fixture.room.receipts, isEmpty);
      },
    );
  }

  for (final preparationFails in <bool>[false, true]) {
    test(
      'store error is not swallowed when preparation failure=$preparationFails',
      () async {
        final fixture = _Fixture();
        final storeFailure = _Failure('store');
        fixture.store.failure = storeFailure;
        final caught = await _catchFailure(
          _execute(
            fixture.executor(
              factory: preparationFails
                  ? _Failure('preparation').asyncFactory
                  : _materialFactory,
            ),
            _request(),
          ),
        );
        _expectOriginal(caught, storeFailure);
        expect(fixture.store.calls, 1);
        expect(fixture.room.writes, 0);
      },
    );
  }

  test(
    'catalog error for a new command retains original error and stack',
    () async {
      final fixture = _Fixture();
      final failure = _Failure('catalog');
      fixture.catalog.failure = failure;
      _expectOriginal(
        await _catchFailure(_execute(fixture.executor(), _request())),
        failure,
      );
      expect(fixture.catalog.calls, 1);
      expect(fixture.store.logicalReads, 3);
      expect(fixture.room.writes, 0);
    },
  );

  test(
    'malformed matching receipt does not fall back to failed preparation',
    () async {
      final fixture = _Fixture();
      final request = _request();
      fixture.room.receipts[request
          .commandId] = service.StoredAuthorityCommandReceipt(
        actorUid: 'uid-p1',
        receipt: service.DurableCommandReceipt(
          commandId: request.commandId,
          inputHashVersion: request.inputHashVersion,
          inputHash: request.inputHash,
          // The receipt model allows this canonical map; the public response
          // adapter must reject the missing versions, not manufacture a replay.
          publicResult: <String, Object?>{
            'commandId': request.commandId,
            'status': 'accepted',
          },
        ),
      );
      fixture.catalog.failure = _Failure('catalog');
      await expectLater(
        _execute(
          fixture.executor(factory: _Failure('preparation').syncFactory),
          request,
        ),
        throwsA(
          isA<service.AuthorityReconnectViolation>().having(
            (error) => error.code,
            'code',
            'invalidDurableCommandResult',
          ),
        ),
      );
      expect(fixture.catalog.calls, 0);
      expect(fixture.room.writes, 0);
    },
  );

  test(
    'one awaited material is reused across three callback attempts',
    () async {
      final fixture = _Fixture();
      fixture.store.attempts = 3;
      final pending = Completer<service.FirstPlayableStartMaterial>();
      var calls = 0;
      final resultFuture = _execute(
        fixture.executor(
          factory: (command) {
            calls += 1;
            return pending.future;
          },
        ),
        _request(),
      );
      expect(calls, 1);
      expect(fixture.store.calls, 0, reason: 'preparation remains awaited');
      pending.complete(_material('prepared-once'));
      final result = await resultFuture;
      expect(result.value.status, api.AuthorityCommandStatus.accepted);
      expect(calls, 1);
      expect(fixture.store.decisions, hasLength(3));
      expect(
        fixture.store.decisions.map((d) => d.startPlan!.gameId).toSet(),
        <String>{'prepared-once'},
      );
      expect(
        fixture.store.decisions
            .map((d) => d.startPlan!.publicState.toCanonicalJson())
            .toSet(),
        hasLength(1),
      );
      expect(fixture.room.writes, 4);
      expect(fixture.room.receipts, hasLength(1));
    },
  );

  test(
    'concurrent requests isolate a prepared material from an original failure',
    () async {
      final fixture = _Fixture();
      final secondRoom = _Room('room-other');
      fixture.store.rooms[secondRoom.id] = secondRoom;
      final pending = <String, Completer<service.FirstPlayableStartMaterial>>{};
      final executor = fixture.executor(
        factory: (command) {
          final completer = Completer<service.FirstPlayableStartMaterial>();
          pending[command.commandId] = completer;
          return completer.future;
        },
      );
      final successFuture = _execute(executor, _request());
      final failureFuture = _catchFailure(
        _execute(
          executor,
          _request(commandId: 'other-start', roomId: secondRoom.id),
        ),
      );
      expect(pending, hasLength(2));
      expect(fixture.store.calls, 0);
      final failure = _Failure('second-preparation');
      pending['other-start']!.completeError(failure.error, failure.stack);
      _expectOriginal(await failureFuture, failure);
      pending['cmd-start']!.complete(_material('isolated-game'));
      final accepted = await successFuture;
      expect(accepted.value.publicResult['gameId'], 'isolated-game');
      expect(fixture.room.gameId, 'isolated-game');
      expect(fixture.room.writes, 4);
      expect(secondRoom.writes, 0);
      expect(secondRoom.receipts, isEmpty);
      expect(fixture.store.logicalReads, 6);
    },
  );
}

api.AuthorityCommandRequest _request({
  String commandId = 'cmd-start',
  String roomId = 'room-vp0',
  int version = 12,
  RoomCommandType type = RoomCommandType.startGame,
}) => api.AuthorityCommandRequest.room(
  RoomCommand(
    commandId: commandId,
    schemaVersion: 1,
    expectedRoomVersion: version,
    clientInstanceId: 'client-replay',
    type: type,
    payload: <String, Object?>{
      'roomId': roomId,
      if (type == RoomCommandType.setReady) 'ready': true,
    },
  ),
);

Future<AuthorityExecutionResult<api.AuthorityCommandReply>> _execute(
  service.FirstPlayableAuthorityExecutor executor,
  api.AuthorityCommandRequest request, {
  String actorUid = 'uid-p1',
}) => executor.executeCommand(
  context: IngressContext(requestReceivedAt: DateTime.utc(2026, 9, 9)),
  identity: service.VerifiedIdentity(
    uid: actorUid,
    authTime: DateTime.utc(2026, 9, 8),
  ),
  request: request,
);

service.FirstPlayableStartMaterial _material(String gameId) =>
    service.FirstPlayableStartMaterial(gameId: gameId, seed: syntheticRollSeed);

Future<service.FirstPlayableStartMaterial> _materialFactory(
  RoomCommand command,
) async => _material('game-${command.commandId}');

Future<(Object, StackTrace)> _catchFailure(Future<Object?> future) async {
  try {
    await future;
  } on Object catch (error, stack) {
    return (error, stack);
  }
  fail('Expected the operation to fail');
}

void _expectOriginal((Object, StackTrace) caught, _Failure expected) {
  expect(caught.$1, same(expected.error));
  expect(caught.$2.toString(), expected.stack.toString());
}

final class _Failure {
  _Failure(String label, {Object? cause})
    : error = cause ?? StateError('synthetic-$label'),
      stack = StackTrace.fromString('synthetic-$label-stack');
  final Object error;
  final StackTrace stack;
  Never raise() => Error.throwWithStackTrace(error, stack);
  Future<service.FirstPlayableStartMaterial> syncFactory(RoomCommand command) =>
      raise();
  Future<service.FirstPlayableStartMaterial> asyncFactory(
    RoomCommand command,
  ) async {
    await Future<void>.value();
    raise();
  }
}

final class _Fixture {
  _Fixture({bool ready = true}) : room = _Room('room-vp0', ready: ready) {
    store.rooms[room.id] = room;
  }
  final _Room room;
  final _Store store = _Store();
  final _Catalog catalog = _Catalog();
  service.FirstPlayableAuthorityExecutor executor({
    service.FirstPlayableStartMaterialFactory? factory = _materialFactory,
  }) => service.FirstPlayableAuthorityExecutor(
    store: store,
    rulesCatalogRepository: catalog,
    startMaterialFactory: factory,
  );
}

final class _Catalog implements service.FirstPlayableRulesCatalogRepository {
  final RulesCatalog value = syntheticRollCatalog();
  _Failure? failure;
  var calls = 0;
  @override
  RulesCatalog catalogForRoom({
    required String rulesVersion,
    required String presetId,
  }) {
    calls += 1;
    failure?.raise();
    expect(rulesVersion, value.rulesVersion);
    expect(presetId, 'express');
    return value;
  }

  @override
  RulesCatalog catalogForNewRoom({required String presetId}) =>
      throw UnsupportedError('unused');
  @override
  RulesCatalog catalogForGame(PublicGameState state) =>
      throw UnsupportedError('unused');
}

final class _Room {
  _Room(this.id, {bool ready = true})
    : members = <service.ReadyRoomMember>[
        const service.ReadyRoomMember(
          uid: 'uid-p1',
          playerId: 'p1',
          kind: PlayerKind.human,
          ready: true,
        ),
        service.ReadyRoomMember(
          uid: 'uid-p2',
          playerId: 'p2',
          kind: PlayerKind.human,
          ready: ready,
        ),
      ];
  final String id;
  var version = 12;
  var status = 'open';
  String? gameId;
  var writes = 0;
  List<service.ReadyRoomMember> members;
  final receipts = <String, service.StoredAuthorityCommandReceipt>{};
  String get persistenceSummary => CanonicalDomainJson.encode(<String, Object?>{
    'version': version,
    'status': status,
    'gameId': gameId,
    'writes': writes,
    'members': <String, Object?>{
      for (final member in members) member.playerId: member.ready,
    },
  });
  service.FirstPlayableRoomTransactionView view(String commandId) =>
      service.FirstPlayableRoomTransactionView(
        roomId: id,
        roomVersion: version,
        status: status,
        gameId: gameId,
        hostUid: 'uid-p1',
        presetId: 'express',
        rulesVersion: 'synthetic-rules-vp0',
        members: members,
        storedReceipt: receipts[commandId],
      );
}

final class _Store implements service.FirstPlayableAuthorityStore {
  final rooms = <String, _Room>{};
  final decisions = <service.FirstPlayableRoomTransactionDecision>[];
  _Failure? failure;
  var calls = 0;
  var logicalReads = 0;
  var attempts = 1;
  @override
  Future<service.FirstPlayableRoomTransactionResult> transactRoom({
    required String roomId,
    required String commandId,
    required service.FirstPlayableRoomTransactionCallback evaluate,
  }) async {
    calls += 1;
    failure?.raise();
    final room = rooms[roomId]!;
    late service.FirstPlayableRoomTransactionDecision decision;
    for (var attempt = 0; attempt < attempts; attempt += 1) {
      logicalReads +=
          3; // Synthetic public room, private room and receipt view.
      decision = evaluate(room.view(commandId));
      decisions.add(decision);
    }
    var writes = 0;
    if (decision.receiptToPersist case final receipt?) {
      room.receipts[commandId] = receipt;
      writes += 1;
    }
    if (decision.membersAfter case final members?) {
      room.members = members;
      room.version = decision.reply.versionAfter;
      writes += 1;
    }
    if (decision.startPlan case final plan?) {
      room.gameId = plan.gameId;
      room.version = plan.roomVersionAfter;
      room.status = 'active';
      writes += 3;
    }
    room.writes += writes;
    return service.FirstPlayableRoomTransactionResult(
      decision: decision,
      metrics: AuthorityExecutionMetrics(
        firestoreReadCount: 3 * attempts,
        firestoreWriteCount: writes,
        schemaVersion: 1,
        stateVersion: room.version,
      ),
    );
  }

  @override
  Future<service.FirstPlayableRoomEntryTransactionResult> transactRoomEntry({
    required service.FirstPlayableRoomEntryKind kind,
    required String codeHash,
    String? roomId,
    required String commandId,
    required service.FirstPlayableRoomEntryTransactionCallback evaluate,
  }) => throw UnsupportedError('unused');
  @override
  Future<service.FirstPlayableGameTransactionResult> transactGame({
    required String gameId,
    required String commandId,
    required service.FirstPlayableGameTransactionCallback evaluate,
  }) => throw UnsupportedError('unused');
  @override
  Future<service.FirstPlayableGameReadResult> readGame({
    required String gameId,
    String? commandId,
  }) => throw UnsupportedError('unused');
}
