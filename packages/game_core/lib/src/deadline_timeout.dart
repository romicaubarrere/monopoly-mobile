/// Pure-Dart deadline semantics for M1 pending decisions.
///
/// Persistence owns the exactly-once operation record. This module only decides
/// whether a deadline is due and what deterministic Engine action must happen.
/// It deliberately does not choose bot strategy or a debt liquidation plan.
enum PendingDecisionKind {
  propertyOffer,
  auctionTurn,
  cuchaExit,
  cardChoice,
  debtResolution,
  tradeResponse,
}

enum TimeoutPolicy {
  pass,
  reject,
  botDecide,
  autoLiquidate,
  none,
}

final class PendingDecision {
  PendingDecision({
    required this.decisionId,
    required this.kind,
    required List<String> allowedPlayerIds,
    required this.stateVersionCreated,
    required this.createdAt,
    required this.timeoutPolicy,
    this.deadlineAt,
  }) : allowedPlayerIds = List.unmodifiable(allowedPlayerIds) {
    if (decisionId.isEmpty) {
      throw ArgumentError.value(decisionId, 'decisionId', 'must not be empty');
    }
    if (stateVersionCreated < 0) {
      throw ArgumentError.value(
        stateVersionCreated,
        'stateVersionCreated',
        'must be non-negative',
      );
    }
  }

  final String decisionId;
  final PendingDecisionKind kind;
  final List<String> allowedPlayerIds;
  final int stateVersionCreated;
  final DateTime createdAt;
  final DateTime? deadlineAt;
  final TimeoutPolicy timeoutPolicy;
}

enum DeadlineResolutionStatus {
  staleDecision,
  noDeadline,
  notDue,
  ready,
}

enum DeadlineAction {
  pass,
  reject,
  delegateBotDecision,
  delegateAutoLiquidation,
  none,
}

final class DeadlineResolution {
  const DeadlineResolution._({
    required this.status,
    required this.action,
    this.operationId,
  });

  const DeadlineResolution.stale()
    : this._(
        status: DeadlineResolutionStatus.staleDecision,
        action: DeadlineAction.none,
      );

  const DeadlineResolution.noDeadline()
    : this._(
        status: DeadlineResolutionStatus.noDeadline,
        action: DeadlineAction.none,
      );

  const DeadlineResolution.notDue()
    : this._(
        status: DeadlineResolutionStatus.notDue,
        action: DeadlineAction.none,
      );

  const DeadlineResolution.ready({
    required String operationId,
    required DeadlineAction action,
  }) : this._(
         status: DeadlineResolutionStatus.ready,
         action: action,
         operationId: operationId,
       );

  final DeadlineResolutionStatus status;
  final DeadlineAction action;
  final String? operationId;

  bool get isDue => status == DeadlineResolutionStatus.ready;

  /// Only pass/reject are complete deterministic timeout outcomes in this
  /// slice. Bot decisions and debt liquidation remain explicit delegations.
  bool get isTerminal =>
      isDue &&
      (action == DeadlineAction.pass || action == DeadlineAction.reject);
}

abstract final class DeadlineTimeoutEngine {
  static String operationIdFor(String decisionId) => 'deadline:v1:$decisionId';

  /// Resolves deadline eligibility using authority time.
  ///
  /// The boundary is inclusive: a request to materialize the deadline at
  /// `deadlineAt` is due. Human command ingress uses its separately captured
  /// requestReceivedAt and is intentionally outside this function.
  static DeadlineResolution resolveCurrent({
    required PendingDecision? currentDecision,
    required String decisionId,
    required DateTime authorityNow,
  }) {
    if (currentDecision == null || currentDecision.decisionId != decisionId) {
      return const DeadlineResolution.stale();
    }

    final deadlineAt = currentDecision.deadlineAt;
    if (deadlineAt == null) {
      return const DeadlineResolution.noDeadline();
    }
    if (authorityNow.isBefore(deadlineAt)) {
      return const DeadlineResolution.notDue();
    }

    return DeadlineResolution.ready(
      operationId: operationIdFor(currentDecision.decisionId),
      action: _actionFor(currentDecision.timeoutPolicy),
    );
  }

  /// Applies only timeout outcomes that are complete without another Engine
  /// policy. Returning the same decision for delegated work prevents a caller
  /// from silently treating bot choice or auto-liquidation as already done.
  static PendingDecision? applyTerminalOutcome({
    required PendingDecision currentDecision,
    required DeadlineResolution resolution,
  }) {
    if (!resolution.isTerminal) {
      return currentDecision;
    }
    return null;
  }

  static DeadlineAction _actionFor(TimeoutPolicy policy) => switch (policy) {
    TimeoutPolicy.pass => DeadlineAction.pass,
    TimeoutPolicy.reject => DeadlineAction.reject,
    TimeoutPolicy.botDecide => DeadlineAction.delegateBotDecision,
    TimeoutPolicy.autoLiquidate => DeadlineAction.delegateAutoLiquidation,
    TimeoutPolicy.none => DeadlineAction.none,
  };
}
