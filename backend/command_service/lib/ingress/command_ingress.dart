import '../observability/authority_execution_metrics.dart';
import '../observability/authority_observability.dart';

export '../observability/authority_execution_metrics.dart';

/// Captured exactly once per logical ingress request and reused across retries.
final class IngressContext {
  const IngressContext({required this.requestReceivedAt});

  final DateTime requestReceivedAt;
}

enum IngressCommandKind { room, game }

final class IngressCommandEnvelope {
  const IngressCommandEnvelope({
    required this.kind,
    required this.commandId,
    required this.inputHashVersion,
    required this.expectedVersion,
  });

  final IngressCommandKind kind;
  final String commandId;
  final int inputHashVersion;
  final int expectedVersion;
}

final class AuthorityExecutionResult<T> {
  const AuthorityExecutionResult({
    required this.value,
    required this.outcome,
    required this.reason,
    this.metrics = const AuthorityExecutionMetrics(),
  });

  final T value;
  final AuthorityOutcome outcome;
  final AuthorityReason reason;
  final AuthorityExecutionMetrics metrics;
}

typedef AuthorityExecutor<T> = Future<AuthorityExecutionResult<T>> Function(
  IngressContext context,
  IngressCommandEnvelope command,
);

/// Non-authoritative ingress orchestration.
///
/// This layer captures authority metadata, delegates gameplay decisions to the
/// authority executor, and emits only allowlisted observability fields.
final class CommandIngress {
  const CommandIngress({
    required BestEffortAuthorityObservability observability,
    DateTime Function()? now,
  }) : _observability = observability,
       _now = now ?? DateTime.now;

  final BestEffortAuthorityObservability _observability;
  final DateTime Function() _now;

  /// Observes one authenticated reconnect execution, including public egress
  /// validation performed by [execute]. Success describes this server boundary,
  /// not a command disposition, delivered ACK, or client reconciliation success.
  /// See docs/reconnect-authority-metrics.md for the measurement boundary.
  Future<T> handleRecovery<T>({
    required Future<T> Function() execute,
    required ({int schemaVersion, int stateVersion}) Function(T) versions,
  }) async {
    DateTime? startedAt;
    try {
      startedAt = _now();
    } on Object {
      // A diagnostic clock is not authority for the recovery operation.
    }
    final capture = AuthorityExecutionMetricsCapture();
    try {
      final result = await capture.run(execute);
      _emitRecovery(
        capture.metrics,
        startedAt,
        versions: () => versions(result),
      );
      return result;
    } on Object {
      _emitRecovery(capture.metrics, startedAt);
      rethrow;
    }
  }

  void _emitRecovery(
    AuthorityExecutionMetrics metrics,
    DateTime? startedAt, {
    ({int schemaVersion, int stateVersion}) Function()? versions,
  }) {
    try {
      if (startedAt == null) return;
      final confirmedVersions = versions?.call();
      _observability.emit(
        AuthorityLogEvent(
          operation: AuthorityOperation.recovery,
          outcome: versions == null
              ? AuthorityOutcome.internalFailure
              : AuthorityOutcome.success,
          reason: versions == null
              ? AuthorityReason.internalError
              : AuthorityReason.none,
          latencyMs: _elapsedMs(startedAt, _now()),
          retryCount: metrics.retryCount,
          conflictCount: metrics.conflictCount,
          firestoreReadCount: metrics.firestoreReadCount,
          firestoreWriteCount: metrics.firestoreWriteCount,
          bytesRead: metrics.bytesRead,
          bytesWritten: metrics.bytesWritten,
          snapshotBytes: 0,
          coldStart: false,
          schemaVersion: confirmedVersions?.schemaVersion,
          stateVersion: confirmedVersions?.stateVersion,
        ),
      );
    } on Object {
      // Clock, metadata, event construction and sink failures cannot alter the
      // original result/exception or turn success into a second error event.
    }
  }

  Future<T> handle<T>({
    required IngressCommandEnvelope command,
    required AuthorityExecutor<T> execute,
    IngressContext? ingressContext,
  }) async {
    if (command.commandId.isEmpty) {
      throw ArgumentError.value(
        command.commandId,
        'commandId',
        'must not be empty',
      );
    }
    if (command.inputHashVersion != 1) {
      throw ArgumentError.value(
        command.inputHashVersion,
        'inputHashVersion',
        'M1 requires canonical version 1',
      );
    }
    if (command.expectedVersion < 0) {
      throw ArgumentError.value(
        command.expectedVersion,
        'expectedVersion',
        'must be non-negative',
      );
    }

    final context =
        ingressContext ?? IngressContext(requestReceivedAt: _now().toUtc());
    DateTime? startedAt;
    try {
      startedAt = _now();
    } on Object {
      // The diagnostic clock is optional; the authority timestamp above is not.
    }
    final capture = AuthorityExecutionMetricsCapture();
    final AuthorityExecutionResult<T> result;
    try {
      result = await capture.run(() => execute(context, command));
    } on Object {
      _emitCommand(
        command.kind,
        capture.metrics,
        startedAt,
        outcome: AuthorityOutcome.internalFailure,
        reason: AuthorityReason.internalError,
      );
      rethrow;
    }

    _emitCommand(
      command.kind,
      result.metrics,
      startedAt,
      outcome: result.outcome,
      reason: result.reason,
    );
    return result.value;
  }

  void _emitCommand(
    IngressCommandKind kind,
    AuthorityExecutionMetrics metrics,
    DateTime? startedAt, {
    required AuthorityOutcome outcome,
    required AuthorityReason reason,
  }) {
    try {
      if (startedAt == null) return;
      _observability.emit(
        AuthorityLogEvent(
          operation: switch (kind) {
            IngressCommandKind.room => AuthorityOperation.roomCommand,
            IngressCommandKind.game => AuthorityOperation.gameCommand,
          },
          outcome: outcome,
          reason: reason,
          latencyMs: _elapsedMs(startedAt, _now()),
          retryCount: metrics.retryCount,
          conflictCount: metrics.conflictCount,
          firestoreReadCount: metrics.firestoreReadCount,
          firestoreWriteCount: metrics.firestoreWriteCount,
          bytesRead: metrics.bytesRead,
          bytesWritten: metrics.bytesWritten,
          snapshotBytes: metrics.snapshotBytes,
          coldStart: metrics.coldStart,
          schemaVersion: metrics.schemaVersion,
          stateVersion: metrics.stateVersion,
        ),
      );
    } on Object {
      // Invalid diagnostics cannot change the executor result/exception or
      // trigger a second event that incorrectly reports an authority failure.
    }
  }

  static int _elapsedMs(DateTime start, DateTime end) {
    final difference = end.difference(start).inMilliseconds;
    return difference < 0 ? 0 : difference;
  }
}
