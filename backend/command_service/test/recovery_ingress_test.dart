import 'dart:async';

import 'package:board_command_service/ingress/command_ingress.dart';
import 'package:board_command_service/observability/authority_observability.dart';
import 'package:test/test.dart';

// Deliberately synthetic counters test orchestration, not Firestore cost.
const _first = AuthorityExecutionMetrics(
  retryCount: 1,
  conflictCount: 2,
  firestoreReadCount: 3,
  firestoreWriteCount: 4,
  bytesRead: 5,
  bytesWritten: 6,
  schemaVersion: 91,
  stateVersion: 92,
  snapshotBytes: 93,
  coldStart: true,
);
const _second = AuthorityExecutionMetrics(
  retryCount: 10,
  conflictCount: 20,
  firestoreReadCount: 30,
  firestoreWriteCount: 40,
  bytesRead: 50,
  bytesWritten: 60,
);

void main() {
  test(
    'success sums captured counters once and takes only validated versions',
    () async {
      final sink = _Sink();
      var now = DateTime.utc(2026, 9, 8);
      final ingress = _ingress(sink, now: () => now);
      final value = Object();
      final result = await ingress.handleRecovery(
        execute: () async {
          AuthorityExecutionMetricsCapture.record(_first);
          await Future<void>.value();
          AuthorityExecutionMetricsCapture.record(_second);
          now = now.add(const Duration(milliseconds: 37));
          return value;
        },
        versions: (_) => (schemaVersion: 1, stateVersion: 7),
      );

      expect(result, same(value));
      expect(sink.calls, 1);
      expect(sink.events.single, <String, Object>{
        'operation': 'recovery',
        'outcome': 'success',
        'reason': 'none',
        'latencyMs': 37,
        'retryCount': 11,
        'conflictCount': 22,
        'firestoreReadCount': 33,
        'firestoreWriteCount': 44,
        'bytesRead': 55,
        'bytesWritten': 66,
        'snapshotBytes': 0,
        'coldStart': false,
        'schemaVersion': 1,
        'stateVersion': 7,
      });
    },
  );

  test(
    'failure retains counters but no result versions, identity or raw error',
    () async {
      final sink = _Sink();
      final ingress = _ingress(sink);
      final original = StateError('private recovery error');
      final stack = StackTrace.fromString('original-recovery-stack');
      Object? caught;
      StackTrace? caughtStack;
      var versionCalls = 0;

      try {
        await ingress.handleRecovery<Object>(
          execute: () async {
            AuthorityExecutionMetricsCapture.record(_first);
            await Future<void>.value();
            Error.throwWithStackTrace(original, stack);
          },
          versions: (_) {
            versionCalls += 1;
            return (schemaVersion: 1, stateVersion: 7);
          },
        );
      } on Object catch (error, trace) {
        caught = error;
        caughtStack = trace;
      }

      expect(caught, same(original));
      expect(caughtStack.toString(), stack.toString());
      expect(versionCalls, 0);
      expect(sink.events.single, <String, Object>{
        'operation': 'recovery',
        'outcome': 'internalFailure',
        'reason': 'internalError',
        'latencyMs': 0,
        'retryCount': 1,
        'conflictCount': 2,
        'firestoreReadCount': 3,
        'firestoreWriteCount': 4,
        'bytesRead': 5,
        'bytesWritten': 6,
        'snapshotBytes': 0,
        'coldStart': false,
      });
    },
  );

  test(
    'unmeasured executor does not inherit a prior recovery or returned metrics',
    () async {
      final sink = _Sink();
      final ingress = _ingress(sink);
      await _run(ingress, () async {
        AuthorityExecutionMetricsCapture.record(_first);
        return Object();
      });
      final returned = AuthorityExecutionResult(
        value: Object(),
        outcome: AuthorityOutcome.rejected,
        reason: AuthorityReason.staleVersion,
        metrics: _first,
      );
      expect(await _run(ingress, () async => returned), same(returned));
      expect(sink.events, hasLength(2));
      expect(sink.events.last['firestoreReadCount'], 0);
      expect(sink.events.last['bytesRead'], 0);
      expect(sink.events.last['outcome'], 'success');
      expect(sink.events.last['reason'], 'none');
    },
  );

  for (final fails in [false, true]) {
    test(
      'throwing sink preserves ${fails ? 'error' : 'result'} exactly once',
      () async {
        final sink = _Sink(throwsOnWrite: true);
        final ingress = _ingress(sink);
        final original = StateError('synthetic original');
        final value = Object();
        final operation = _run(ingress, () async {
          AuthorityExecutionMetricsCapture.record(_first);
          if (fails) throw original;
          return value;
        });
        if (fails) {
          await expectLater(operation, throwsA(same(original)));
        } else {
          expect(await operation, same(value));
        }
        expect(sink.calls, 1);
      },
    );

    for (final throwAt in [1, 2]) {
      test(
        'clock failure $throwAt preserves ${fails ? 'error' : 'result'}',
        () async {
          final sink = _Sink();
          var clockCalls = 0;
          final ingress = _ingress(
            sink,
            now: () {
              if (++clockCalls == throwAt) throw StateError('diagnostic clock');
              return DateTime.utc(2026, 9, 8);
            },
          );
          final original = StateError('original execution');
          final value = Object();
          var executions = 0;
          final operation = _run(ingress, () async {
            executions += 1;
            AuthorityExecutionMetricsCapture.record(_first);
            if (fails) throw original;
            return value;
          });
          if (fails) {
            await expectLater(operation, throwsA(same(original)));
          } else {
            expect(await operation, same(value));
          }
          expect(executions, 1);
          expect(sink.calls, 0);
        },
      );
    }
  }

  test(
    'backwards diagnostic clock clamps elapsed time without changing result',
    () async {
      final sink = _Sink();
      var now = DateTime.utc(2026, 9, 8);
      final ingress = _ingress(sink, now: () => now);
      final value = Object();
      expect(
        await _run(ingress, () async {
          now = now.subtract(const Duration(seconds: 1));
          return value;
        }),
        same(value),
      );
      expect(sink.events.single['latencyMs'], 0);
    },
  );

  for (final badVersion in ['throw', 'negativeSchema', 'negativeState']) {
    test(
      'invalid diagnostic versions $badVersion never change success',
      () async {
        final sink = _Sink();
        final ingress = _ingress(sink);
        final value = Object();
        final result = await ingress.handleRecovery(
          execute: () async => value,
          versions: (_) => switch (badVersion) {
            'negativeSchema' => (schemaVersion: -1, stateVersion: 7),
            'negativeState' => (schemaVersion: 1, stateVersion: -1),
            _ => throw StateError('diagnostic version extraction'),
          },
        );
        expect(result, same(value));
        expect(sink.calls, 0);
      },
    );
  }

  test(
    'concurrent recoveries on one ingress never share captured counters',
    () async {
      final sink = _Sink();
      final ingress = _ingress(sink);
      final started = Completer<void>();
      final resume = Completer<void>();
      final first = _run(ingress, () async {
        AuthorityExecutionMetricsCapture.record(_first);
        started.complete();
        await resume.future;
        AuthorityExecutionMetricsCapture.record(_first);
        return 'first';
      });
      await started.future;
      expect(
        await _run(ingress, () async {
          AuthorityExecutionMetricsCapture.record(_second);
          return 'second';
        }),
        'second',
      );
      resume.complete();
      expect(await first, 'first');
      expect(sink.events, hasLength(2));
      expect(sink.events.map((e) => e['firestoreReadCount']), [30, 6]);
      expect(sink.events.map((e) => e['bytesRead']), [50, 10]);
    },
  );

  test('nested recovery records only its own operations', () async {
    final sink = _Sink();
    final ingress = _ingress(sink);
    await _run(ingress, () async {
      AuthorityExecutionMetricsCapture.record(_first);
      await _run(ingress, () async {
        AuthorityExecutionMetricsCapture.record(_second);
        return Object();
      });
      AuthorityExecutionMetricsCapture.record(_first);
      return Object();
    });
    expect(sink.events, hasLength(2));
    expect(sink.events.map((e) => e['firestoreReadCount']), [30, 6]);
  });

  test(
    'detached callbacks cannot alter emitted metrics or the next recovery',
    () async {
      final sink = _Sink();
      final ingress = _ingress(sink);
      final late = Completer<void>();
      late Future<void> callback;
      await _run(ingress, () async {
        AuthorityExecutionMetricsCapture.record(_first);
        callback = late.future.then((_) {
          AuthorityExecutionMetricsCapture.record(_second);
        });
        return Object();
      });
      await _run(ingress, () async {
        late.complete();
        await callback;
        return Object();
      });
      expect(sink.events, hasLength(2));
      expect(sink.events.map((e) => e['firestoreReadCount']), [3, 0]);
    },
  );
}

Future<T> _run<T>(CommandIngress ingress, Future<T> Function() execute) =>
    ingress.handleRecovery(
      execute: execute,
      versions: (_) => (schemaVersion: 1, stateVersion: 7),
    );

CommandIngress _ingress(_Sink sink, {DateTime Function()? now}) =>
    CommandIngress(
      observability: BestEffortAuthorityObservability(sink),
      now: now ?? () => DateTime.utc(2026, 9, 8),
    );

final class _Sink implements AuthorityLogSink {
  _Sink({this.throwsOnWrite = false});

  final bool throwsOnWrite;
  final events = <Map<String, Object>>[];
  int calls = 0;

  @override
  void write(Map<String, Object> fields) {
    calls += 1;
    if (throwsOnWrite) throw StateError('synthetic sink');
    events.add(fields);
  }
}
