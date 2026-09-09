import 'dart:async';

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

/// Single-use, non-authoritative accounting for one awaited ingress execution.
///
/// The private zone value avoids putting mutable state on a reused context or
/// shared store. No error handler is installed: errors keep their original
/// identity and error zone. Each store operation publishes once, after cleanup.
/// See docs/firestore-retry-metrics.md for lifetime and measurement boundaries.
final class AuthorityExecutionMetricsCapture {
  static final Object _zoneKey = Object();

  AuthorityExecutionMetrics _metrics = const AuthorityExecutionMetrics();
  bool _started = false;
  bool _closed = false;

  AuthorityExecutionMetrics get metrics => _metrics;

  Future<T> run<T>(Future<T> Function() execute) async {
    if (_started) throw StateError('Metrics capture is single-use');
    _started = true;
    try {
      return await runZoned(
        execute,
        zoneValues: <Object, Object>{_zoneKey: this},
      );
    } finally {
      // Detached work still inherits this zone but may not mutate a completed
      // request's evidence or publish into a later request's capture.
      _closed = true;
    }
  }

  static void record(AuthorityExecutionMetrics snapshot) {
    try {
      final capture = Zone.current[_zoneKey];
      if (capture is! AuthorityExecutionMetricsCapture ||
          capture._closed ||
          !_valid(snapshot)) {
        return;
      }
      final previous = capture._metrics;
      final total = AuthorityExecutionMetrics(
        retryCount: previous.retryCount + snapshot.retryCount,
        conflictCount: previous.conflictCount + snapshot.conflictCount,
        firestoreReadCount:
            previous.firestoreReadCount + snapshot.firestoreReadCount,
        firestoreWriteCount:
            previous.firestoreWriteCount + snapshot.firestoreWriteCount,
        bytesRead: previous.bytesRead + snapshot.bytesRead,
        bytesWritten: previous.bytesWritten + snapshot.bytesWritten,
      );
      // Versions and snapshot/cold-start defaults are not failure evidence.
      // Reject malformed or overflowing totals instead of breaking gameplay.
      if (_valid(total)) capture._metrics = total;
    } on Object {
      // Accounting cannot replace an operation's original result or exception.
    }
  }

  static bool _valid(AuthorityExecutionMetrics value) => <int>[
    value.retryCount,
    value.conflictCount,
    value.firestoreReadCount,
    value.firestoreWriteCount,
    value.bytesRead,
    value.bytesWritten,
  ].every((count) => count >= 0);
}
