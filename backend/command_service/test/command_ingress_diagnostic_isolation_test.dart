import 'dart:async';

import 'package:board_command_service/ingress/command_ingress.dart';
import 'package:board_command_service/observability/authority_observability.dart';
import 'package:test/test.dart';

void main() {
  group('CommandIngress diagnostic isolation', () {
    for (final kind in IngressCommandKind.values) {
      for (final disposition in _dispositions.take(3)) {
        for (final failingTick in <int>[1, 2]) {
          test(
            '${kind.name} ${disposition.$1.name} survives diagnostic tick $failingTick',
            () async {
              final sink = _Sink();
              final clock = _Clock(failingTick: failingTick);
              final ingress = _ingress(sink, clock.now);
              final context = IngressContext(requestReceivedAt: _authorityTime);
              final command = _command(kind);
              final value = Object();
              var executions = 0;
              final returned = await ingress.handle<Object>(
                command: command,
                ingressContext: context,
                execute: (received, envelope) async {
                  executions += 1;
                  expect(received, same(context));
                  expect(received.requestReceivedAt, _authorityTime);
                  expect(envelope, same(command));
                  AuthorityExecutionMetricsCapture.record(_counts(100));
                  return AuthorityExecutionResult(
                    value: value,
                    outcome: disposition.$1,
                    reason: disposition.$2,
                    metrics: _resultMetrics,
                  );
                },
              );

              expect(returned, same(value));
              expect(executions, 1);
              expect(clock.calls, failingTick);
              expect(sink.attempts, 0);
              expect(sink.events, isEmpty);
            },
          );
        }
      }

      test(
        '${kind.name} requires its missing authoritative timestamp',
        () async {
          final sink = _Sink();
          final clock = _Clock(failingTick: 1);
          var executions = 0;
          final (error, stack) = await _failureOf(
            _ingress(sink, clock.now).handle<Object>(
              command: _command(kind),
              execute: (_, _) async {
                executions += 1;
                return _result(Object());
              },
            ),
          );

          expect(error, same(clock.error));
          expect(stack.toString(), clock.stack.toString());
          expect(executions, 0);
          expect(clock.calls, 1);
          expect(sink.attempts, 0);
        },
      );

      test(
        '${kind.name} keeps captured authority time when diagnostic start fails',
        () async {
          final sink = _Sink();
          final authorityTime = DateTime(2026, 9, 8, 12, 34, 56);
          final clock = _Clock(failingTick: 2, firstTick: authorityTime);
          final value = Object();
          var executions = 0;
          final returned = await _ingress(sink, clock.now).handle<Object>(
            command: _command(kind),
            execute: (context, _) async {
              executions += 1;
              expect(context.requestReceivedAt, authorityTime.toUtc());
              expect(context.requestReceivedAt.isUtc, isTrue);
              return _result(value);
            },
          );

          expect(returned, same(value));
          expect(executions, 1);
          expect(clock.calls, 2);
          expect(sink.attempts, 0);
        },
      );

      test(
        '${kind.name} captures authority time before separate latency',
        () async {
          final sink = _Sink();
          final authorityTime = DateTime(2026, 9, 8, 12, 34, 56);
          final ticks = <DateTime>[
            authorityTime,
            authorityTime.add(const Duration(milliseconds: 100)),
            authorityTime.add(const Duration(milliseconds: 145)),
          ];
          var clockCalls = 0;
          var executions = 0;
          final value = Object();
          final returned = await _ingress(sink, () => ticks[clockCalls++])
              .handle<Object>(
                command: _command(kind),
                execute: (context, _) async {
                  executions += 1;
                  expect(context.requestReceivedAt, authorityTime.toUtc());
                  expect(context.requestReceivedAt.isUtc, isTrue);
                  return _result(value);
                },
              );

          expect(returned, same(value));
          expect(executions, 1);
          expect(clockCalls, 3);
          expect(sink.attempts, 1);
          expect(sink.events.single['latencyMs'], 45);
          expect(sink.events.single['operation'], '${kind.name}Command');
        },
      );
    }

    for (final disposition in _dispositions) {
      test(
        '${disposition.$1.name} preserves returned metrics and allowlist',
        () async {
          final sink = _Sink();
          final clock = _Clock();
          final context = IngressContext(requestReceivedAt: _authorityTime);
          final value = Object();
          final returned = await _ingress(sink, clock.now).handle<Object>(
            command: _command(IngressCommandKind.game),
            ingressContext: context,
            execute: (received, _) async {
              expect(received, same(context));
              AuthorityExecutionMetricsCapture.record(_counts(100));
              return AuthorityExecutionResult(
                value: value,
                outcome: disposition.$1,
                reason: disposition.$2,
                metrics: _resultMetrics,
              );
            },
          );

          expect(returned, same(value));
          expect(clock.calls, 2);
          expect(sink.attempts, 1);
          expect(sink.events.single, <String, Object>{
            'operation': 'gameCommand',
            'outcome': disposition.$1.name,
            'reason': disposition.$2.name,
            'latencyMs': 20,
            'retryCount': 1,
            'conflictCount': 2,
            'firestoreReadCount': 3,
            'firestoreWriteCount': 4,
            'bytesRead': 5,
            'bytesWritten': 6,
            'snapshotBytes': 7,
            'schemaVersion': 8,
            'stateVersion': 9,
            'coldStart': true,
          });
        },
      );
    }

    for (var field = 0; field < _numericFields.length; field += 1) {
      test(
        'invalid returned ${_numericFields[field]} only omits the event',
        () async {
          final sink = _Sink();
          final clock = _Clock();
          final value = Object();
          var executions = 0;
          final returned = await _ingress(sink, clock.now).handle<Object>(
            command: _command(IngressCommandKind.game),
            ingressContext: IngressContext(requestReceivedAt: _authorityTime),
            execute: (_, _) async {
              executions += 1;
              AuthorityExecutionMetricsCapture.record(_counts(100));
              return _result(value, metrics: _invalidMetrics(field));
            },
          );

          expect(returned, same(value));
          expect(executions, 1);
          expect(clock.calls, 2);
          expect(sink.attempts, 0);
          expect(sink.events, isEmpty);
        },
      );
    }

    for (final asynchronous in <bool>[false, true]) {
      for (final failingTick in <int?>[null, 1, 2]) {
        test(
          '${asynchronous ? 'async' : 'sync'} error and stack survive diagnostic tick $failingTick',
          () async {
            final sink = _Sink();
            final clock = _Clock(failingTick: failingTick);
            final original = StateError('private executor error');
            final originalStack = StackTrace.fromString(
              'private executor stack',
            );
            var executions = 0;
            final (error, stack) = await _failureOf(
              _ingress(sink, clock.now).handle<Object>(
                command: _command(IngressCommandKind.room),
                ingressContext: IngressContext(
                  requestReceivedAt: _authorityTime,
                ),
                execute: (_, _) {
                  executions += 1;
                  AuthorityExecutionMetricsCapture.record(_counts(3));
                  if (asynchronous) {
                    return Future<AuthorityExecutionResult<Object>>(() {
                      AuthorityExecutionMetricsCapture.record(_counts(4));
                      Error.throwWithStackTrace(original, originalStack);
                    });
                  }
                  Error.throwWithStackTrace(original, originalStack);
                },
              ),
            );

            expect(error, same(original));
            expect(stack.toString(), originalStack.toString());
            expect(executions, 1);
            expect(clock.calls, failingTick ?? 2);
            expect(sink.attempts, failingTick == null ? 1 : 0);
            if (failingTick == null) {
              expect(sink.events.single, _failureEvent(asynchronous ? 7 : 3));
            } else {
              expect(sink.events, isEmpty);
            }
          },
        );
      }
    }

    for (final fails in <bool>[false, true]) {
      test(
        'throwing sink preserves ${fails ? 'error' : 'result'} without retry',
        () async {
          final sink = _Sink(throwsOnWrite: true);
          final clock = _Clock();
          final value = Object();
          final original = StateError('private original error');
          final originalStack = StackTrace.fromString('private original stack');
          var executions = 0;
          final future = _ingress(sink, clock.now).handle<Object>(
            command: _command(IngressCommandKind.room),
            ingressContext: IngressContext(requestReceivedAt: _authorityTime),
            execute: (_, _) async {
              executions += 1;
              AuthorityExecutionMetricsCapture.record(_counts(3));
              if (fails) Error.throwWithStackTrace(original, originalStack);
              return _result(value);
            },
          );

          if (fails) {
            final (error, stack) = await _failureOf(future);
            expect(error, same(original));
            expect(stack.toString(), originalStack.toString());
            expect(sink.events.single, _failureEvent(3));
          } else {
            expect(await future, same(value));
            expect(sink.events.single['outcome'], 'success');
            expect(sink.events.single['firestoreReadCount'], 3);
            expect(sink.events.single['snapshotBytes'], 7);
          }
          expect(executions, 1);
          expect(clock.calls, 2);
          expect(sink.attempts, 1);
        },
      );

      test(
        'backward diagnostic time clamps ${fails ? 'failure' : 'success'} latency',
        () async {
          final sink = _Sink();
          var clockCalls = 0;
          final ingress = _ingress(sink, () {
            clockCalls += 1;
            return _authorityTime.subtract(
              Duration(milliseconds: clockCalls * 20),
            );
          });
          final value = Object();
          final original = StateError('original error');
          final future = ingress.handle<Object>(
            command: _command(IngressCommandKind.game),
            ingressContext: IngressContext(requestReceivedAt: _authorityTime),
            execute: (_, _) async {
              if (fails) throw original;
              return _result(value);
            },
          );

          if (fails) {
            expect((await _failureOf(future)).$1, same(original));
          } else {
            expect(await future, same(value));
          }
          expect(clockCalls, 2);
          expect(sink.attempts, 1);
          expect(sink.events.single['latencyMs'], 0);
        },
      );
    }

    for (final invalid in <(String, IngressCommandEnvelope)>[
      (
        'commandId',
        const IngressCommandEnvelope(
          kind: IngressCommandKind.game,
          commandId: '',
          inputHashVersion: 1,
          expectedVersion: 0,
        ),
      ),
      (
        'inputHashVersion',
        const IngressCommandEnvelope(
          kind: IngressCommandKind.room,
          commandId: 'synthetic-command',
          inputHashVersion: 2,
          expectedVersion: 0,
        ),
      ),
      (
        'expectedVersion',
        const IngressCommandEnvelope(
          kind: IngressCommandKind.game,
          commandId: 'synthetic-command',
          inputHashVersion: 1,
          expectedVersion: -1,
        ),
      ),
    ]) {
      test(
        'invalid ${invalid.$1} still fails before clocks and execution',
        () async {
          final sink = _Sink();
          final clock = _Clock(failingTick: 1);
          var executions = 0;
          final (error, _) = await _failureOf(
            _ingress(sink, clock.now).handle<Object>(
              command: invalid.$2,
              execute: (_, _) async {
                executions += 1;
                return _result(Object());
              },
            ),
          );

          expect(
            error,
            isA<ArgumentError>().having((e) => e.name, 'name', invalid.$1),
          );
          expect(executions, 0);
          expect(clock.calls, 0);
          expect(sink.attempts, 0);
        },
      );
    }

    test('interleaved diagnostic failure cannot suppress another request event', () async {
      final sink = _Sink();
      final clock = _Clock(failingTick: 1);
      final ingress = _ingress(sink, clock.now);
      final context = IngressContext(requestReceivedAt: _authorityTime);
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final firstValue = Object();
      final secondError = StateError('second executor failure');
      final first = ingress.handle<Object>(
        command: _command(IngressCommandKind.game),
        ingressContext: context,
        execute: (received, _) async {
          expect(received, same(context));
          AuthorityExecutionMetricsCapture.record(_counts(100));
          firstStarted.complete();
          await releaseFirst.future;
          return _result(firstValue);
        },
      );
      // Race the signal against completion so the pre-fix failure is reported,
      // not hidden behind a hanging barrier or an unhandled future error.
      await Future.any<void>(<Future<void>>[
        firstStarted.future,
        first.then<void>((_) {}),
      ]);
      try {
        final (error, _) = await _failureOf(
          ingress.handle<Object>(
            command: _command(IngressCommandKind.room),
            ingressContext: context,
            execute: (received, _) async {
              expect(received, same(context));
              AuthorityExecutionMetricsCapture.record(_counts(2));
              throw secondError;
            },
          ),
        );
        expect(error, same(secondError));
      } finally {
        releaseFirst.complete();
      }

      expect(await first, same(firstValue));
      expect(clock.calls, 3);
      expect(sink.attempts, 1);
      expect(sink.events.single, _failureEvent(2));
    });
  });
}

final _authorityTime = DateTime.utc(2026, 9, 8, 12);

const _dispositions = <(AuthorityOutcome, AuthorityReason)>[
  (AuthorityOutcome.success, AuthorityReason.none),
  (AuthorityOutcome.rejected, AuthorityReason.decisionClosed),
  (AuthorityOutcome.duplicate, AuthorityReason.duplicateCommand),
  (AuthorityOutcome.collision, AuthorityReason.commandIdCollision),
  (AuthorityOutcome.stale, AuthorityReason.staleVersion),
  (AuthorityOutcome.retryableFailure, AuthorityReason.retryableConflict),
  (AuthorityOutcome.internalFailure, AuthorityReason.internalError),
];

const _resultMetrics = AuthorityExecutionMetrics(
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
);

const _numericFields = <String>[
  'retryCount',
  'conflictCount',
  'firestoreReadCount',
  'firestoreWriteCount',
  'bytesRead',
  'bytesWritten',
  'snapshotBytes',
  'schemaVersion',
  'stateVersion',
];

AuthorityExecutionMetrics _invalidMetrics(int field) {
  final values = List<int>.generate(9, (index) => index + 1)..[field] = -1;
  return AuthorityExecutionMetrics(
    retryCount: values[0],
    conflictCount: values[1],
    firestoreReadCount: values[2],
    firestoreWriteCount: values[3],
    bytesRead: values[4],
    bytesWritten: values[5],
    snapshotBytes: values[6],
    schemaVersion: values[7],
    stateVersion: values[8],
  );
}

AuthorityExecutionMetrics _counts(int count) => AuthorityExecutionMetrics(
  retryCount: count,
  conflictCount: count,
  firestoreReadCount: count,
  firestoreWriteCount: count,
  bytesRead: count,
  bytesWritten: count,
);

AuthorityExecutionResult<Object> _result(
  Object value, {
  AuthorityExecutionMetrics metrics = _resultMetrics,
}) => AuthorityExecutionResult(
  value: value,
  outcome: AuthorityOutcome.success,
  reason: AuthorityReason.none,
  metrics: metrics,
);

IngressCommandEnvelope _command(IngressCommandKind kind) =>
    IngressCommandEnvelope(
      kind: kind,
      commandId: 'synthetic-command',
      inputHashVersion: 1,
      expectedVersion: 0,
    );

CommandIngress _ingress(AuthorityLogSink sink, DateTime Function() now) =>
    CommandIngress(
      observability: BestEffortAuthorityObservability(sink),
      now: now,
    );

Map<String, Object> _failureEvent(int count) => <String, Object>{
  'operation': 'roomCommand',
  'outcome': 'internalFailure',
  'reason': 'internalError',
  'latencyMs': 20,
  for (final field in _numericFields.take(6)) field: count,
  'snapshotBytes': 0,
  'coldStart': false,
};

Future<(Object, StackTrace)> _failureOf(Future<Object> future) async {
  try {
    await future;
  } on Object catch (error, stack) {
    return (error, stack);
  }
  fail('Expected original operation failure.');
}

final class _Clock {
  _Clock({this.failingTick, this.firstTick});

  final int? failingTick;
  final DateTime? firstTick;
  final error = StateError('private clock error');
  final stack = StackTrace.fromString('private clock stack');
  var calls = 0;

  DateTime now() {
    calls += 1;
    if (calls == failingTick) Error.throwWithStackTrace(error, stack);
    if (calls == 1 && firstTick != null) return firstTick!;
    return _authorityTime.add(Duration(milliseconds: calls * 20));
  }
}

final class _Sink implements AuthorityLogSink {
  _Sink({this.throwsOnWrite = false});

  final bool throwsOnWrite;
  final events = <Map<String, Object>>[];
  var attempts = 0;

  @override
  void write(Map<String, Object> fields) {
    attempts += 1;
    events.add(Map<String, Object>.of(fields));
    if (throwsOnWrite) throw StateError('private sink failure');
  }
}
