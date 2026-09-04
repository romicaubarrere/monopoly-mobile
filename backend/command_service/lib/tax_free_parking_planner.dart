import 'package:board_backend_api/backend_api.dart';
import 'package:board_game_core/game_core.dart';

final class AuthorityTaxFreeParkingViolation implements Exception {
  const AuthorityTaxFreeParkingViolation(this.code);

  final String code;

  @override
  String toString() => 'AuthorityTaxFreeParkingViolation: $code';
}

/// Atomic public-state plan produced by the canonical landing-economy Engine.
///
/// Tax and Free Parking consume no randomness. The durable adapter therefore
/// commits [stateAfter] and [safeResultSummary] together while leaving the
/// existing private RNG document byte-for-byte unchanged.
final class AuthorityTaxFreeParkingPlan {
  const AuthorityTaxFreeParkingPlan(this.enginePlan);

  final TaxFreeParkingPlan enginePlan;

  PublicGameState get stateAfter => enginePlan.stateAfter;

  Map<String, Object?> get safeResultSummary => <String, Object?>{
    'commandId': enginePlan.operationId,
    'operationId': enginePlan.operationId,
    'status': 'accepted',
    'stateVersionBefore': enginePlan.stateVersionBefore,
    'stateVersionAfter': enginePlan.stateVersionAfter,
    'kind': enginePlan.kind.wireValue,
    'amount': enginePlan.amount,
    'events': enginePlan.events
        .map((event) => event.toJson())
        .toList(growable: false),
  };
}

sealed class AuthorityTaxFreeParkingEvaluation {
  const AuthorityTaxFreeParkingEvaluation();

  bool get accepted;
  Map<String, Object?> get publicResult;
}

final class AuthorityTaxFreeParkingAccepted
    extends AuthorityTaxFreeParkingEvaluation {
  const AuthorityTaxFreeParkingAccepted(this.plan);

  final AuthorityTaxFreeParkingPlan plan;

  @override
  bool get accepted => true;

  @override
  Map<String, Object?> get publicResult => plan.safeResultSummary;
}

final class AuthorityTaxFreeParkingRejected
    extends AuthorityTaxFreeParkingEvaluation {
  const AuthorityTaxFreeParkingRejected(this.rejection);

  final TaxFreeParkingRejection rejection;

  @override
  bool get accepted => false;

  @override
  Map<String, Object?> get publicResult => <String, Object?>{
    'commandId': rejection.operationId,
    ...rejection.toPublicJson(),
  };
}

/// Authority composition for automatic tax and Free Parking landing effects.
///
/// The caller captures the landing index, expected state version and
/// transition time when it schedules this immutable operation. Authority
/// revalidates that context inside the durable transaction, then delegates all
/// economy and debt semantics to [TaxFreeParkingEngine].
abstract final class AuthorityTaxFreeParkingPlanner {
  static AuthorityTaxFreeParkingEvaluation evaluateSystem({
    required String operationId,
    required int expectedStateVersion,
    required String playerId,
    required int expectedLandingIndex,
    required PublicGameState state,
    required RulesCatalog catalog,
    required DateTime transitionTime,
  }) {
    final matches = state.players.where(
      (player) =>
          player.playerId == playerId && player.status == PlayerStatus.active,
    );
    if (matches.length == 1 &&
        matches.single.position != expectedLandingIndex) {
      return AuthorityTaxFreeParkingRejected(
        TaxFreeParkingRejection(
          operationId: operationId,
          stateVersionBefore: state.header.stateVersion,
          errorCode: TaxFreeParkingErrorCode.invalidState,
        ),
      );
    }

    final evaluation = TaxFreeParkingEngine.evaluate(
      operationId: operationId,
      expectedStateVersion: expectedStateVersion,
      playerId: playerId,
      state: state,
      catalog: catalog,
      transitionTime: transitionTime.toUtc(),
    );
    if (evaluation is TaxFreeParkingRejection) {
      return AuthorityTaxFreeParkingRejected(evaluation);
    }
    return AuthorityTaxFreeParkingAccepted(
      AuthorityTaxFreeParkingPlan(evaluation as TaxFreeParkingPlan),
    );
  }

  /// Stable semantic identity for duplicate/collision classification.
  ///
  /// The transport operation id is deliberately excluded, matching the
  /// repository's fingerprint-v1 convention. The captured transition time is
  /// included because it determines the canonical DebtCase deadline.
  static Map<String, Object?> semanticMaterial({
    required String gameId,
    required int expectedStateVersion,
    required String playerId,
    required int expectedLandingIndex,
    required DateTime transitionTime,
  }) => <String, Object?>{
    'v': SemanticFingerprintV1.version,
    'family': 'game',
    'type': 'automaticLandingEconomy',
    'target': gameId,
    'expectedVersion': expectedStateVersion,
    'playerId': playerId,
    'landingIndex': expectedLandingIndex,
    'transitionTime': transitionTime.toUtc().toIso8601String(),
  };

  static String inputHash({
    required String gameId,
    required int expectedStateVersion,
    required String playerId,
    required int expectedLandingIndex,
    required DateTime transitionTime,
  }) => SemanticFingerprintV1.sha256Hex(
    semanticMaterial(
      gameId: gameId,
      expectedStateVersion: expectedStateVersion,
      playerId: playerId,
      expectedLandingIndex: expectedLandingIndex,
      transitionTime: transitionTime,
    ),
  );
}
