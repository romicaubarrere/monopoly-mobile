import 'dart:async';

import 'package:board_command_service/ingress/command_ingress.dart';
import 'package:board_command_service/observability/authority_observability.dart';
import 'package:test/test.dart';

void main() {
  group('AuthorityExecutionMetricsCapture', () {
    test('aggregates only the six measured additive counters', () async {
      final capture = AuthorityExecutionMetricsCapture();
      final value = await capture.run(() async {
        AuthorityExecutionMetricsCapture.record(
          const AuthorityExecutionMetrics(
            retryCount: 1,
            conflictCount: 2,
            firestoreReadCount: 3,
            firestoreWriteCount: 4,
            bytesRead: 5,
            bytesWritten: 6,
            schemaVersion: 7,
            stateVersion: 8,
            snapshotBytes: 9,
            coldStart: true,
          ),
        );
        await Future<void>.value();
        AuthorityExecutionMetricsCapture.record(
          const AuthorityExecutionMetrics(
            retryCount: 10,
            conflictCount: 20,
            firestoreReadCount: 30,
            firestoreWriteCount: 40,
            bytesRead: 50,
            bytesWritten: 60,
          ),
        );
        return 'unchanged-result';
      });

      expect(value, 'unchanged-result');
      expect(_counts(capture.metrics), <int>[11, 22, 33, 44, 55, 66]);
      _expectUnmeasuredDefaults(capture.metrics);
    });

    test('record outside a capture is a no-op', () async {
      final capture = AuthorityExecutionMetricsCapture();
      AuthorityExecutionMetricsCapture.record(_metrics(100));
      expect(_counts(capture.metrics), everyElement(0));
      await capture.run(() async {
        AuthorityExecutionMetricsCapture.record(_metrics(1));
      });
      AuthorityExecutionMetricsCapture.record(_metrics(200));
      expect(_counts(capture.metrics), everyElement(1));
    });

    test('metrics getters return immutable point-in-time values', () async {
      final capture = AuthorityExecutionMetricsCapture();
      final before = capture.metrics;
      late AuthorityExecutionMetrics during;
      await capture.run(() async {
        AuthorityExecutionMetricsCapture.record(_metrics(1));
        during = capture.metrics;
        await Future<void>.value();
        AuthorityExecutionMetricsCapture.record(_metrics(2));
      });

      expect(_counts(before), everyElement(0));
      expect(_counts(during), everyElement(1));
      expect(_counts(capture.metrics), everyElement(3));
    });

    test('interleaved asynchronous captures do not share counters', () async {
      final first = AuthorityExecutionMetricsCapture();
      final second = AuthorityExecutionMetricsCapture();
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      await Future.wait(<Future<void>>[
        first.run(() async {
          AuthorityExecutionMetricsCapture.record(_metrics(1));
          firstStarted.complete();
          await releaseFirst.future;
          AuthorityExecutionMetricsCapture.record(_metrics(2));
        }),
        second.run(() async {
          await firstStarted.future;
          AuthorityExecutionMetricsCapture.record(_metrics(10));
          releaseFirst.complete();
          await Future<void>.value();
          AuthorityExecutionMetricsCapture.record(_metrics(20));
        }),
      ]);

      expect(_counts(first.metrics), everyElement(3));
      expect(_counts(second.metrics), everyElement(30));
    });

    test('nested captures shadow and then restore the parent', () async {
      final parent = AuthorityExecutionMetricsCapture();
      final child = AuthorityExecutionMetricsCapture();
      await parent.run(() async {
        AuthorityExecutionMetricsCapture.record(_metrics(1));
        await child.run(() async {
          AuthorityExecutionMetricsCapture.record(_metrics(10));
          await Future<void>.value();
          AuthorityExecutionMetricsCapture.record(_metrics(20));
        });
        AuthorityExecutionMetricsCapture.record(_metrics(2));
      });

      expect(_counts(parent.metrics), everyElement(3));
      expect(_counts(child.metrics), everyElement(30));
    });

    test(
      'sealed child callbacks do not fall through to active parent',
      () async {
        final parent = AuthorityExecutionMetricsCapture();
        final child = AuthorityExecutionMetricsCapture();
        final release = Completer<void>();
        late Future<void> lateRecord;
        await parent.run(() async {
          AuthorityExecutionMetricsCapture.record(_metrics(1));
          await child.run(() async {
            AuthorityExecutionMetricsCapture.record(_metrics(10));
            lateRecord = () async {
              await release.future;
              AuthorityExecutionMetricsCapture.record(_metrics(100));
            }();
          });
          release.complete();
          await lateRecord;
          AuthorityExecutionMetricsCapture.record(_metrics(2));
        });

        expect(_counts(parent.metrics), everyElement(3));
        expect(_counts(child.metrics), everyElement(10));
      },
    );

    for (final fail in <bool>[false, true]) {
      test(
        'late records are sealed after ${fail ? 'failure' : 'success'}',
        () async {
          final capture = AuthorityExecutionMetricsCapture();
          final next = AuthorityExecutionMetricsCapture();
          final release = Completer<void>();
          final original = StateError('original execution error');
          late Future<void> lateRecord;
          final execution = capture.run<void>(() async {
            AuthorityExecutionMetricsCapture.record(_metrics(1));
            lateRecord = () async {
              await release.future;
              AuthorityExecutionMetricsCapture.record(_metrics(100));
            }();
            if (fail) throw original;
          });
          if (fail) {
            expect((await _failureOf(execution)).$1, same(original));
          } else {
            await execution;
          }
          final sealed = capture.metrics;
          await next.run(() async {
            AuthorityExecutionMetricsCapture.record(_metrics(2));
            release.complete();
            await lateRecord;
          });

          expect(_counts(sealed), everyElement(1));
          expect(_counts(capture.metrics), everyElement(1));
          expect(_counts(next.metrics), everyElement(2));
        },
      );
    }

    for (final asynchronous in <bool>[false, true]) {
      test(
        'preserves ${asynchronous ? 'async' : 'sync'} error identity and stack',
        () async {
          final capture = AuthorityExecutionMetricsCapture();
          final original = StateError('private original execution error');
          final originalStack = StackTrace.fromString(
            'original-execution-stack',
          );
          Future<void> execute() {
            AuthorityExecutionMetricsCapture.record(_metrics(3));
            if (asynchronous) {
              return Future<void>(() {
                Error.throwWithStackTrace(original, originalStack);
              });
            }
            Error.throwWithStackTrace(original, originalStack);
          }

          final (error, stack) = await _failureOf(capture.run(execute));
          expect(error, same(original));
          expect(stack.toString(), originalStack.toString());
          expect(_counts(capture.metrics), everyElement(3));
        },
      );
    }

    for (var negativeIndex = 0; negativeIndex < 6; negativeIndex += 1) {
      test('ignores a snapshot with negative counter $negativeIndex', () async {
        final capture = AuthorityExecutionMetricsCapture();
        final fields = List<int>.filled(6, 100)..[negativeIndex] = -1;
        await capture.run(() async {
          AuthorityExecutionMetricsCapture.record(_metrics(2));
          AuthorityExecutionMetricsCapture.record(
            AuthorityExecutionMetrics(
              retryCount: fields[0],
              conflictCount: fields[1],
              firestoreReadCount: fields[2],
              firestoreWriteCount: fields[3],
              bytesRead: fields[4],
              bytesWritten: fields[5],
            ),
          );
          AuthorityExecutionMetricsCapture.record(_metrics(3));
        });

        expect(_counts(capture.metrics), everyElement(5));
      });
    }

    test('ignored provenance fields cannot poison valid counters', () async {
      final capture = AuthorityExecutionMetricsCapture();
      await capture.run(() async {
        AuthorityExecutionMetricsCapture.record(
          const AuthorityExecutionMetrics(
            firestoreReadCount: 3,
            schemaVersion: -1,
            stateVersion: -1,
            snapshotBytes: -1,
            coldStart: true,
          ),
        );
      });

      expect(_counts(capture.metrics), <int>[0, 0, 3, 0, 0, 0]);
      _expectUnmeasuredDefaults(capture.metrics);
    });

    test(
      'overflowing aggregate is ignored without discarding prior evidence',
      () async {
        final capture = AuthorityExecutionMetricsCapture();
        const maximum = 0x7fffffffffffffff;
        await capture.run(() async {
          AuthorityExecutionMetricsCapture.record(_metrics(maximum));
          AuthorityExecutionMetricsCapture.record(_metrics(1));
        });
        expect(_counts(capture.metrics), everyElement(maximum));
      },
    );

    test('a sealed capture cannot execute a second callback', () async {
      final capture = AuthorityExecutionMetricsCapture();
      await capture.run(() async {
        AuthorityExecutionMetricsCapture.record(_metrics(1));
      });
      var reran = false;
      await expectLater(
        capture.run(() async {
          reran = true;
          AuthorityExecutionMetricsCapture.record(_metrics(100));
        }),
        throwsStateError,
      );

      expect(reran, isFalse);
      expect(_counts(capture.metrics), everyElement(1));
    });

    test(
      'an active capture cannot execute a concurrent second callback',
      () async {
        final capture = AuthorityExecutionMetricsCapture();
        final started = Completer<void>();
        final release = Completer<void>();
        final first = capture.run(() async {
          AuthorityExecutionMetricsCapture.record(_metrics(1));
          started.complete();
          await release.future;
          AuthorityExecutionMetricsCapture.record(_metrics(2));
        });
        await started.future;
        var reran = false;
        try {
          await expectLater(
            capture.run(() async {
              reran = true;
              AuthorityExecutionMetricsCapture.record(_metrics(100));
            }),
            throwsStateError,
          );
        } finally {
          release.complete();
          await first;
        }

        expect(reran, isFalse);
        expect(_counts(capture.metrics), everyElement(3));
      },
    );
  });

  group('CommandIngress captured failure metrics', () {
    test(
      'successful result metrics remain authoritative without double counts',
      () async {
        final sink = _Sink();
        final ingress = _ingress(sink);
        final value = await ingress.handle<String>(
          command: _command,
          execute: (_, _) async {
            AuthorityExecutionMetricsCapture.record(_metrics(100));
            return const AuthorityExecutionResult(
              value: 'accepted-value',
              outcome: AuthorityOutcome.success,
              reason: AuthorityReason.none,
              metrics: AuthorityExecutionMetrics(
                retryCount: 1,
                conflictCount: 2,
                firestoreReadCount: 3,
                firestoreWriteCount: 4,
                bytesRead: 5,
                bytesWritten: 6,
                snapshotBytes: 7,
                schemaVersion: 8,
                stateVersion: 9,
                coldStart: true,
              ),
            );
          },
        );

        expect(value, 'accepted-value');
        expect(sink.events, hasLength(1));
        final event = sink.events.single;
        expect(_eventCounts(event), <int>[1, 2, 3, 4, 5, 6]);
        expect(event['outcome'], 'success');
        expect(event['snapshotBytes'], 7);
        expect(event['schemaVersion'], 8);
        expect(event['stateVersion'], 9);
        expect(event['coldStart'], isTrue);
      },
    );

    for (final asynchronous in <bool>[false, true]) {
      test(
        'logs measured ${asynchronous ? 'async' : 'sync'} failure and rethrows unchanged',
        () async {
          final sink = _Sink();
          final original = StateError('private execution failure');
          final originalStack = StackTrace.fromString('original-ingress-stack');
          final execution = _ingress(sink).handle<void>(
            command: _command,
            execute: (_, _) {
              AuthorityExecutionMetricsCapture.record(_metrics(3));
              if (asynchronous) {
                return Future<AuthorityExecutionResult<void>>(() {
                  Error.throwWithStackTrace(original, originalStack);
                });
              }
              Error.throwWithStackTrace(original, originalStack);
            },
          );

          final (error, stack) = await _failureOf(execution);
          expect(error, same(original));
          expect(stack.toString(), originalStack.toString());
          expect(sink.events, hasLength(1));
          final event = sink.events.single;
          expect(_eventCounts(event), everyElement(3));
          expect(event['outcome'], 'internalFailure');
          expect(event['reason'], 'internalError');
          expect(event.keys, unorderedEquals(_failureFields));
          expect(event.values, isNot(contains(original.toString())));
        },
      );
    }

    test('uninstrumented failures retain the existing zero fallback', () async {
      final sink = _Sink();
      final original = StateError('uninstrumented failure');
      final (error, _) = await _failureOf(
        _ingress(sink).handle<void>(
          command: _command,
          execute: (_, _) async => throw original,
        ),
      );

      expect(error, same(original));
      expect(sink.events, hasLength(1));
      expect(_eventCounts(sink.events.single), everyElement(0));
      expect(sink.events.single.keys, unorderedEquals(_failureFields));
    });

    test(
      'failure-event clock error cannot replace the original exception',
      () async {
        final sink = _Sink();
        var clockCalls = 0;
        final ingress = CommandIngress(
          observability: BestEffortAuthorityObservability(sink),
          now: () {
            clockCalls += 1;
            if (clockCalls == 2) throw StateError('diagnostic clock failed');
            return DateTime.utc(2026);
          },
        );
        final original = StateError('original operation failed');
        final (error, _) = await _failureOf(
          ingress.handle<void>(
            ingressContext: IngressContext(
              requestReceivedAt: DateTime.utc(2026),
            ),
            command: _command,
            execute: (_, _) async => throw original,
          ),
        );
        expect(error, same(original));
        expect(sink.events, isEmpty);
      },
    );

    test('reusing an IngressContext does not reuse metric captures', () async {
      final sink = _Sink();
      final ingress = _ingress(sink);
      final context = IngressContext(requestReceivedAt: DateTime.utc(2026));
      for (final count in <int>[2, 5]) {
        final original = StateError('request $count');
        final (error, _) = await _failureOf(
          ingress.handle<void>(
            command: _command,
            ingressContext: context,
            execute: (received, _) async {
              expect(received, same(context));
              AuthorityExecutionMetricsCapture.record(_metrics(count));
              throw original;
            },
          ),
        );
        expect(error, same(original));
      }

      expect(sink.events, hasLength(2));
      expect(_eventCounts(sink.events[0]), everyElement(2));
      expect(_eventCounts(sink.events[1]), everyElement(5));
    });

    test(
      'throwing sink cannot replace either success or original failure',
      () async {
        final ingress = _ingress(_ThrowingSink());
        final value = await ingress.handle<String>(
          command: _command,
          execute: (_, _) async {
            AuthorityExecutionMetricsCapture.record(_metrics(3));
            return const AuthorityExecutionResult(
              value: 'safe-success',
              outcome: AuthorityOutcome.success,
              reason: AuthorityReason.none,
            );
          },
        );
        expect(value, 'safe-success');

        final original = StateError('original failure');
        final originalStack = StackTrace.fromString('original-sink-test-stack');
        final (error, stack) = await _failureOf(
          ingress.handle<void>(
            command: _command,
            execute: (_, _) async {
              AuthorityExecutionMetricsCapture.record(_metrics(4));
              Error.throwWithStackTrace(original, originalStack);
            },
          ),
        );
        expect(error, same(original));
        expect(stack.toString(), originalStack.toString());
      },
    );
  });
}

AuthorityExecutionMetrics _metrics(int count) => AuthorityExecutionMetrics(
  retryCount: count,
  conflictCount: count,
  firestoreReadCount: count,
  firestoreWriteCount: count,
  bytesRead: count,
  bytesWritten: count,
);

List<int> _counts(AuthorityExecutionMetrics metrics) => <int>[
  metrics.retryCount,
  metrics.conflictCount,
  metrics.firestoreReadCount,
  metrics.firestoreWriteCount,
  metrics.bytesRead,
  metrics.bytesWritten,
];

List<Object?> _eventCounts(Map<String, Object> event) => <Object?>[
  event['retryCount'],
  event['conflictCount'],
  event['firestoreReadCount'],
  event['firestoreWriteCount'],
  event['bytesRead'],
  event['bytesWritten'],
];

void _expectUnmeasuredDefaults(AuthorityExecutionMetrics metrics) {
  expect(metrics.schemaVersion, isNull);
  expect(metrics.stateVersion, isNull);
  expect(metrics.snapshotBytes, 0);
  expect(metrics.coldStart, isFalse);
}

Future<(Object, StackTrace)> _failureOf(Future<void> future) async {
  try {
    await future;
  } on Object catch (error, stack) {
    return (error, stack);
  }
  fail('Expected the original execution failure.');
}

CommandIngress _ingress(AuthorityLogSink sink) => CommandIngress(
  observability: BestEffortAuthorityObservability(sink),
  now: () => DateTime.utc(2026),
);

const _command = IngressCommandEnvelope(
  kind: IngressCommandKind.game,
  commandId: 'cmd-capture',
  inputHashVersion: 1,
  expectedVersion: 0,
);

const _failureFields = <String>[
  'operation',
  'outcome',
  'reason',
  'latencyMs',
  'retryCount',
  'conflictCount',
  'firestoreReadCount',
  'firestoreWriteCount',
  'bytesRead',
  'bytesWritten',
  'snapshotBytes',
  'coldStart',
];

final class _Sink implements AuthorityLogSink {
  final events = <Map<String, Object>>[];

  @override
  void write(Map<String, Object> fields) => events.add(fields);
}

final class _ThrowingSink implements AuthorityLogSink {
  @override
  void write(Map<String, Object> fields) =>
      throw StateError('sink unavailable');
}
