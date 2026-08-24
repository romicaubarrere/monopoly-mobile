enum DeadlineEligibility { eligible, decisionClosed }

final class PersistedDecisionDeadline {
  const PersistedDecisionDeadline({
    required this.decisionId,
    required this.deadlineAtMs,
  });

  final String decisionId;
  final int deadlineAtMs;

  DeadlineEligibility classifyHumanCommand({
    required int requestReceivedAtMs,
  }) => requestReceivedAtMs < deadlineAtMs
      ? DeadlineEligibility.eligible
      : DeadlineEligibility.decisionClosed;

  String get operationId => 'deadline:v1:$decisionId';
}

/// Dedupe boundary for lazy deadline wake-up.
///
/// It does not choose gameplay outcome. The authority/Engine callback owns the
/// deterministic timeout transition; this guard only ensures the persisted
/// operation id can produce at most one effect.
final class DeadlineOperationGuard {
  final Set<String> _completed = <String>{};

  bool begin(PersistedDecisionDeadline deadline) =>
      _completed.add(deadline.operationId);

  bool hasCompleted(PersistedDecisionDeadline deadline) =>
      _completed.contains(deadline.operationId);
}
