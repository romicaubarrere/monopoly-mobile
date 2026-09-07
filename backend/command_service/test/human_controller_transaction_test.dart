import 'package:board_backend_api/backend_api.dart' as api;
import 'package:board_command_service/command_service.dart';
import 'package:board_command_service/ingress/command_ingress.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_roll_fixture.dart';

void main() {
  final context = IngressContext(requestReceivedAt: DateTime.utc(2026, 9, 7));
  final identity = VerifiedIdentity(
    uid: 'uid-1',
    authTime: DateTime.utc(2026, 9, 6),
  );
  FirstPlayableAuthorityExecutor executor(_ControllerStore store) =>
      FirstPlayableAuthorityExecutor(
        store: store,
        rulesCatalogRepository: PinnedFirstPlayableRulesCatalogRepository(
          activeRulesVersion: syntheticRollCatalog().rulesVersion,
          catalogs: [syntheticRollCatalog()],
        ),
      );

  test('new bot-controlled human command persists only a rejection, retry stays rejected after reclaim', () async {
    final original = syntheticRollState();
    final store = _ControllerStore(_temporary(original));
    final authority = executor(store);
    final request = api.AuthorityCommandRequest.game(syntheticRollCommand());
    final before = store.state.toCanonicalJson();
    final privateBefore = store.privateRng;
    final rejected = await authority.executeCommand(
      context: context,
      identity: identity,
      request: request,
    );
    expect(rejected.value.status, api.AuthorityCommandStatus.rejected);
    expect(rejected.value.errorCode, 'controllerNotHuman');
    expect(store.lastDecision!.publicStateAfter, isNull);
    expect(store.lastDecision!.privateRngAfter, isNull);
    expect(store.lastDecision!.receiptToPersist, isNotNull);
    expect(store.state.toCanonicalJson(), before);
    expect(store.privateRng, same(privateBefore));
    expect(store.receiptWrites, 1);

    store.state = original; // Simulates a separately confirmed human reclaim.
    final duplicate = await authority.executeCommand(
      context: context,
      identity: identity,
      request: request,
    );
    expect(duplicate.value.status, api.AuthorityCommandStatus.duplicate);
    expect(duplicate.value.publicResult['errorCode'], 'controllerNotHuman');
    expect(store.receiptWrites, 1);
    expect(store.lastDecision!.receiptToPersist, isNull);
    expect(store.state.toCanonicalJson(), original.toCanonicalJson());
    expect(store.privateRng, same(privateBefore));

    final fresh = await authority.executeCommand(
      context: context,
      identity: identity,
      request: api.AuthorityCommandRequest.game(
        syntheticRollCommand(commandId: 'new-after-reclaim'),
      ),
    );
    expect(fresh.value.status, api.AuthorityCommandStatus.accepted);
    expect(store.state.header.stateVersion, 1);
  });

  test('lost ACK from before takeover reuses accepted receipt without a second RNG effect', () async {
    final store = _ControllerStore(syntheticRollState());
    final authority = executor(store);
    final request = api.AuthorityCommandRequest.game(syntheticRollCommand());
    final accepted = await authority.executeCommand(
      context: context,
      identity: identity,
      request: request,
    );
    expect(accepted.value.status, api.AuthorityCommandStatus.accepted);
    store.state = _temporary(store.state);
    final before = store.state.toCanonicalJson();
    final counters = Map<RngStream, int>.from(store.privateRng.streamCounters);
    final duplicate = await authority.executeCommand(
      context: context,
      identity: identity,
      request: request,
    );
    expect(duplicate.value.status, api.AuthorityCommandStatus.duplicate);
    expect(store.state.toCanonicalJson(), before);
    expect(store.privateRng.streamCounters, counters);
    expect(store.receiptWrites, 1);
    expect(store.lastDecision!.publicStateAfter, isNull);
    expect(store.lastDecision!.privateRngAfter, isNull);
  });

  test('transaction retry revalidates the current controller before applying a plan', () async {
    final original = syntheticRollState();
    final store = _ControllerStore(original)
      ..replacementOnRetry = _temporary(original);
    final privateBefore = store.privateRng;
    final result = await executor(store).executeCommand(
      context: context,
      identity: identity,
      request: api.AuthorityCommandRequest.game(syntheticRollCommand()),
    );
    expect(
      store.discardedDecision!.reply.status,
      api.AuthorityCommandStatus.accepted,
    );
    expect(result.value.status, api.AuthorityCommandStatus.rejected);
    expect(result.value.errorCode, 'controllerNotHuman');
    expect(store.state.header.stateVersion, 0);
    expect(store.privateRng, same(privateBefore));
    expect(store.receiptWrites, 1);
  });
}

// Deterministic transaction-callback harness, not Firestore concurrency proof.
final class _ControllerStore implements FirstPlayableAuthorityStore {
  _ControllerStore(this.state);
  PublicGameState state;
  AuthorityPrivateRngSnapshot privateRng = syntheticRollPrivateState();
  final receipts = <String, StoredAuthorityCommandReceipt>{};
  int receiptWrites = 0;
  PublicGameState? replacementOnRetry;
  FirstPlayableGameTransactionDecision? discardedDecision;
  FirstPlayableGameTransactionDecision? lastDecision;

  FirstPlayableGameTransactionView _view(String commandId) =>
      FirstPlayableGameTransactionView(
        publicState: state,
        privateRng: privateRng,
        memberUidByPlayerId: const {'p1': 'uid-1', 'p2': 'uid-2'},
        storedReceipt: receipts[commandId],
      );

  @override
  Future<FirstPlayableGameTransactionResult> transactGame({
    required String gameId,
    required String commandId,
    required FirstPlayableGameTransactionCallback evaluate,
  }) async {
    expect(gameId, state.header.gameId);
    var decision = evaluate(_view(commandId));
    final replacement = replacementOnRetry;
    if (replacement != null) {
      discardedDecision = decision;
      state = replacement;
      replacementOnRetry = null;
      decision = evaluate(_view(commandId));
    }
    lastDecision = decision;
    if (decision.publicStateAfter case final after?) state = after;
    if (decision.privateRngAfter case final after?) privateRng = after;
    if (decision.receiptToPersist case final receipt?) {
      receipts[commandId] = receipt;
      receiptWrites += 1;
    }
    return FirstPlayableGameTransactionResult(decision: decision);
  }

  @override
  Future<FirstPlayableGameReadResult> readGame({
    required String gameId,
    String? commandId,
  }) => throw UnimplementedError('No read path in this callback test');
  @override
  Future<FirstPlayableRoomTransactionResult> transactRoom({
    required String roomId,
    required String commandId,
    required FirstPlayableRoomTransactionCallback evaluate,
  }) => throw UnimplementedError('No room mutation in this callback test');
  @override
  Future<FirstPlayableRoomEntryTransactionResult> transactRoomEntry({
    required FirstPlayableRoomEntryKind kind,
    required String codeHash,
    String? roomId,
    required String commandId,
    required FirstPlayableRoomEntryTransactionCallback evaluate,
  }) => throw UnimplementedError('No room entry in this callback test');
}

PublicGameState _temporary(PublicGameState state) => PublicGameState(
  header: state.header,
  presetConfig: state.presetConfig,
  roundState: state.roundState,
  turnState: state.turnState,
  players: state.players,
  seatControllers: [
    for (final controller in state.seatControllers)
      if (controller.playerId == 'p1')
        SeatControllerState(
          playerId: 'p1',
          controller: SeatController.bot,
          botPolicyId: 'balanced',
          takeoverReason: TakeoverReason.disconnectTimeout,
          takeoverStartedAt: DateTime.utc(2026, 9, 7),
          humanReclaimPending: true,
        )
      else
        controller,
  ],
  board: state.board,
  ownership: state.ownership,
  bank: state.bank,
  freeParkingPot: state.freeParkingPot,
  deckPublicState: state.deckPublicState,
  pendingDecision: state.pendingDecision,
  activeAuction: state.activeAuction,
  activeTrade: state.activeTrade,
  debtCase: state.debtCase,
  result: state.result,
  lastMutation: state.lastMutation,
);
