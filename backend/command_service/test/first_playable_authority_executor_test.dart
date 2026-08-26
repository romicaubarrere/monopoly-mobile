import 'package:board_backend_api/backend_api.dart' as api;
import 'package:board_command_service/command_service.dart' as service;
import 'package:board_command_service/ingress/command_ingress.dart' as ingress;
import 'package:board_command_service/observability/authority_observability.dart'
    as observability;
import 'package:board_command_service/security/firebase_identity_verifier.dart'
    as firebase_identity;
import 'package:board_command_service/security/membership_authorizer.dart'
    as membership;
import 'package:board_game_contracts/game_contracts.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_buy_auction_fixture.dart';
import 'support/synthetic_roll_fixture.dart';

void main() {
  final context = ingress.IngressContext(
    requestReceivedAt: DateTime.parse('2026-08-25T02:00:00.000Z'),
  );
  final identity = firebase_identity.VerifiedIdentity(
    uid: 'uid-p1',
    authTime: DateTime.parse('2026-08-25T01:59:00.000Z'),
  );

  test(
    'Roll commits public state, private RNG and receipt exactly once',
    () async {
      final store = _MemoryStore(
        state: syntheticRollState(),
        catalog: syntheticRollCatalog(),
        privateRng: syntheticRollPrivateState(),
      );
      final executor = service.FirstPlayableAuthorityExecutor(store: store);
      final request = api.AuthorityCommandRequest.game(syntheticRollCommand());

      final accepted = await executor.executeCommand(
        context: context,
        identity: identity,
        request: request,
      );
      final countersAfter = Map<RngStream, int>.from(
        store.privateRng!.streamCounters,
      );
      final duplicate = await executor.executeCommand(
        context: context,
        identity: identity,
        request: request,
      );

      expect(accepted.outcome, observability.AuthorityOutcome.success);
      expect(accepted.value.status, api.AuthorityCommandStatus.accepted);
      expect(store.state.header.stateVersion, 1);
      expect(store.writeCount, 1);
      expect(duplicate.outcome, observability.AuthorityOutcome.duplicate);
      expect(duplicate.value.status, api.AuthorityCommandStatus.duplicate);
      expect(store.privateRng!.streamCounters, countersAfter);
      expect(store.writeCount, 1);
    },
  );

  test(
    'same commandId with a different semantic identity fails closed',
    () async {
      final store = _MemoryStore(
        state: syntheticRollState(),
        catalog: syntheticRollCatalog(),
        privateRng: syntheticRollPrivateState(),
      );
      final executor = service.FirstPlayableAuthorityExecutor(store: store);
      await executor.executeCommand(
        context: context,
        identity: identity,
        request: api.AuthorityCommandRequest.game(syntheticRollCommand()),
      );
      final collision = api.AuthorityCommandRequest.game(
        GameCommand(
          commandId: 'cmd-roll-1',
          schemaVersion: 1,
          expectedStateVersion: 1,
          clientInstanceId: 'client-other',
          gameId: store.state.header.gameId,
          actorPlayerId: 'p1',
          type: GameCommandType.buyProperty,
          payload: const <String, Object?>{'propertyId': 'street-07'},
        ),
      );

      final result = await executor.executeCommand(
        context: context,
        identity: identity,
        request: collision,
      );

      expect(result.outcome, observability.AuthorityOutcome.collision);
      expect(result.reason, observability.AuthorityReason.commandIdCollision);
      expect(result.value.errorCode, 'commandIdCollision');
      expect(store.state.header.stateVersion, 1);
      expect(store.writeCount, 1);
    },
  );

  test('Buy uses Engine plan and leaves private RNG unchanged', () async {
    final privateRng = syntheticRollPrivateState();
    final store = _MemoryStore(
      state: syntheticPropertyOfferState(),
      catalog: syntheticBuyAuctionCatalog(),
      privateRng: privateRng,
    );
    final executor = service.FirstPlayableAuthorityExecutor(store: store);

    final result = await executor.executeCommand(
      context: ingress.IngressContext(
        requestReceivedAt: syntheticBuyAuctionTime,
      ),
      identity: identity,
      request: api.AuthorityCommandRequest.game(
        syntheticOfferCommand(GameCommandType.buyProperty),
      ),
    );

    expect(result.value.status, api.AuthorityCommandStatus.accepted);
    expect(result.value.snapshot!.stateVersion, 2);
    expect(store.state.header.stateVersion, 2);
    expect(store.privateRng, same(privateRng));
    expect(store.writeCount, 1);
  });

  test('reconnect resolves lost ACK from the same private receipt', () async {
    final store = _MemoryStore(
      state: syntheticRollState(),
      catalog: syntheticRollCatalog(),
      privateRng: syntheticRollPrivateState(),
    );
    final executor = service.FirstPlayableAuthorityExecutor(store: store);
    final command = api.AuthorityCommandRequest.game(syntheticRollCommand());
    await executor.executeCommand(
      context: context,
      identity: identity,
      request: command,
    );

    final reply = await executor.reconnect(
      context: context,
      identity: identity,
      request: api.AuthorityReconnectRequest(
        gameId: store.state.header.gameId,
        observedStateVersion: 0,
        uncertainCommand: command.uncertainIdentity,
      ),
    );

    expect(reply.disposition, api.ReconnectDisposition.uncertainConfirmed);
    expect(
      reply.commandResolution!.action,
      api.CommandResolutionAction.useDurableResult,
    );
    expect(reply.snapshot.stateVersion, 1);
    expect(store.writeCount, 1);
  });

  test('public snapshot read enforces actor membership', () async {
    final store = _MemoryStore(
      state: syntheticRollState(),
      catalog: syntheticRollCatalog(),
      privateRng: syntheticRollPrivateState(),
    );
    final executor = service.FirstPlayableAuthorityExecutor(store: store);

    expect(
      () => executor.readPublicGame(
        context: context,
        identity: firebase_identity.VerifiedIdentity(
          uid: 'uid-not-member',
          authTime: identity.authTime,
        ),
        gameId: store.state.header.gameId,
      ),
      throwsA(isA<membership.MembershipAuthorizationException>()),
    );
  });

  test(
    'SetReady is atomic, public-only, duplicate-safe and collision-safe',
    () async {
      final store = _MemoryStore(
        state: syntheticRollState(),
        catalog: syntheticRollCatalog(),
        privateRng: syntheticRollPrivateState(),
        roomMembers: const <service.ReadyRoomMember>[
          service.ReadyRoomMember(
            uid: 'uid-p1',
            playerId: 'p1',
            kind: PlayerKind.human,
            ready: true,
          ),
          service.ReadyRoomMember(
            uid: 'uid-p2',
            playerId: 'p2',
            kind: PlayerKind.human,
            ready: false,
          ),
        ],
      );
      final executor = service.FirstPlayableAuthorityExecutor(store: store);
      final command = _roomRequest(
        commandId: 'cmd-ready-1',
        type: RoomCommandType.setReady,
        actorReady: true,
      );

      final accepted = await executor.executeCommand(
        context: context,
        identity: firebase_identity.VerifiedIdentity(
          uid: 'uid-p2',
          authTime: identity.authTime,
        ),
        request: command,
      );
      final duplicate = await executor.executeCommand(
        context: context,
        identity: firebase_identity.VerifiedIdentity(
          uid: 'uid-p2',
          authTime: identity.authTime,
        ),
        request: command,
      );
      final collision = await executor.executeCommand(
        context: context,
        identity: firebase_identity.VerifiedIdentity(
          uid: 'uid-p2',
          authTime: identity.authTime,
        ),
        request: _roomRequest(
          commandId: 'cmd-ready-1',
          type: RoomCommandType.setReady,
          actorReady: false,
        ),
      );

      expect(accepted.value.status, api.AuthorityCommandStatus.accepted);
      expect(accepted.value.versionAfter, 13);
      expect(accepted.value.publicResult, isNot(contains('uid')));
      expect(store.roomMembers.every((member) => member.ready), isTrue);
      expect(duplicate.value.status, api.AuthorityCommandStatus.duplicate);
      expect(collision.outcome, observability.AuthorityOutcome.collision);
      expect(store.roomWriteCount, 1);
    },
  );

  test(
    'StartGame reuses one private material across transaction retries',
    () async {
      var materialCalls = 0;
      final store = _MemoryStore(
        state: syntheticRollState(),
        catalog: syntheticRollCatalog(),
        privateRng: syntheticRollPrivateState(),
        retryRoomCallback: true,
      );
      final executor = service.FirstPlayableAuthorityExecutor(
        store: store,
        startMaterialFactory: (command) async {
          materialCalls += 1;
          return service.FirstPlayableStartMaterial(
            gameId: 'game-started-vp0',
            seed: List<int>.generate(32, (index) => index),
          );
        },
      );

      final result = await executor.executeCommand(
        context: context,
        identity: identity,
        request: _roomRequest(
          commandId: 'cmd-start-1',
          type: RoomCommandType.startGame,
        ),
      );

      expect(result.value.status, api.AuthorityCommandStatus.accepted);
      expect(result.value.publicResult['gameId'], 'game-started-vp0');
      expect(result.value.publicResult, isNot(contains('seed')));
      expect(result.value.publicResult, isNot(contains('streamCounters')));
      expect(materialCalls, 1);
      expect(store.roomCallbackCount, 2);
      expect(store.roomVersion, 13);
      expect(store.startPlan!.publicState.header.stateVersion, 0);
      expect(store.startPlan!.privateState.seed, hasLength(32));
      expect(store.roomWriteCount, 1);
    },
  );

  test(
    'room membership and Ready guards fail closed without a game write',
    () async {
      final store = _MemoryStore(
        state: syntheticRollState(),
        catalog: syntheticRollCatalog(),
        privateRng: syntheticRollPrivateState(),
        roomMembers: const <service.ReadyRoomMember>[
          service.ReadyRoomMember(
            uid: 'uid-p1',
            playerId: 'p1',
            kind: PlayerKind.human,
            ready: true,
          ),
          service.ReadyRoomMember(
            uid: 'uid-p2',
            playerId: 'p2',
            kind: PlayerKind.human,
            ready: false,
          ),
        ],
      );
      final executor = service.FirstPlayableAuthorityExecutor(
        store: store,
        startMaterialFactory: (command) async =>
            service.FirstPlayableStartMaterial(
              gameId: 'game-must-not-persist',
              seed: List<int>.filled(32, 7),
            ),
      );

      expect(
        () => executor.executeCommand(
          context: context,
          identity: firebase_identity.VerifiedIdentity(
            uid: 'uid-not-member',
            authTime: identity.authTime,
          ),
          request: _roomRequest(
            commandId: 'cmd-ready-forbidden',
            type: RoomCommandType.setReady,
            actorReady: true,
          ),
        ),
        throwsA(isA<membership.MembershipAuthorizationException>()),
      );
      final notReady = await executor.executeCommand(
        context: context,
        identity: identity,
        request: _roomRequest(
          commandId: 'cmd-start-not-ready',
          type: RoomCommandType.startGame,
        ),
      );

      expect(notReady.value.status, api.AuthorityCommandStatus.rejected);
      expect(notReady.value.errorCode, 'notAllPlayersReady');
      expect(store.startPlan, isNull);
      expect(store.roomStatus, 'open');
    },
  );
}

api.AuthorityCommandRequest _roomRequest({
  required String commandId,
  required RoomCommandType type,
  bool? actorReady,
}) => api.AuthorityCommandRequest.room(
  RoomCommand(
    commandId: commandId,
    schemaVersion: 1,
    expectedRoomVersion: 12,
    clientInstanceId: 'client-room-1',
    type: type,
    payload: <String, Object?>{
      'roomId': 'room-vp0',
      if (type == RoomCommandType.setReady) 'ready': actorReady,
    },
  ),
);

final class _MemoryStore implements service.FirstPlayableAuthorityStore {
  _MemoryStore({
    required this.state,
    required this.catalog,
    required this.privateRng,
    List<service.ReadyRoomMember>? roomMembers,
    this.retryRoomCallback = false,
  }) : roomMembers =
           roomMembers ??
           const <service.ReadyRoomMember>[
             service.ReadyRoomMember(
               uid: 'uid-p1',
               playerId: 'p1',
               kind: PlayerKind.human,
               ready: true,
             ),
             service.ReadyRoomMember(
               uid: 'uid-p2',
               playerId: 'p2',
               kind: PlayerKind.human,
               ready: true,
             ),
           ];

  PublicGameState state;
  final RulesCatalog catalog;
  service.AuthorityPrivateRngSnapshot? privateRng;
  service.StoredAuthorityCommandReceipt? receipt;
  service.StoredAuthorityCommandReceipt? roomReceipt;
  List<service.ReadyRoomMember> roomMembers;
  final bool retryRoomCallback;
  var roomVersion = 12;
  var roomStatus = 'open';
  var roomCallbackCount = 0;
  var roomWriteCount = 0;
  service.ReadyStartPlan? startPlan;
  var writeCount = 0;

  service.FirstPlayableGameTransactionView get _view =>
      service.FirstPlayableGameTransactionView(
        publicState: state,
        catalog: catalog,
        memberUidByPlayerId: const <String, String>{'p1': 'uid-p1'},
        privateRng: privateRng,
        storedReceipt: receipt,
      );

  @override
  Future<service.FirstPlayableGameReadResult> readGame({
    required String gameId,
    String? commandId,
  }) async {
    _requireGame(gameId);
    return service.FirstPlayableGameReadResult(
      view: service.FirstPlayableGameTransactionView(
        publicState: state,
        catalog: catalog,
        memberUidByPlayerId: const <String, String>{'p1': 'uid-p1'},
        privateRng: privateRng,
        storedReceipt: commandId == receipt?.receipt.commandId ? receipt : null,
      ),
      metrics: ingress.AuthorityExecutionMetrics(
        firestoreReadCount: commandId == null ? 1 : 2,
        schemaVersion: state.header.schemaVersion,
        stateVersion: state.header.stateVersion,
      ),
    );
  }

  @override
  Future<service.FirstPlayableRoomTransactionResult> transactRoom({
    required String roomId,
    required String commandId,
    required service.FirstPlayableRoomTransactionCallback evaluate,
  }) async {
    if (roomId != 'room-vp0') {
      throw const service.FirstPlayableAuthorityExecutorViolation(
        'roomUnavailable',
      );
    }
    service.FirstPlayableRoomTransactionView view() =>
        service.FirstPlayableRoomTransactionView(
          roomId: roomId,
          roomVersion: roomVersion,
          status: roomStatus,
          hostUid: 'uid-p1',
          presetId: 'express',
          members: roomMembers,
          catalog: catalog,
          storedReceipt: commandId == roomReceipt?.receipt.commandId
              ? roomReceipt
              : null,
        );
    var decision = evaluate(view());
    roomCallbackCount += 1;
    if (retryRoomCallback) {
      decision = evaluate(view());
      roomCallbackCount += 1;
    }
    if (decision.membersAfter != null) {
      roomMembers = decision.membersAfter!;
      roomVersion = decision.reply.versionAfter;
    }
    if (decision.startPlan != null) {
      startPlan = decision.startPlan;
      state = decision.startPlan!.publicState;
      roomVersion = decision.startPlan!.roomVersionAfter;
      roomStatus = 'active';
    }
    if (decision.receiptToPersist != null) {
      roomReceipt = decision.receiptToPersist;
      roomWriteCount += 1;
    }
    return service.FirstPlayableRoomTransactionResult(
      decision: decision,
      metrics: ingress.AuthorityExecutionMetrics(
        firestoreReadCount: 2,
        firestoreWriteCount: decision.receiptToPersist == null ? 0 : 2,
        schemaVersion: 1,
        stateVersion: roomVersion,
      ),
    );
  }

  @override
  Future<service.FirstPlayableGameTransactionResult> transactGame({
    required String gameId,
    required String commandId,
    required service.FirstPlayableGameTransactionCallback evaluate,
  }) async {
    _requireGame(gameId);
    final decision = evaluate(_view);
    var writes = 0;
    if (decision.publicStateAfter != null) {
      state = decision.publicStateAfter!;
      writes += 1;
    }
    if (decision.privateRngAfter != null) {
      privateRng = decision.privateRngAfter;
      writes += 1;
    }
    if (decision.receiptToPersist != null) {
      receipt = decision.receiptToPersist;
      writes += 1;
      writeCount += 1;
    }
    return service.FirstPlayableGameTransactionResult(
      decision: decision,
      metrics: ingress.AuthorityExecutionMetrics(
        firestoreReadCount: 3,
        firestoreWriteCount: writes,
        schemaVersion: state.header.schemaVersion,
        stateVersion: state.header.stateVersion,
      ),
    );
  }

  void _requireGame(String gameId) {
    if (gameId != state.header.gameId) {
      throw const service.FirstPlayableAuthorityExecutorViolation(
        'gameUnavailable',
      );
    }
  }
}
