import 'dart:convert';
import 'dart:io';

import 'package:board_command_service/command_service.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_bankruptcy_fixture.dart';
import 'support/synthetic_bankruptcy_plans.dart';

void main() {
  final catalog = syntheticBankruptcyCatalog();
  const members = <String, String>{
    'p1': 'uid-p1',
    'p2': 'uid-p2',
    'p3': 'uid-p3',
  };

  AuthorityBankruptcyEvaluation evaluateHuman({
    required GameCommand command,
    required PublicGameState state,
    String uid = 'uid-p1',
    DateTime? at,
  }) => AuthorityBankruptcyPlanner.evaluateHuman(
    command: command,
    authenticatedActorUid: uid,
    memberUidByPlayerId: members,
    state: state,
    catalog: catalog,
    requestReceivedAt: at ?? syntheticBankruptcyTime,
  );

  test('human declaration exposes one safe atomic bankruptcy plan', () {
    final evaluation = evaluateHuman(
      command: syntheticBankruptcyCommand(GameCommandType.declareBankruptcy),
      state: syntheticBankruptcyState(),
    ) as AuthorityBankruptcyAccepted;

    final plan = evaluation.plan;
    final debtor = plan.stateAfter.players.singleWhere(
      (player) => player.playerId == 'p1',
    );
    final creditor = plan.stateAfter.players.singleWhere(
      (player) => player.playerId == 'p2',
    );
    expect(debtor.status, PlayerStatus.bankrupt);
    expect(creditor.cash, 2007);
    expect(creditor.ownedPropertyIds, <String>['street-00']);
    expect(plan.stateAfter.pendingDecision, isNull);
    expect(plan.stateAfter.debtCase, isNull);
    expect(plan.safeResultSummary['bankruptcyDeclared'], isTrue);
    expect(plan.safeResultSummary, isNot(contains('state')));
    expect(jsonEncode(plan.safeResultSummary), isNot(contains('seed')));
    expect(
      jsonEncode(plan.safeResultSummary),
      isNot(contains('streamCounters')),
    );
  });

  test('manual payment delegates settlement to canonical Engine', () {
    final evaluation = evaluateHuman(
      command: syntheticBankruptcyCommand(GameCommandType.payDebt),
      state: syntheticBankruptcyState(debtorCash: 500),
    ) as AuthorityBankruptcyAccepted;

    expect(evaluation.plan.enginePlan.bankruptcyDeclared, isFalse);
    expect(evaluation.plan.stateAfter.header.stateVersion, 2);
    expect(
      evaluation.plan.stateAfter.players
          .singleWhere((player) => player.playerId == 'p1')
          .cash,
      0,
    );
  });

  test('membership, stale version and inclusive deadline fail closed', () {
    final state = syntheticBankruptcyState();
    final command = syntheticBankruptcyCommand(
      GameCommandType.declareBankruptcy,
    );
    expect(
      () => evaluateHuman(command: command, state: state, uid: 'uid-other'),
      throwsA(
        isA<AuthorityBankruptcyViolation>().having(
          (error) => error.code,
          'code',
          'actorNotAuthenticatedMember',
        ),
      ),
    );

    final stale = evaluateHuman(
      command: syntheticBankruptcyCommand(
        GameCommandType.declareBankruptcy,
        expectedStateVersion: 0,
      ),
      state: state,
    ) as AuthorityBankruptcyRejected;
    expect(stale.rejection.errorCode, BankruptcyErrorCode.staleVersion);
    expect(stale.rejection.stateVersionAfter, 1);

    final closed = evaluateHuman(
      command: command,
      state: state,
      at: syntheticBankruptcyDeadline,
    ) as AuthorityBankruptcyRejected;
    expect(closed.rejection.errorCode, BankruptcyErrorCode.decisionClosed);
    expect(closed.publicResult['events'], isEmpty);
  });

  test(
    'same captured ingress input is byte-stable and source is unchanged',
    () {
      final state = syntheticBankruptcyState();
      final command = syntheticBankruptcyCommand(
        GameCommandType.declareBankruptcy,
      );
      final first = evaluateHuman(
        command: command,
        state: state,
      ) as AuthorityBankruptcyAccepted;
      final retry = evaluateHuman(
        command: command,
        state: state,
      ) as AuthorityBankruptcyAccepted;

      expect(
        retry.plan.enginePlan.toCanonicalPublicJson(),
        first.plan.enginePlan.toCanonicalPublicJson(),
      );
      expect(retry.plan.safeResultSummary, first.plan.safeResultSummary);
      expect(state.header.stateVersion, 1);
      expect(state.debtCase, isNotNull);
    },
  );

  test('deadline is read-only before due and deterministic when due', () {
    final state = syntheticBankruptcyState();
    final early = AuthorityBankruptcyPlanner.evaluateDeadline(
      state: state,
      catalog: catalog,
      authorityNow: syntheticBankruptcyDeadline.subtract(
        const Duration(microseconds: 1),
      ),
      decisionId: 'debt-1:decision',
      debtCaseId: 'debt-1',
      debtorPlayerId: 'p1',
      expectedStateVersion: 1,
    ) as AuthorityBankruptcyNoOp;
    expect(early.reason, 'notDue');
    expect(state.header.stateVersion, 1);

    final due = AuthorityBankruptcyPlanner.evaluateDeadline(
      state: state,
      catalog: catalog,
      authorityNow: syntheticBankruptcyDeadline,
      decisionId: 'debt-1:decision',
      debtCaseId: 'debt-1',
      debtorPlayerId: 'p1',
      expectedStateVersion: 1,
    ) as AuthorityBankruptcyAccepted;
    expect(due.plan.enginePlan.commandId, 'deadline:v1:debt-1:decision');
    expect(due.plan.enginePlan.bankruptcyDeclared, isTrue);
    expect(due.plan.stateAfter.header.stateVersion, 2);
  });

  test('bank creditor branch remains owned by Engine', () {
    final due = AuthorityBankruptcyPlanner.evaluateDeadline(
      state: syntheticBankruptcyState(
        creditorKind: 'bank',
        includeThirdPlayer: true,
      ),
      catalog: catalog,
      authorityNow: syntheticBankruptcyDeadline,
      decisionId: 'debt-1:decision',
      debtCaseId: 'debt-1',
      debtorPlayerId: 'p1',
      expectedStateVersion: 1,
    ) as AuthorityBankruptcyAccepted;

    expect(due.plan.stateAfter.header.status, GameStatus.active);
    expect(due.plan.stateAfter.turnState['phase'], 'bankruptcyAuctions');
    expect(due.plan.stateAfter.bank['bankruptcyAuctionQueue'], <String>[
      'street-00',
    ]);
  });

  test('semantic fingerprint excludes transport identity', () {
    final first = syntheticBankruptcyCommand(GameCommandType.declareBankruptcy);
    final retry = syntheticBankruptcyCommand(
      GameCommandType.declareBankruptcy,
      commandId: 'transport-retry-id',
      clientInstanceId: 'transport-retry-client',
    );
    expect(
      AuthorityBankruptcyPlanner.inputHash(first),
      AuthorityBankruptcyPlanner.inputHash(retry),
    );
    expect(AuthorityBankruptcyPlanner.inputHash(first), hasLength(64));
  });

  test('shared Emulator fixture is generated by canonical Authority plans', () {
    final fixture = jsonDecode(
      File('test/fixtures/bankruptcy_plans.json').readAsStringSync(),
    );
    expect(fixture, syntheticBankruptcyFixtureJson());
  });
}
