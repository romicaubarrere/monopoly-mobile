import '../lib/observability/authority_observability.dart';

void main() {
  final event = AuthorityLogEvent(
    operation: AuthorityOperation.gameCommand,
    outcome: AuthorityOutcome.success,
    reason: AuthorityReason.none,
    latencyMs: 12,
    retryCount: 0,
    conflictCount: 0,
    firestoreReadCount: 2,
    firestoreWriteCount: 1,
    bytesRead: 128,
    bytesWritten: 64,
    snapshotBytes: 512,
    coldStart: false,
    schemaVersion: 1,
    stateVersion: 7,
  );

  final fields = event.toLogFields();
  const forbiddenKeys = <String>{
    'token',
    'authorization',
    'roomCode',
    'uid',
    'playerId',
    'rngSeed',
    'rngCounter',
    'futureDeckOrder',
    'commandPayload',
    'freeText',
  };
  if (fields.keys.any(forbiddenKeys.contains)) {
    throw StateError('forbidden observability field exposed');
  }

  final throwing = BestEffortAuthorityObservability(_ThrowingSink());
  throwing.emit(event);

  var negativeRejected = false;
  try {
    AuthorityLogEvent(
      operation: AuthorityOperation.roomCommand,
      outcome: AuthorityOutcome.rejected,
      reason: AuthorityReason.staleVersion,
      latencyMs: -1,
      retryCount: 0,
      conflictCount: 0,
      firestoreReadCount: 0,
      firestoreWriteCount: 0,
      bytesRead: 0,
      bytesWritten: 0,
      snapshotBytes: 0,
      coldStart: false,
    );
  } on ArgumentError {
    negativeRejected = true;
  }
  if (!negativeRejected) {
    throw StateError('negative metrics must be rejected');
  }

  print('Authority observability smoke: PASS');
}

final class _ThrowingSink implements AuthorityLogSink {
  @override
  void write(Map<String, Object> fields) => throw StateError('sink unavailable');
}
