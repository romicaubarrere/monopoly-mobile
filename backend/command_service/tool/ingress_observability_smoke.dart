import 'package:board_command_service/ingress/command_ingress.dart';
import 'package:board_command_service/observability/authority_observability.dart';

final class _CollectingSink implements AuthorityLogSink {
  final events = <Map<String, Object>>[];

  @override
  void write(Map<String, Object> fields) => events.add(fields);
}

Future<void> main() async {
  final sink = _CollectingSink();
  final observability = BestEffortAuthorityObservability(sink);

  final ticks = <DateTime>[
    DateTime.utc(2026, 8, 24, 1, 0, 0),
    DateTime.utc(2026, 8, 24, 1, 0, 0, 100),
    DateTime.utc(2026, 8, 24, 1, 0, 0, 145),
  ];
  var index = 0;

  final ingress = CommandIngress(
    observability: observability,
    now: () => ticks[index++],
  );

  DateTime? receivedAt;
  final result = await ingress.handle<String>(
    command: const IngressCommandEnvelope(
      kind: IngressCommandKind.game,
      commandId: 'synthetic-command-id',
      inputHashVersion: 1,
      expectedVersion: 7,
    ),
    execute: (context, command) async {
      receivedAt = context.requestReceivedAt;
      return const AuthorityExecutionResult<String>(
        value: 'ok',
        outcome: AuthorityOutcome.success,
        reason: AuthorityReason.none,
        metrics: AuthorityExecutionMetrics(
          retryCount: 2,
          conflictCount: 1,
          firestoreReadCount: 3,
          firestoreWriteCount: 2,
          bytesRead: 512,
          bytesWritten: 256,
          snapshotBytes: 1024,
          schemaVersion: 1,
          stateVersion: 8,
          coldStart: false,
        ),
      );
    },
  );

  if (result != 'ok') throw StateError('unexpected result');
  if (receivedAt != DateTime.utc(2026, 8, 24, 1, 0, 0)) {
    throw StateError('requestReceivedAt was not captured exactly at ingress');
  }
  if (sink.events.length != 1) throw StateError('expected one log event');

  final event = sink.events.single;
  if (event['operation'] != 'gameCommand' ||
      event['outcome'] != 'success' ||
      event['latencyMs'] != 45 ||
      event['retryCount'] != 2 ||
      event['conflictCount'] != 1 ||
      event['stateVersion'] != 8) {
    throw StateError('unexpected authority observability fields: $event');
  }

  const forbiddenKeys = <String>{
    'commandId',
    'roomCode',
    'uid',
    'playerId',
    'token',
    'authorization',
    'seed',
    'rngCounter',
    'futureDeck',
    'payload',
  };
  if (event.keys.any(forbiddenKeys.contains)) {
    throw StateError('private or identifying field leaked: $event');
  }

  var rejectedInvalidHashVersion = false;
  try {
    await ingress.handle<void>(
      command: const IngressCommandEnvelope(
        kind: IngressCommandKind.room,
        commandId: 'synthetic-command-id-2',
        inputHashVersion: 2,
        expectedVersion: 0,
      ),
      execute: (context, command) async => const AuthorityExecutionResult<void>(
        value: null,
        outcome: AuthorityOutcome.success,
        reason: AuthorityReason.none,
      ),
    );
  } on ArgumentError {
    rejectedInvalidHashVersion = true;
  }
  if (!rejectedInvalidHashVersion) {
    throw StateError('non-canonical inputHashVersion was accepted');
  }

  print('Ingress observability: PASS');
}
