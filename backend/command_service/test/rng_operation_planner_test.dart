import 'dart:convert';
import 'dart:io';

import 'package:board_backend_api/backend_api.dart';
import 'package:board_command_service/command_service.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  final fixture = _loadFixture('tv-27-durable-dice-draw');

  test('TV-27 shared durable fixture is produced by canonical Dart RNG', () {
    final plan = _evaluateFixture(fixture);
    final expected = fixture['expectedPlan']! as Map<String, Object?>;

    expect(plan.rngVersion, fixture['rngVersion']);
    expect(plan.values, expected['values']);
    expect(plan.candidatesConsumed, expected['candidatesConsumed']);
    expect(<String, int>{
      for (final entry in plan.successorCounters.entries)
        entry.key.label: entry.value,
    }, expected['successorCounters']);
  });

  test('TV-27 callback retry from identical private input is stable', () {
    final firstAttempt = _evaluateFixture(fixture);
    final retriedCallback = _evaluateFixture(fixture);

    expect(retriedCallback.values, firstAttempt.values);
    expect(retriedCallback.successorCounters, firstAttempt.successorCounters);
    expect(retriedCallback.candidatesConsumed, firstAttempt.candidatesConsumed);
  });

  test('shared command identity uses canonical semantic fingerprint v1', () {
    final operation = fixture['operation']! as Map<String, Object?>;
    final semanticMaterial = <String, Object?>{
      'v': 1,
      'family': 'game',
      'type': 'RandomDraw',
      'target': operation['gameId'],
      'expectedVersion': operation['expectedStateVersion'],
      'actorPlayerId': operation['actorPlayerId'],
      'payload': <String, Object?>{
        'stream': operation['stream'],
        'upperBounds': operation['upperBounds'],
      },
    };

    expect(operation['inputHashVersion'], SemanticFingerprintV1.version);
    expect(
      SemanticFingerprintV1.canonicalJson(semanticMaterial),
      '{"actorPlayerId":"p1","expectedVersion":12,"family":"game",'
      '"payload":{"stream":"dice","upperBounds":[6,6]},'
      '"target":"game-rng-tv27","type":"RandomDraw","v":1}',
    );
    expect(SemanticFingerprintV1.sha256Hex(semanticMaterial), hasLength(64));
  });

  test('unsupported version and empty operation fail before persistence', () {
    final privateInput = fixture['privateInput']! as Map<String, Object?>;
    final counters = _parseCounters(
      privateInput['streamCounters']! as Map<String, Object?>,
    );

    expect(
      () => AuthorityRngOperationPlanner.evaluate(
        privateSnapshot: AuthorityPrivateRngSnapshot(
          rngVersion: 'unsupported',
          seed: (privateInput['seedBytes']! as List<Object?>).cast<int>(),
          streamCounters: counters,
        ),
        draws: const <AuthorityRandomDraw>[
          AuthorityRandomDraw(stream: RngStream.dice, upperBound: 6),
        ],
      ),
      throwsA(isA<RngContractViolation>()),
    );

    expect(
      () => AuthorityRngOperationPlanner.evaluate(
        privateSnapshot: AuthorityPrivateRngSnapshot(
          rngVersion: canonicalRngVersion,
          seed: (privateInput['seedBytes']! as List<Object?>).cast<int>(),
          streamCounters: counters,
        ),
        draws: const <AuthorityRandomDraw>[],
      ),
      throwsA(isA<RngContractViolation>()),
    );
  });
}

AuthorityRandomOperationPlan _evaluateFixture(Map<String, Object?> fixture) {
  final privateInput = fixture['privateInput']! as Map<String, Object?>;
  final operation = fixture['operation']! as Map<String, Object?>;
  final stream = RngStream.parse(operation['stream']! as String);

  return AuthorityRngOperationPlanner.evaluate(
    privateSnapshot: AuthorityPrivateRngSnapshot(
      rngVersion: fixture['rngVersion']! as String,
      seed: (privateInput['seedBytes']! as List<Object?>).cast<int>(),
      streamCounters: _parseCounters(
        privateInput['streamCounters']! as Map<String, Object?>,
      ),
    ),
    draws: <AuthorityRandomDraw>[
      for (final upperBound
          in (operation['upperBounds']! as List<Object?>).cast<int>())
        AuthorityRandomDraw(stream: stream, upperBound: upperBound),
    ],
  );
}

Map<RngStream, int> _parseCounters(Map<String, Object?> counters) =>
    <RngStream, int>{
      for (final entry in counters.entries)
        RngStream.parse(entry.key): entry.value! as int,
    };

Map<String, Object?> _loadFixture(String id) {
  final decoded = jsonDecode(
    File('test/fixtures/rng_operation_plans.json').readAsStringSync(),
  ) as List<Object?>;
  return decoded.cast<Map<String, Object?>>().singleWhere(
    (candidate) => candidate['id'] == id,
  );
}
