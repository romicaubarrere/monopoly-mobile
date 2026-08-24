import '../observability/authority_observability.dart';

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

final class AuthorityExecutionMetrics {
  const AuthorityExecutionMetrics({
    this.retryCount = 0,
    this.conflictCount = 0,
    this.firestoreReadCount = 0,
    this.firestoreWriteCount = 0,
    this.bytesRead = 0,
    this.bytesWritten = 0,
    this.snapshotBytes = 0,
    this.schemaVersion,
    this.stateVersion,
    this.coldStart = false,
  });

  final int retryCount;
  final int conflictCount;
  final int firestoreReadCount;
  final int firestoreWriteCount;
  final int bytesRead;
  final int bytesWritten;
  final int snapshotBytes;
  final int? schemaVersion;
  final int? stateVersion;
  final bool coldStart;
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

  Future<T> handle<T>({
    required IngressCommandEnvelope command,
    required AuthorityExecutor<T> execute,
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

    final requestReceivedAt = _now().toUtc();
    final context = IngressContext(requestReceivedAt: requestReceivedAt);
    final startedAt = _now();

    try {
      final result = await execute(context, command);
      final metrics = result.metrics;

      _observability.emit(
        AuthorityLogEvent(
          operation: switch (command.kind) {
            IngressCommandKind.room => AuthorityOperation.roomCommand,
            IngressCommandKind.game => AuthorityOperation.gameCommand,
          },
          outcome: result.outcome,
          reason: result.reason,
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

      return result.value;
    } on Object {
      _observability.emit(
        AuthorityLogEvent(
          operation: switch (command.kind) {
            IngressCommandKind.room => AuthorityOperation.roomCommand,
            IngressCommandKind.game => AuthorityOperation.gameCommand,
          },
          outcome: AuthorityOutcome.internalFailure,
          reason: AuthorityReason.internalError,
          latencyMs: _elapsedMs(startedAt, _now()),
          retryCount: 0,
          conflictCount: 0,
          firestoreReadCount: 0,
          firestoreWriteCount: 0,
          bytesRead: 0,
          bytesWritten: 0,
          snapshotBytes: 0,
          coldStart: false,
        ),
      );
      rethrow;
    }
  }

  static int _elapsedMs(DateTime start, DateTime end) {
    final difference = end.difference(start).inMilliseconds;
    return difference < 0 ? 0 : difference;
  }
}
