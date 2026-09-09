import 'package:board_command_service/command_service.dart';
import 'package:board_game_core/game_core.dart';

import 'synthetic_tax_free_parking_fixture.dart';

final class SyntheticTaxFreeParkingPlan {
  const SyntheticTaxFreeParkingPlan({
    required this.operationId,
    required this.expectedStateVersion,
    required this.playerId,
    required this.expectedLandingIndex,
    required this.transitionTime,
    required this.inputHashMarker,
    required this.plan,
  });

  final String operationId;
  final int expectedStateVersion;
  final String playerId;
  final int expectedLandingIndex;
  final DateTime transitionTime;
  final String inputHashMarker;
  final AuthorityTaxFreeParkingPlan plan;

  Map<String, Object?> toJson() => <String, Object?>{
    'operation': <String, Object?>{
      'operationId': operationId,
      'expectedStateVersion': expectedStateVersion,
      'playerId': playerId,
      'expectedLandingIndex': expectedLandingIndex,
      'transitionTime': transitionTime.toUtc().toIso8601String(),
    },
    'inputHashMarker': inputHashMarker,
    'stateAfter': plan.stateAfter.toJson(),
    'resultSummary': plan.safeResultSummary,
  };
}

Map<String, Object?> syntheticTaxFreeParkingFixtureJson() {
  final catalog = syntheticTaxFreeParkingCatalog();

  Map<String, Object?> scenario({
    required String name,
    required PublicGameState initialState,
    required int landingIndex,
    bool competingPlans = false,
  }) {
    SyntheticTaxFreeParkingPlan build(String suffix) {
      final operationId = 'landing-$name-$suffix';
      final accepted = AuthorityTaxFreeParkingPlanner.evaluateSystem(
        operationId: operationId,
        expectedStateVersion: initialState.header.stateVersion,
        playerId: 'p1',
        expectedLandingIndex: landingIndex,
        state: initialState,
        catalog: catalog,
        transitionTime: syntheticTaxFreeParkingTime,
      ) as AuthorityTaxFreeParkingAccepted;
      return SyntheticTaxFreeParkingPlan(
        operationId: operationId,
        expectedStateVersion: initialState.header.stateVersion,
        playerId: 'p1',
        expectedLandingIndex: landingIndex,
        transitionTime: syntheticTaxFreeParkingTime,
        inputHashMarker: 'fixture-semantic-hash-v1-$name',
        plan: accepted.plan,
      );
    }

    return <String, Object?>{
      'initialState': initialState.toJson(),
      'plans': <String, Object?>{
        'a': build('a').toJson(),
        if (competingPlans) 'b': build('b').toJson(),
      },
    };
  }

  return <String, Object?>{
    'tax': scenario(
      name: 'tax',
      initialState: syntheticTaxFreeParkingState(),
      landingIndex: 31,
      competingPlans: true,
    ),
    'debt': scenario(
      name: 'debt',
      initialState: syntheticTaxFreeParkingState(cash: 99),
      landingIndex: 31,
    ),
    'collection': scenario(
      name: 'collection',
      initialState: syntheticTaxFreeParkingState(position: 33, pot: 263),
      landingIndex: 33,
      competingPlans: true,
    ),
    'zeroCollection': scenario(
      name: 'zero-collection',
      initialState: syntheticTaxFreeParkingState(position: 33, pot: 0),
      landingIndex: 33,
    ),
    'privateSentinel': <String, Object?>{
      'rngVersion': canonicalRngVersion,
      'seedMarker': 'authority-private-unchanged',
      'streamCounters': <String, Object?>{'dice': 2},
    },
  };
}
