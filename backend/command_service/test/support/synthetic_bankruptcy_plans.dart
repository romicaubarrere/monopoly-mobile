import 'package:board_command_service/command_service.dart';
import 'package:board_game_core/game_core.dart';

import 'synthetic_bankruptcy_fixture.dart';

final class SyntheticBankruptcyPlan {
  const SyntheticBankruptcyPlan({
    required this.command,
    required this.inputHashMarker,
    required this.initialState,
    required this.plan,
  });

  final GameCommand command;
  final String inputHashMarker;
  final PublicGameState initialState;
  final AuthorityBankruptcyPlan plan;

  Map<String, Object?> toJson() => <String, Object?>{
    'command': command.toJson(),
    'inputHashMarker': inputHashMarker,
    'initialState': initialState.toJson(),
    'stateAfter': plan.stateAfter.toJson(),
    'resultSummary': plan.safeResultSummary,
  };
}

Map<String, SyntheticBankruptcyPlan> syntheticBankruptcyPlans() {
  final catalog = syntheticBankruptcyCatalog();
  const members = <String, String>{'p1': 'uid-p1', 'p2': 'uid-p2'};
  final initial = syntheticBankruptcyState();

  SyntheticBankruptcyPlan human(String commandId) {
    final command = syntheticBankruptcyCommand(
      GameCommandType.declareBankruptcy,
      commandId: commandId,
    );
    final accepted = AuthorityBankruptcyPlanner.evaluateHuman(
      command: command,
      authenticatedActorUid: 'uid-p1',
      memberUidByPlayerId: members,
      state: initial,
      catalog: catalog,
      requestReceivedAt: syntheticBankruptcyTime,
    ) as AuthorityBankruptcyAccepted;
    return SyntheticBankruptcyPlan(
      command: command,
      inputHashMarker: 'fixture-semantic-hash-v1-declare',
      initialState: initial,
      plan: accepted.plan,
    );
  }

  final deadline = AuthorityBankruptcyPlanner.evaluateDeadline(
    state: initial,
    catalog: catalog,
    authorityNow: syntheticBankruptcyDeadline,
    decisionId: 'debt-1:decision',
    debtCaseId: 'debt-1',
    debtorPlayerId: 'p1',
    expectedStateVersion: 1,
  ) as AuthorityBankruptcyAccepted;
  final deadlineCommand = GameCommand(
    commandId: deadline.plan.enginePlan.commandId,
    schemaVersion: initial.header.schemaVersion,
    expectedStateVersion: initial.header.stateVersion,
    clientInstanceId: 'authority-system',
    gameId: initial.header.gameId,
    actorPlayerId: 'p1',
    type: GameCommandType.declareBankruptcy,
    payload: const <String, Object?>{
      'debtCaseId': 'debt-1',
      'decisionId': 'debt-1:decision',
    },
  );

  return <String, SyntheticBankruptcyPlan>{
    'declareA': human('cmd-bankruptcy-a'),
    'declareB': human('cmd-bankruptcy-b'),
    'deadline': SyntheticBankruptcyPlan(
      command: deadlineCommand,
      inputHashMarker: 'fixture-semantic-hash-v1-declare',
      initialState: initial,
      plan: deadline.plan,
    ),
  };
}

Map<String, Object?> syntheticBankruptcyFixtureJson() => <String, Object?>{
  for (final entry in syntheticBankruptcyPlans().entries)
    entry.key: entry.value.toJson(),
  'privateSentinel': <String, Object?>{
    'rngVersion': canonicalRngVersion,
    'seedMarker': 'authority-private-unchanged',
    'streamCounters': <String, Object?>{'dice': 2},
  },
};
