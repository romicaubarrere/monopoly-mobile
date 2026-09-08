import 'dart:convert';
import 'dart:io';

import 'package:board_backend_api/backend_api.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'support/public_snapshot_size_evidence.dart';
import 'support/synthetic_bankruptcy_plans.dart';
import 'support/synthetic_tax_free_parking_plans.dart';

void main() {
  Map<String, Object?> loadFixtures() => <String, Object?>{
    for (final name in publicSnapshotFixturePaths.keys)
      name: jsonDecode(File('test/fixtures/$name').readAsStringSync()),
  };

  Map<String, Object?> firstSnapshot(Map<String, Object?> fixtures) =>
      ((fixtures['bankruptcy_plans.json']! as Map<String, Object?>)['declareA']!
              as Map<String, Object?>)['initialState']!
          as Map<String, Object?>;

  List<Map<String, Object?>> entries(Map<String, Object?> fixtures) =>
      (publicSnapshotSizeEvidence(fixtures)['snapshots']! as List<Object?>)
          .cast<Map<String, Object?>>();

  test(
    'committed report matches all 16 complete Engine-generated snapshots',
    () {
      final fixtures = loadFixtures();
      expect(
        fixtures['bankruptcy_plans.json'],
        syntheticBankruptcyFixtureJson(),
      );
      expect(
        fixtures['tax_free_parking_plans.json'],
        syntheticTaxFreeParkingFixtureJson(),
      );
      final report = publicSnapshotSizeEvidence(fixtures);
      expect(
        report,
        jsonDecode(
          File('test/fixtures/public_snapshot_sizes.json').readAsStringSync(),
        ),
      );
      expect(report['evidenceKind'], 'synthetic-public-snapshot-fixtures');
      expect(report['serialization'], 'CanonicalDomainJson/UTF-8');
      expect(entries(fixtures), hasLength(16));
      expect(
        entries(fixtures)
            .map((entry) => '${entry['fixture']}:${entry['snapshotPath']}'),
        <String>[
          'bankruptcy_plans.json:declareA.initialState',
          'bankruptcy_plans.json:declareA.stateAfter',
          'bankruptcy_plans.json:declareB.initialState',
          'bankruptcy_plans.json:declareB.stateAfter',
          'bankruptcy_plans.json:deadline.initialState',
          'bankruptcy_plans.json:deadline.stateAfter',
          'tax_free_parking_plans.json:tax.initialState',
          'tax_free_parking_plans.json:tax.plans.a.stateAfter',
          'tax_free_parking_plans.json:tax.plans.b.stateAfter',
          'tax_free_parking_plans.json:debt.initialState',
          'tax_free_parking_plans.json:debt.plans.a.stateAfter',
          'tax_free_parking_plans.json:collection.initialState',
          'tax_free_parking_plans.json:collection.plans.a.stateAfter',
          'tax_free_parking_plans.json:collection.plans.b.stateAfter',
          'tax_free_parking_plans.json:zeroCollection.initialState',
          'tax_free_parking_plans.json:zeroCollection.plans.a.stateAfter',
        ],
      );
    },
  );

  test('measures compact UTF-8 bytes and hashes exactly that public JSON', () {
    final fixtures = loadFixtures();
    final state = firstSnapshot(fixtures);
    final bank = state['bank']! as Map<String, Object?>;
    bank['currencyUnit'] = 'a';
    final ascii = entries(fixtures).first;
    bank['currencyUnit'] = 'é'; // Same code-unit length, one extra UTF-8 byte.
    final unicode = entries(fixtures).first;
    expect(
      unicode['serializedSnapshotBytes'],
      (ascii['serializedSnapshotBytes']! as int) + 1,
    );
    bank['currencyUnit'] = 'ñ🎲\n"';
    final measured = entries(fixtures).first;
    final expectedJson = syntheticBankruptcyPlans()['declareA']!.initialState
        .toCanonicalJson()
        .replaceFirst('synthetic-unit', r'ñ🎲\n\"');
    expect(jsonDecode(expectedJson), state);
    final bytes = utf8.encode(expectedJson);
    expect(measured['serializedSnapshotBytes'], bytes.length);
    expect(measured['sha256'], sha256.convert(bytes).toString());
    expect(bytes.length, greaterThan(expectedJson.length));
    expect(
      bytes.length,
      lessThan(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(state)).length,
      ),
    );
  });

  test('canonical key ordering is stable and the source stays unchanged', () {
    final fixtures = loadFixtures();
    final before = jsonEncode(fixtures);
    final expected = publicSnapshotSizeEvidence(fixtures);
    expect(jsonEncode(fixtures), before);
    Object? reverseKeys(Object? value) => switch (value) {
      final Map<String, Object?> map => <String, Object?>{
        for (final entry in map.entries.toList().reversed)
          entry.key: reverseKeys(entry.value),
      },
      final List<Object?> list => list.map(reverseKeys).toList(),
      _ => value,
    };
    expect(
      publicSnapshotSizeEvidence(
        reverseKeys(fixtures)! as Map<String, Object?>,
      ),
      expected,
    );
  });

  test(
    'content drift changes the hash even when the byte length is unchanged',
    () {
      final fixtures = loadFixtures();
      final before = entries(fixtures);
      (firstSnapshot(fixtures)['bank']!
              as Map<String, Object?>)['currencyUnit'] =
          'synthetic-UNIT';
      final after = entries(fixtures);
      expect(
        after.first['serializedSnapshotBytes'],
        before.first['serializedSnapshotBytes'],
      );
      expect(after.first['sha256'], isNot(before.first['sha256']));
      expect(after.skip(1), before.skip(1));
    },
  );

  test(
    'report contains metadata only and excludes unselected fixture material',
    () {
      final fixtures = loadFixtures();
      final expected = publicSnapshotSizeEvidence(fixtures);
      final bankruptcy =
          fixtures['bankruptcy_plans.json']! as Map<String, Object?>;
      bankruptcy['privateSentinel'] = <String, Object?>{
        'seed': 'private-test-marker',
      };
      bankruptcy['unselected'] = <String, Object?>{
        'initialState': <String, Object?>{'token': 'unselected-test-marker'},
      };
      fixtures['unselected.json'] = <String, Object?>{
        'seed': 'private-test-marker',
      };
      expect(publicSnapshotSizeEvidence(fixtures), expected);
      for (final entry in entries(fixtures)) {
        expect(
          entry.keys,
          unorderedEquals(<String>[
            'fixture',
            'snapshotPath',
            'serializedSnapshotBytes',
            'sha256',
          ]),
        );
        expect(entry['serializedSnapshotBytes'], isA<int>());
        expect(entry['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      }
      final encoded = jsonEncode(expected);
      for (final value in <String>[
        'private-test-marker',
        'unselected-test-marker',
        'authority-private-unchanged',
        'game-vp0',
        'room-vp0',
        'uid-p1',
        'synthetic-unit',
        'streamCounters',
      ]) {
        expect(encoded, isNot(contains(value)));
      }
    },
  );

  for (final key in <String>[
    'seed',
    'streamCounters',
    'memberUidByPlayerId',
    'token',
  ]) {
    test('existing recursive public guard rejects $key before reporting', () {
      final fixtures = loadFixtures();
      firstSnapshot(fixtures)['bank'] = <String, Object?>{
        'nested': <Object?>[
          <String, Object?>{key: 'private-test-marker'},
        ],
      };
      expect(
        () => publicSnapshotSizeEvidence(fixtures),
        throwsA(
          isA<ClientAuthorityContractViolation>().having(
            (error) => error.code,
            'code',
            'privateMaterialForbidden',
          ),
        ),
      );
    });
  }

  for (final invalid in <Object?>[null, 1, <Object?>[]]) {
    test('missing or non-object selected snapshot fails closed: $invalid', () {
      final fixtures = loadFixtures();
      final bankruptcy =
          fixtures['bankruptcy_plans.json']! as Map<String, Object?>;
      (bankruptcy['declareA']! as Map<String, Object?>)['initialState'] =
          invalid;
      expect(() => publicSnapshotSizeEvidence(fixtures), throwsFormatException);
    });
  }

  test(
    'missing source fixture or intermediate path cannot reduce the report',
    () {
      final fixtures = loadFixtures();
      fixtures.remove('bankruptcy_plans.json');
      expect(() => publicSnapshotSizeEvidence(fixtures), throwsFormatException);
      final nested = loadFixtures();
      (nested['tax_free_parking_plans.json']! as Map<String, Object?>).remove(
        'tax',
      );
      expect(() => publicSnapshotSizeEvidence(nested), throwsFormatException);
    },
  );

  for (final invalid in <(String, Object?, String)>[
    ('schemaVersion', 2, 'unsupportedSnapshotSchemaVersion'),
    ('stateVersion', -1, 'invalidSnapshotVersion'),
    ('gameId', '', 'invalidSnapshotGameId'),
    ('freeParkingPot', 0.5, 'invalidJsonMaterial'),
  ]) {
    test('existing snapshot validation rejects invalid ${invalid.$1}', () {
      final fixtures = loadFixtures();
      firstSnapshot(fixtures)[invalid.$1] = invalid.$2;
      expect(
        () => publicSnapshotSizeEvidence(fixtures),
        throwsA(
          isA<ClientAuthorityContractViolation>().having(
            (error) => error.code,
            'code',
            invalid.$3,
          ),
        ),
      );
    });
  }

  test('CLI prints the golden without changing fixture bytes', () async {
    final paths = <String>[
      ...publicSnapshotFixturePaths.keys,
      'public_snapshot_sizes.json',
    ];
    final before = <String, List<int>>{
      for (final path in paths)
        path: File('test/fixtures/$path').readAsBytesSync(),
    };
    final result = await Process.run(Platform.resolvedExecutable, <String>[
      'run',
      'tool/report_public_snapshot_sizes.dart',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stderr, isEmpty);
    expect(result.stdout, utf8.decode(before['public_snapshot_sizes.json']!));
    final fromRoot = await Process.run(Platform.resolvedExecutable, <String>[
      'run',
      'backend/command_service/tool/report_public_snapshot_sizes.dart',
    ], workingDirectory: Directory.current.parent.parent.path);
    expect(fromRoot.exitCode, 0, reason: fromRoot.stderr.toString());
    expect(fromRoot.stderr, isEmpty);
    expect(fromRoot.stdout, result.stdout);
    for (final path in paths) {
      expect(File('test/fixtures/$path').readAsBytesSync(), before[path]);
    }
  });

  test(
    'CLI rejects arguments without reading arbitrary paths or printing data',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        'tool/report_public_snapshot_sizes.dart',
        'not-a-fixture',
      ]);
      expect(result.exitCode, 64);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('Usage:'));
      expect(result.stderr, isNot(contains('not-a-fixture')));
    },
  );
}
