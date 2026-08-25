import 'dart:convert';
import 'dart:io';

import 'package:board_command_service/command_service.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_roll_fixture.dart';

void main() {
  final fixture =
      (jsonDecode(
            File('test/fixtures/roll_movement_plans.json').readAsStringSync(),
          ) as List<Object?>).single
          as Map<String, Object?>;

  AuthorityRollMovementEvaluation evaluate({
    GameCommand? command,
    String authenticatedActorUid = 'uid-1',
    PublicGameState? state,
    AuthorityPrivateRngSnapshot? privateState,
  }) => AuthorityRollMovementPlanner.evaluate(
    command: command ?? syntheticRollCommand(),
    authenticatedActorUid: authenticatedActorUid,
    memberUidByPlayerId: const <String, String>{'p1': 'uid-1', 'p2': 'uid-2'},
    state: state ?? syntheticRollState(),
    catalog: syntheticRollCatalog(),
    privateSnapshot: privateState ?? syntheticRollPrivateState(),
    transitionTime: DateTime.parse('2026-08-25T01:30:00Z'),
  );

  test(
    'authority invokes Engine and exposes one atomic public/private plan',
    () {
      final evaluation = evaluate();

      expect(evaluation, isA<AuthorityRollMovementAccepted>());
      final plan = (evaluation as AuthorityRollMovementAccepted).plan;
      expect(<int>[plan.enginePlan.die1, plan.enginePlan.die2], <int>[6, 2]);
      expect(plan.enginePlan.toPosition, 8);
      expect(plan.enginePlan.propertyId, 'street-07');
      expect(plan.stateAfter.header.stateVersion, 1);
      expect(plan.successorPrivateState.streamCounters[RngStream.dice], 2);
      expect(plan.safeResultSummary['stateVersionAfter'], 1);
      expect(plan.safeResultSummary.toString(), isNot(contains('seed')));
      expect(
        plan.safeResultSummary.toString(),
        isNot(contains('streamCounters')),
      );
    },
  );

  test('shared Emulator fixture is produced by the canonical Dart plan', () {
    final expected = fixture['expectedPlan']! as Map<String, Object?>;
    final evaluation = evaluate() as AuthorityRollMovementAccepted;
    final plan = evaluation.plan;
    final p1 = plan.stateAfter.players.singleWhere(
      (player) => player.playerId == 'p1',
    );

    expect(plan.enginePlan.stateVersionAfter, expected['stateVersionAfter']);
    expect(plan.enginePlan.die1, expected['die1']);
    expect(plan.enginePlan.die2, expected['die2']);
    expect(plan.enginePlan.fromPosition, expected['fromPosition']);
    expect(plan.enginePlan.toPosition, expected['toPosition']);
    expect(plan.enginePlan.propertyId, expected['propertyId']);
    expect(p1.position, expected['toPosition']);
    expect(plan.stateAfter.turnState, expected['turnStateAfter']);
    expect(plan.stateAfter.pendingDecision, expected['pendingDecision']);
    expect(
      plan.enginePlan.events.map((event) => event.toJson()).toList(),
      expected['events'],
    );
    expect(<String, int>{
      for (final entry in plan.successorPrivateState.streamCounters.entries)
        entry.key.label: entry.value,
    }, expected['successorCounters']);
  });

  test('callback retry from identical immutable inputs is byte-stable', () {
    final first = evaluate() as AuthorityRollMovementAccepted;
    final retry = evaluate() as AuthorityRollMovementAccepted;

    expect(
      retry.plan.enginePlan.toCanonicalPublicJson(),
      first.plan.enginePlan.toCanonicalPublicJson(),
    );
    expect(
      retry.plan.successorPrivateState.streamCounters,
      first.plan.successorPrivateState.streamCounters,
    );
    expect(retry.plan.safeResultSummary, first.plan.safeResultSummary);
  });

  test('auth mismatch and private version mismatch fail before Engine', () {
    expect(
      () => evaluate(authenticatedActorUid: 'uid-other'),
      throwsA(
        isA<AuthorityRollMovementViolation>().having(
          (error) => error.code,
          'code',
          'actorNotAuthenticatedMember',
        ),
      ),
    );
    expect(
      () => evaluate(
        privateState: syntheticRollPrivateState(rngVersion: 'unsupported'),
      ),
      throwsA(
        isA<AuthorityRollMovementViolation>().having(
          (error) => error.code,
          'code',
          'rngVersionMismatch',
        ),
      ),
    );
  });

  test('stale state is a zero-effect rejection with no private successor', () {
    final evaluation = evaluate(
      command: syntheticRollCommand(expectedStateVersion: 1),
    );

    expect(evaluation, isA<AuthorityRollMovementRejected>());
    final rejection = evaluation as AuthorityRollMovementRejected;
    expect(rejection.rejection.errorCode, RollMovementErrorCode.staleVersion);
    expect(rejection.publicResult['stateVersionAfter'], 0);
    expect(rejection.publicResult['events'], isEmpty);
  });

  test('semantic fingerprint excludes transport and auth metadata', () {
    final first = syntheticRollCommand();
    final sameSemanticCommand = syntheticRollCommand(
      commandId: 'different-command-id',
      clientInstanceId: 'different-client',
    );

    expect(
      AuthorityRollMovementPlanner.semanticMaterial(first),
      <String, Object?>{
        'v': 1,
        'family': 'game',
        'type': 'RollDice',
        'target': 'game-vp0',
        'expectedVersion': 0,
        'actorPlayerId': 'p1',
        'payload': const <String, Object?>{},
      },
    );
    expect(
      AuthorityRollMovementPlanner.inputHash(first),
      AuthorityRollMovementPlanner.inputHash(sameSemanticCommand),
    );
    expect(AuthorityRollMovementPlanner.inputHash(first), hasLength(64));
  });
}
