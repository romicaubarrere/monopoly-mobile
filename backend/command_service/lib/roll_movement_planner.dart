import 'package:board_backend_api/backend_api.dart';
import 'package:board_game_core/game_core.dart';

import 'rng_operation_planner.dart';

final class AuthorityRollMovementViolation implements Exception {
  const AuthorityRollMovementViolation(this.code);

  final String code;

  @override
  String toString() => 'AuthorityRollMovementViolation: $code';
}

/// Persistence-neutral authority composition around the canonical Engine
/// Roll/movement transition.
///
/// Duplicate/collision lookup happens before this planner. A durable adapter
/// invokes [AuthorityRollMovementPlanner.evaluate] only for a new command, then
/// commits [stateAfter], [successorPrivateState], and [safeResultSummary] in one
/// transaction. Transaction retries must reuse the same immutable inputs and
/// authority-captured [transitionTime].
final class AuthorityRollMovementPlan {
  AuthorityRollMovementPlan({
    required this.enginePlan,
    required this.successorPrivateState,
  });

  final RollMovementPlan enginePlan;
  final AuthorityPrivateRngSnapshot successorPrivateState;

  PublicGameState get stateAfter => enginePlan.stateAfter;

  Map<String, Object?> get safeResultSummary => <String, Object?>{
    'commandId': enginePlan.commandId,
    'status': 'accepted',
    'stateVersionBefore': enginePlan.stateVersionBefore,
    'stateVersionAfter': enginePlan.stateVersionAfter,
    'events': enginePlan.events
        .map((event) => event.toJson())
        .toList(growable: false),
  };
}

sealed class AuthorityRollMovementEvaluation {
  const AuthorityRollMovementEvaluation();

  bool get accepted;
  Map<String, Object?> get publicResult;
}

final class AuthorityRollMovementAccepted
    extends AuthorityRollMovementEvaluation {
  const AuthorityRollMovementAccepted(this.plan);

  final AuthorityRollMovementPlan plan;

  @override
  bool get accepted => true;

  @override
  Map<String, Object?> get publicResult => plan.safeResultSummary;
}

final class AuthorityRollMovementRejected
    extends AuthorityRollMovementEvaluation {
  const AuthorityRollMovementRejected(this.rejection);

  final RollMovementRejection rejection;

  @override
  bool get accepted => false;

  @override
  Map<String, Object?> get publicResult => rejection.toPublicJson();
}

/// Composes identity and private RNG boundaries with Engine-owned gameplay.
///
/// This class deliberately does not calculate dice, movement, landing effects,
/// or deadlines. Those semantics stay single-owned by [RollMovementEngine].
abstract final class AuthorityRollMovementPlanner {
  static AuthorityRollMovementEvaluation evaluate({
    required GameCommand command,
    required String authenticatedActorUid,
    required Map<String, String> memberUidByPlayerId,
    required PublicGameState state,
    required RulesCatalog catalog,
    required AuthorityPrivateRngSnapshot privateSnapshot,
    required DateTime transitionTime,
  }) {
    if (authenticatedActorUid.isEmpty ||
        memberUidByPlayerId[command.actorPlayerId] != authenticatedActorUid) {
      throw const AuthorityRollMovementViolation('actorNotAuthenticatedMember');
    }
    if (privateSnapshot.rngVersion != canonicalRngVersion ||
        state.header.rngVersion != privateSnapshot.rngVersion) {
      throw const AuthorityRollMovementViolation('rngVersionMismatch');
    }

    final rng = CanonicalRng(
      seed: privateSnapshot.seed,
      counters: privateSnapshot.streamCounters,
    );
    final evaluation = RollMovementEngine.evaluate(
      command: command,
      state: state,
      catalog: catalog,
      rng: rng,
      transitionTime: transitionTime,
    );
    if (evaluation is RollMovementRejection) {
      return AuthorityRollMovementRejected(evaluation);
    }
    final enginePlan = evaluation as RollMovementPlan;
    return AuthorityRollMovementAccepted(
      AuthorityRollMovementPlan(
        enginePlan: enginePlan,
        successorPrivateState: AuthorityPrivateRngSnapshot(
          rngVersion: privateSnapshot.rngVersion,
          seed: privateSnapshot.seed,
          streamCounters: <RngStream, int>{
            for (final stream in RngStream.values)
              stream: enginePlan.successorRng.counterFor(stream),
          },
        ),
      ),
    );
  }

  /// Semantic identity used for commandId duplicate/collision classification.
  /// Transport metadata, auth material, commandId, and clientInstanceId remain
  /// excluded by the v1 contract.
  static Map<String, Object?> semanticMaterial(GameCommand command) =>
      <String, Object?>{
        'v': SemanticFingerprintV1.version,
        'family': 'game',
        'type': command.type.wireValue,
        'target': command.gameId,
        'expectedVersion': command.expectedStateVersion,
        'actorPlayerId': command.actorPlayerId,
        'payload': command.payload,
      };

  static String inputHash(GameCommand command) =>
      SemanticFingerprintV1.sha256Hex(semanticMaterial(command));
}
