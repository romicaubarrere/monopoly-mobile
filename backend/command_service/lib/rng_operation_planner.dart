import 'dart:typed_data';

import 'package:board_game_core/game_core.dart';

/// Authority-private RNG snapshot loaded from the durable secret store.
///
/// This type must never cross the command-service boundary or be serialized to
/// public state, logs, analytics, or mobile contracts.
final class AuthorityPrivateRngSnapshot {
  AuthorityPrivateRngSnapshot({
    required this.rngVersion,
    required List<int> seed,
    required Map<RngStream, int> streamCounters,
  }) : seed = Uint8List.fromList(seed),
       streamCounters = Map.unmodifiable(streamCounters);

  final String rngVersion;
  final Uint8List seed;
  final Map<RngStream, int> streamCounters;
}

/// An Engine-owned random need expressed to the authority RNG boundary.
///
/// The backend does not decide why a draw is needed or map its result to game
/// semantics. It only evaluates the canonical RNG transition requested by the
/// Engine and returns the private successor that must commit atomically with
/// the Engine-produced public transition.
final class AuthorityRandomDraw {
  const AuthorityRandomDraw({required this.stream, required this.upperBound});

  final RngStream stream;
  final int upperBound;
}

/// Persistence-neutral result of evaluating an authority random operation.
final class AuthorityRandomOperationPlan {
  AuthorityRandomOperationPlan({
    required this.rngVersion,
    required List<int> values,
    required Map<RngStream, int> successorCounters,
    required this.candidatesConsumed,
  }) : values = List.unmodifiable(values),
       successorCounters = Map.unmodifiable(successorCounters);

  final String rngVersion;
  final List<int> values;
  final Map<RngStream, int> successorCounters;
  final int candidatesConsumed;
}

/// Invokes the canonical pure-Dart RNG without owning gameplay rules.
///
/// The planner is pure: transaction callback retries from an identical private
/// snapshot reproduce the same values and successor counters. Only the durable
/// adapter may persist the returned successor, in the same transaction as the
/// public Engine result, command result, and stateVersion successor.
abstract final class AuthorityRngOperationPlanner {
  static AuthorityRandomOperationPlan evaluate({
    required AuthorityPrivateRngSnapshot privateSnapshot,
    required List<AuthorityRandomDraw> draws,
  }) {
    if (privateSnapshot.rngVersion != canonicalRngVersion) {
      throw RngContractViolation(
        'Unsupported RNG version: ${privateSnapshot.rngVersion}',
      );
    }
    if (draws.isEmpty) {
      throw const RngContractViolation(
        'An authority random operation requires at least one draw',
      );
    }

    var rng = CanonicalRng(
      seed: privateSnapshot.seed,
      counters: privateSnapshot.streamCounters,
    );
    final values = <int>[];
    var candidatesConsumed = 0;

    for (final draw in draws) {
      final transition = rng.nextInt(draw.stream, draw.upperBound);
      values.add(transition.value);
      candidatesConsumed += transition.candidatesConsumed;
      rng = transition.successor;
    }

    return AuthorityRandomOperationPlan(
      rngVersion: canonicalRngVersion,
      values: values,
      successorCounters: <RngStream, int>{
        for (final stream in RngStream.values) stream: rng.counterFor(stream),
      },
      candidatesConsumed: candidatesConsumed,
    );
  }
}
