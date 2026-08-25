import 'dart:convert';
import 'dart:io';

import 'package:board_command_service/command_service.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_buy_auction_fixture.dart';

void main() {
  final catalog = syntheticBuyAuctionCatalog();
  final members = const <String, String>{'p1': 'uid-1', 'p2': 'uid-2'};

  AuthorityBuyAuctionEvaluation evaluateHuman({
    required GameCommand command,
    required PublicGameState state,
    String authenticatedActorUid = 'uid-1',
    DateTime? requestReceivedAt,
  }) => AuthorityBuyAuctionPlanner.evaluateHuman(
    command: command,
    authenticatedActorUid: authenticatedActorUid,
    memberUidByPlayerId: members,
    state: state,
    catalog: catalog,
    requestReceivedAt: requestReceivedAt ?? syntheticBuyAuctionTime,
  );

  test('authenticated Buy exposes one atomic cash and ownership plan', () {
    final command = syntheticOfferCommand(GameCommandType.buyProperty);
    final evaluation = evaluateHuman(
      command: command,
      state: syntheticPropertyOfferState(),
    );

    expect(evaluation, isA<AuthorityBuyAuctionAccepted>());
    final plan = (evaluation as AuthorityBuyAuctionAccepted).plan;
    final buyer = plan.stateAfter.players.singleWhere(
      (player) => player.playerId == 'p1',
    );
    expect(buyer.cash, 1893);
    expect(buyer.ownedPropertyIds, <String>['street-07']);
    expect(plan.stateAfter.ownership['byPropertyId'], <String, Object?>{
      'street-07': 'p1',
    });
    expect(plan.stateAfter.pendingDecision, isNull);
    expect(plan.safeResultSummary['stateVersionAfter'], 2);
    expect(plan.safeResultSummary.toString(), isNot(contains('seed')));
    expect(
      plan.safeResultSummary.toString(),
      isNot(contains('streamCounters')),
    );
  });

  test('membership, stale version and ingress deadline fail closed', () {
    final command = syntheticOfferCommand(GameCommandType.buyProperty);
    expect(
      () => evaluateHuman(
        command: command,
        state: syntheticPropertyOfferState(),
        authenticatedActorUid: 'uid-other',
      ),
      throwsA(
        isA<AuthorityBuyAuctionViolation>().having(
          (error) => error.code,
          'code',
          'actorNotAuthenticatedMember',
        ),
      ),
    );

    final stale = evaluateHuman(
      command: syntheticOfferCommand(
        GameCommandType.buyProperty,
        expectedStateVersion: 0,
      ),
      state: syntheticPropertyOfferState(),
    ) as AuthorityBuyAuctionRejected;
    expect(stale.rejection.errorCode, BuyAuctionErrorCode.staleVersion);
    expect(stale.publicResult['stateVersionAfter'], 1);

    final atDeadline = evaluateHuman(
      command: command,
      state: syntheticPropertyOfferState(),
      requestReceivedAt: DateTime.parse('2026-08-25T02:30:12Z'),
    ) as AuthorityBuyAuctionRejected;
    expect(atDeadline.rejection.errorCode, BuyAuctionErrorCode.decisionClosed);
    expect(atDeadline.publicResult['events'], isEmpty);
  });

  test('captured ingress before deadline remains byte-stable across retry', () {
    final command = syntheticOfferCommand(GameCommandType.declineProperty);
    final state = syntheticPropertyOfferState();
    final captured = DateTime.parse('2026-08-25T02:30:11.999Z');
    final first = evaluateHuman(
      command: command,
      state: state,
      requestReceivedAt: captured,
    ) as AuthorityBuyAuctionAccepted;
    final retry = evaluateHuman(
      command: command,
      state: state,
      requestReceivedAt: captured,
    ) as AuthorityBuyAuctionAccepted;

    expect(
      retry.plan.enginePlan.toCanonicalPublicJson(),
      first.plan.enginePlan.toCanonicalPublicJson(),
    );
    expect(retry.plan.safeResultSummary, first.plan.safeResultSummary);
    expect(state.header.stateVersion, 1);
    expect(state.activeAuction, isNull);
  });

  test('authenticated non-current bidder is rejected by canonical Engine', () {
    final decline = evaluateHuman(
      command: syntheticOfferCommand(GameCommandType.declineProperty),
      state: syntheticPropertyOfferState(),
    ) as AuthorityBuyAuctionAccepted;
    final rejection = evaluateHuman(
      command: syntheticAuctionCommand(
        GameCommandType.placeBid,
        commandId: 'cmd-invalid-bidder',
        expectedStateVersion: 2,
        actorPlayerId: 'p2',
        payload: const <String, Object?>{
          'auctionId': 'cmd-offer-1:auction',
          'amount': 10,
        },
      ),
      state: decline.plan.stateAfter,
      authenticatedActorUid: 'uid-2',
    ) as AuthorityBuyAuctionRejected;

    expect(rejection.rejection.errorCode, BuyAuctionErrorCode.decisionClosed);
    expect(rejection.publicResult['stateVersionAfter'], 2);
    expect(rejection.publicResult['events'], isEmpty);
  });

  test('deadline composes accepted pass semantics back through Engine', () {
    final decline = evaluateHuman(
      command: syntheticOfferCommand(GameCommandType.declineProperty),
      state: syntheticPropertyOfferState(),
    ) as AuthorityBuyAuctionAccepted;
    final bid = evaluateHuman(
      command: syntheticAuctionCommand(
        GameCommandType.placeBid,
        commandId: 'cmd-bid-1',
        expectedStateVersion: 2,
        actorPlayerId: 'p1',
        payload: const <String, Object?>{
          'auctionId': 'cmd-offer-1:auction',
          'amount': 40,
        },
      ),
      state: decline.plan.stateAfter,
      requestReceivedAt: DateTime.parse('2026-08-25T02:30:02Z'),
    ) as AuthorityBuyAuctionAccepted;

    final early = AuthorityBuyAuctionPlanner.evaluateAuctionDeadline(
      state: bid.plan.stateAfter,
      catalog: catalog,
      authorityNow: DateTime.parse('2026-08-25T02:30:07.999Z'),
    );
    expect(early, isA<AuthorityBuyAuctionNoOp>());
    expect((early as AuthorityBuyAuctionNoOp).reason, 'notDue');

    final due = AuthorityBuyAuctionPlanner.evaluateAuctionDeadline(
      state: bid.plan.stateAfter,
      catalog: catalog,
      authorityNow: DateTime.parse('2026-08-25T02:30:08Z'),
    ) as AuthorityBuyAuctionAccepted;
    expect(
      due.plan.enginePlan.commandId,
      'deadline:v1:cmd-offer-1:auction:turn:3',
    );
    expect(due.plan.stateAfter.header.stateVersion, 4);
    expect(due.plan.stateAfter.activeAuction, isNull);
    expect(due.plan.stateAfter.pendingDecision, isNull);
    final winner = due.plan.stateAfter.players.singleWhere(
      (player) => player.playerId == 'p1',
    );
    expect(winner.cash, 1960);
    expect(winner.ownedPropertyIds, <String>['street-07']);
    expect(due.plan.enginePlan.events.last.type, 'auctionWon');
  });

  test('shared Emulator fixture is generated by canonical Authority plans', () {
    final fixture = jsonDecode(
      File('test/fixtures/buy_auction_plans.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final plans = syntheticBuyAuctionPlans();

    for (final entry in plans.entries) {
      final expected = fixture[entry.key]! as Map<String, Object?>;
      expect(entry.value.command, expected['command']);
      expect(entry.value.durableProjection, expected['stateProjection']);
      expect(entry.value.plan.safeResultSummary, expected['resultSummary']);
    }
    expect(fixture['privateSentinel'], <String, Object?>{
      'rngVersion': canonicalRngVersion,
      'seedMarker': 'authority-private-unchanged',
      'streamCounters': <String, Object?>{'dice': 2},
    });
  });

  test('semantic fingerprint excludes transport and auth metadata', () {
    final first = syntheticOfferCommand(GameCommandType.buyProperty);
    final sameSemantic = syntheticOfferCommand(
      GameCommandType.buyProperty,
      commandId: 'different-command-id',
      clientInstanceId: 'different-client',
    );

    expect(
      AuthorityBuyAuctionPlanner.inputHash(first),
      AuthorityBuyAuctionPlanner.inputHash(sameSemantic),
    );
    expect(AuthorityBuyAuctionPlanner.inputHash(first), hasLength(64));
    expect(
      AuthorityBuyAuctionPlanner.semanticMaterial(first),
      containsPair('type', 'BuyProperty'),
    );
  });
}

final class SyntheticBuyAuctionPlan {
  const SyntheticBuyAuctionPlan({
    required this.command,
    required this.inputHash,
    required this.plan,
  });

  final Map<String, Object?> command;
  final String inputHash;
  final AuthorityBuyAuctionPlan plan;

  Map<String, Object?> get durableProjection {
    final state = plan.stateAfter.toJson();
    return <String, Object?>{
      'stateVersionAfter': plan.stateAfter.header.stateVersion,
      'players': state['players'],
      'ownership': state['ownership'],
      'turnState': state['turnState'],
      'pendingDecision': state['pendingDecision'],
      'activeAuction': state['activeAuction'],
      'lastMutation': state['lastMutation'],
    };
  }
}

Map<String, SyntheticBuyAuctionPlan> syntheticBuyAuctionPlans() {
  const members = <String, String>{'p1': 'uid-1', 'p2': 'uid-2'};
  final catalog = syntheticBuyAuctionCatalog();

  AuthorityBuyAuctionAccepted apply(
    GameCommand command,
    PublicGameState state,
    DateTime at,
  ) => AuthorityBuyAuctionPlanner.evaluateHuman(
    command: command,
    authenticatedActorUid: members[command.actorPlayerId]!,
    memberUidByPlayerId: members,
    state: state,
    catalog: catalog,
    requestReceivedAt: at,
  ) as AuthorityBuyAuctionAccepted;

  final buyCommand = syntheticOfferCommand(GameCommandType.buyProperty);
  final buy = apply(
    buyCommand,
    syntheticPropertyOfferState(),
    syntheticBuyAuctionTime,
  );

  final declineCommand = syntheticOfferCommand(GameCommandType.declineProperty);
  final decline = apply(
    declineCommand,
    syntheticPropertyOfferState(),
    syntheticBuyAuctionTime,
  );
  final bidCommand = syntheticAuctionCommand(
    GameCommandType.placeBid,
    commandId: 'cmd-bid-1',
    expectedStateVersion: 2,
    actorPlayerId: 'p1',
    payload: const <String, Object?>{
      'auctionId': 'cmd-offer-1:auction',
      'amount': 40,
    },
  );
  final bid = apply(
    bidCommand,
    decline.plan.stateAfter,
    DateTime.parse('2026-08-25T02:30:02Z'),
  );
  final deadline = AuthorityBuyAuctionPlanner.evaluateAuctionDeadline(
    state: bid.plan.stateAfter,
    catalog: catalog,
    authorityNow: DateTime.parse('2026-08-25T02:30:08Z'),
  ) as AuthorityBuyAuctionAccepted;
  final deadlineCommand = <String, Object?>{
    'commandId': deadline.plan.enginePlan.commandId,
    'schemaVersion': 1,
    'expectedStateVersion': 3,
    'clientInstanceId': 'authority-system',
    'gameId': 'game-vp0',
    'actorPlayerId': 'p2',
    'type': 'PassAuction',
    'payload': const <String, Object?>{'auctionId': 'cmd-offer-1:auction'},
  };
  final deadlineGameCommand = GameCommand(
    commandId: deadline.plan.enginePlan.commandId,
    schemaVersion: 1,
    expectedStateVersion: 3,
    clientInstanceId: 'authority-system',
    gameId: 'game-vp0',
    actorPlayerId: 'p2',
    type: GameCommandType.passAuction,
    payload: const <String, Object?>{'auctionId': 'cmd-offer-1:auction'},
  );

  SyntheticBuyAuctionPlan record(
    GameCommand command,
    AuthorityBuyAuctionAccepted accepted,
  ) => SyntheticBuyAuctionPlan(
    command: command.toJson(),
    inputHash: AuthorityBuyAuctionPlanner.inputHash(command),
    plan: accepted.plan,
  );

  return <String, SyntheticBuyAuctionPlan>{
    'buy': record(buyCommand, buy),
    'decline': record(declineCommand, decline),
    'bid': record(bidCommand, bid),
    'deadlinePass': SyntheticBuyAuctionPlan(
      command: deadlineCommand,
      inputHash: AuthorityBuyAuctionPlanner.inputHash(deadlineGameCommand),
      plan: deadline.plan,
    ),
  };
}
