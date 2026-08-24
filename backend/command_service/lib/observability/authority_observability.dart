enum AuthorityOperation {
  roomCommand,
  gameCommand,
  deadlineResolution,
  recovery,
}

enum AuthorityOutcome {
  success,
  rejected,
  duplicate,
  collision,
  stale,
  retryableFailure,
  internalFailure,
}

enum AuthorityReason {
  none,
  duplicateCommand,
  commandIdCollision,
  staleVersion,
  decisionClosed,
  retryableConflict,
  internalError,
}

final class AuthorityLogEvent {
  AuthorityLogEvent({
    required this.operation,
    required this.outcome,
    required this.reason,
    required this.latencyMs,
    required this.retryCount,
    required this.conflictCount,
    required this.firestoreReadCount,
    required this.firestoreWriteCount,
    required this.bytesRead,
    required this.bytesWritten,
    required this.snapshotBytes,
    required this.coldStart,
    this.schemaVersion,
    this.stateVersion,
  }) {
    final numericValues = <int>[
      latencyMs,
      retryCount,
      conflictCount,
      firestoreReadCount,
      firestoreWriteCount,
      bytesRead,
      bytesWritten,
      snapshotBytes,
      if (schemaVersion != null) schemaVersion!,
      if (stateVersion != null) stateVersion!,
    ];
    if (numericValues.any((value) => value < 0)) {
      throw ArgumentError.value(
        numericValues,
        'numericValues',
        'must be non-negative',
      );
    }
  }

  final AuthorityOperation operation;
  final AuthorityOutcome outcome;
  final AuthorityReason reason;
  final int latencyMs;
  final int retryCount;
  final int conflictCount;
  final int firestoreReadCount;
  final int firestoreWriteCount;
  final int bytesRead;
  final int bytesWritten;
  final int snapshotBytes;
  final bool coldStart;
  final int? schemaVersion;
  final int? stateVersion;

  Map<String, Object> toLogFields() => <String, Object>{
    'operation': operation.name,
    'outcome': outcome.name,
    'reason': reason.name,
    'latencyMs': latencyMs,
    'retryCount': retryCount,
    'conflictCount': conflictCount,
    'firestoreReadCount': firestoreReadCount,
    'firestoreWriteCount': firestoreWriteCount,
    'bytesRead': bytesRead,
    'bytesWritten': bytesWritten,
    'snapshotBytes': snapshotBytes,
    'coldStart': coldStart,
    if (schemaVersion != null) 'schemaVersion': schemaVersion!,
    if (stateVersion != null) 'stateVersion': stateVersion!,
  };
}

abstract interface class AuthorityLogSink {
  void write(Map<String, Object> fields);
}

final class NoopAuthorityLogSink implements AuthorityLogSink {
  const NoopAuthorityLogSink();

  @override
  void write(Map<String, Object> fields) {}
}

final class BestEffortAuthorityObservability {
  const BestEffortAuthorityObservability(this._sink);

  final AuthorityLogSink _sink;

  void emit(AuthorityLogEvent event) {
    try {
      _sink.write(event.toLogFields());
    } on Object {
      // Observability must never become authoritative gameplay failure.
    }
  }
}
