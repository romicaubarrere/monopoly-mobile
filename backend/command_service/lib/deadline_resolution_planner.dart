import 'package:board_game_core/game_core.dart';

enum DeadlinePlanDisposition { noOp, terminal, delegate }

final class DeadlineResolutionPlan {
  const DeadlineResolutionPlan({
    required this.disposition,
    required this.decisionId,
    required this.expectedStateVersion,
    required this.action,
    required this.reason,
    this.operationId,
  });

  final DeadlinePlanDisposition disposition;
  final String decisionId;
  final int? expectedStateVersion;
  final DeadlineAction action;
  final String reason;
  final String? operationId;

  String get dispositionWireName => switch (disposition) {
    DeadlinePlanDisposition.noOp => 'no_op',
    DeadlinePlanDisposition.terminal => 'terminal',
    DeadlinePlanDisposition.delegate => 'delegate',
  };

  String get actionWireName => switch (action) {
    DeadlineAction.pass => 'pass',
    DeadlineAction.reject => 'reject',
    DeadlineAction.delegateBotDecision => 'delegateBotDecision',
    DeadlineAction.delegateAutoLiquidation => 'delegateAutoLiquidation',
    DeadlineAction.none => 'none',
  };
}

/// Authority adapter from the canonical Engine deadline decision into a
/// persistence-neutral plan.
///
/// This class intentionally owns no timeout policy. It delegates all gameplay
/// interpretation to [DeadlineTimeoutEngine] and only translates its result into
/// fields a durable adapter can validate and persist atomically.
abstract final class DeadlineResolutionPlanner {
  static DeadlineResolutionPlan plan({
    required PendingDecision? currentDecision,
    required String decisionId,
    required DateTime authorityNow,
  }) {
    final resolution = DeadlineTimeoutEngine.resolveCurrent(
      currentDecision: currentDecision,
      decisionId: decisionId,
      authorityNow: authorityNow,
    );

    if (!resolution.isDue) {
      return DeadlineResolutionPlan(
        disposition: DeadlinePlanDisposition.noOp,
        decisionId: decisionId,
        expectedStateVersion: currentDecision?.stateVersionCreated,
        action: DeadlineAction.none,
        reason: resolution.status.name,
      );
    }

    final decision = currentDecision!;
    return DeadlineResolutionPlan(
      disposition: resolution.isTerminal
          ? DeadlinePlanDisposition.terminal
          : DeadlinePlanDisposition.delegate,
      decisionId: decision.decisionId,
      expectedStateVersion: decision.stateVersionCreated,
      action: resolution.action,
      reason: resolution.isTerminal ? 'expired' : 'requiresEnginePolicy',
      operationId: resolution.operationId,
    );
  }
}
