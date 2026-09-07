import 'package:board_command_service/command_service.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_bankruptcy_fixture.dart';
import 'support/synthetic_buy_auction_fixture.dart';
import 'support/synthetic_roll_fixture.dart';

void main() {
  const members = {'p1': 'uid-1', 'p2': 'uid-2'};
  final auction = (BuyAuctionEngine.evaluate(
    command: syntheticOfferCommand(GameCommandType.declineProperty),
    state: syntheticPropertyOfferState(),
    catalog: syntheticBuyAuctionCatalog(),
    transitionTime: syntheticBuyAuctionTime,
  ) as BuyAuctionPlan).stateAfter;

  final cases = [
    (command: syntheticRollCommand(), state: syntheticRollState()),
    for (final type in [
      GameCommandType.buyProperty,
      GameCommandType.declineProperty,
    ])
      (
        command: syntheticOfferCommand(type),
        state: syntheticPropertyOfferState(),
      ),
    for (final type in [GameCommandType.placeBid, GameCommandType.passAuction])
      (
        command: syntheticAuctionCommand(
          type,
          commandId: 'controller-${type.wireValue}',
          expectedStateVersion: 2,
          actorPlayerId: 'p1',
          payload: {
            'auctionId': 'cmd-offer-1:auction',
            if (type == GameCommandType.placeBid) 'amount': 10,
          },
        ),
        state: auction,
      ),
    (
      command: syntheticBankruptcyCommand(GameCommandType.payDebt),
      state: syntheticBankruptcyState(debtorCash: 1000),
    ),
    (
      command: syntheticBankruptcyCommand(GameCommandType.declareBankruptcy),
      state: syntheticBankruptcyState(),
    ),
  ];

  Map<String, Object?> evaluate(
    GameCommand command,
    PublicGameState state, {
    String uid = 'uid-1',
  }) {
    if (command.type == GameCommandType.rollDice) {
      return AuthorityRollMovementPlanner.evaluate(
        command: command,
        authenticatedActorUid: uid,
        memberUidByPlayerId: members,
        state: state,
        catalog: syntheticRollCatalog(),
        privateSnapshot: syntheticRollPrivateState(),
        transitionTime: syntheticBuyAuctionTime,
      ).publicResult;
    }
    if (command.type == GameCommandType.payDebt ||
        command.type == GameCommandType.declareBankruptcy) {
      return AuthorityBankruptcyPlanner.evaluateHuman(
        command: command,
        authenticatedActorUid: uid,
        memberUidByPlayerId: members,
        state: state,
        catalog: syntheticBankruptcyCatalog(),
        requestReceivedAt: syntheticBankruptcyTime,
      ).publicResult;
    }
    return AuthorityBuyAuctionPlanner.evaluateHuman(
      command: command,
      authenticatedActorUid: uid,
      memberUidByPlayerId: members,
      state: state,
      catalog: syntheticBuyAuctionCatalog(),
      requestReceivedAt: syntheticBuyAuctionTime,
    ).publicResult;
  }

  for (final fixture in cases) {
    test(
      '${fixture.command.type.wireValue} remains valid under human control',
      () {
        expect(evaluate(fixture.command, fixture.state)['status'], 'accepted');
      },
    );
    test(
      '${fixture.command.type.wireValue} authenticates membership before controller inspection',
      () {
        final state = _withBotController(fixture.state);
        expect(
          () => evaluate(fixture.command, state, uid: 'foreign-uid'),
          throwsA(
            anyOf(
              isA<AuthorityRollMovementViolation>().having(
                (e) => e.code,
                'code',
                'actorNotAuthenticatedMember',
              ),
              isA<AuthorityBuyAuctionViolation>().having(
                (e) => e.code,
                'code',
                'actorNotAuthenticatedMember',
              ),
              isA<AuthorityBankruptcyViolation>().having(
                (e) => e.code,
                'code',
                'actorNotAuthenticatedMember',
              ),
            ),
          ),
        );
      },
    );
    for (final reclaimPending in [false, true]) {
      test(
        '${fixture.command.type.wireValue} rejects human input while bot controls, reclaim=$reclaimPending',
        () {
          final state = _withBotController(
            fixture.state,
            reclaimPending: reclaimPending,
          );
          final before = state.toCanonicalJson();
          final result = evaluate(fixture.command, state);
          expect(result['status'], 'rejected');
          expect(result['errorCode'], 'controllerNotHuman');
          expect(result['stateVersionAfter'], state.header.stateVersion);
          expect(result['events'], isEmpty);
          expect(state.toCanonicalJson(), before);
        },
      );
    }
    test(
      '${fixture.command.type.wireValue} cannot impersonate a permanent bot',
      () {
        final state = _withBotController(fixture.state, permanent: true);
        final before = state.toCanonicalJson();
        final result = evaluate(fixture.command, state);
        expect(result['status'], 'rejected');
        expect(result['errorCode'], 'controllerNotHuman');
        expect(result['events'], isEmpty);
        expect(state.toCanonicalJson(), before);
      },
    );
    test(
      '${fixture.command.type.wireValue} retains inactive-actor rejection',
      () {
        final state = _withBotController(
          fixture.state,
          status: PlayerStatus.bankrupt,
        );
        final result = evaluate(fixture.command, state);
        expect(result['status'], 'rejected');
        expect(result['errorCode'], 'actorNotInGame');
        expect(result['events'], isEmpty);
      },
    );
  }

  test('system auction deadline remains legal during temporary takeover', () {
    final state = _withBotController(auction);
    final result = AuthorityBuyAuctionPlanner.evaluateAuctionDeadline(
      state: state,
      catalog: syntheticBuyAuctionCatalog(),
      authorityNow: syntheticBuyAuctionTime.add(const Duration(seconds: 6)),
    );
    expect(result, isA<AuthorityBuyAuctionAccepted>());
  });

  test('system debt deadline remains legal during temporary takeover', () {
    final state = _withBotController(syntheticBankruptcyState());
    final result = AuthorityBankruptcyPlanner.evaluateDeadline(
      state: state,
      catalog: syntheticBankruptcyCatalog(),
      authorityNow: syntheticBankruptcyDeadline,
      decisionId: 'debt-1:decision',
      debtCaseId: 'debt-1',
      debtorPlayerId: 'p1',
      expectedStateVersion: 1,
    );
    expect(result, isA<AuthorityBankruptcyAccepted>());
  });
}

// Synthetic controller/player replacement: economy and decisions stay intact.
// No production presence or takeover is fabricated by a test.
PublicGameState _withBotController(
  PublicGameState state, {
  bool reclaimPending = false,
  bool permanent = false,
  PlayerStatus? status,
}) => PublicGameState(
  header: state.header,
  presetConfig: state.presetConfig,
  roundState: state.roundState,
  turnState: state.turnState,
  players: [
    for (final player in state.players)
      if (player.playerId == 'p1')
        PlayerState(
          playerId: player.playerId,
          seat: player.seat,
          kind: permanent ? PlayerKind.bot : player.kind,
          status: status ?? player.status,
          cash: player.cash,
          position: player.position,
          ownedPropertyIds: player.ownedPropertyIds,
          keepCardIds: player.keepCardIds,
          inCucha: player.inCucha,
          cuchaAttempts: player.cuchaAttempts,
          consecutiveDoubles: player.consecutiveDoubles,
          connectivityStatus: player.connectivityStatus,
        )
      else
        player,
  ],
  seatControllers: [
    for (final controller in state.seatControllers)
      if (controller.playerId == 'p1')
        SeatControllerState(
          playerId: controller.playerId,
          controller: SeatController.bot,
          botPolicyId: 'balanced',
          takeoverReason: permanent ? null : TakeoverReason.disconnectTimeout,
          takeoverStartedAt: permanent ? null : syntheticBuyAuctionTime,
          humanReclaimPending: reclaimPending,
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
