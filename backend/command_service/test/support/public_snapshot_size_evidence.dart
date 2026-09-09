import 'dart:convert';

import 'package:board_backend_api/backend_api.dart';
import 'package:board_game_core/game_core.dart';
import 'package:crypto/crypto.dart';

// Curated full public snapshots, not a recursive search through fixtures that
// also contain private sentinels, commands and partial result projections.
const publicSnapshotFixturePaths = <String, List<String>>{
  'bankruptcy_plans.json': <String>[
    'declareA.initialState',
    'declareA.stateAfter',
    'declareB.initialState',
    'declareB.stateAfter',
    'deadline.initialState',
    'deadline.stateAfter',
  ],
  'tax_free_parking_plans.json': <String>[
    'tax.initialState',
    'tax.plans.a.stateAfter',
    'tax.plans.b.stateAfter',
    'debt.initialState',
    'debt.plans.a.stateAfter',
    'collection.initialState',
    'collection.plans.a.stateAfter',
    'collection.plans.b.stateAfter',
    'zeroCollection.initialState',
    'zeroCollection.plans.a.stateAfter',
  ],
};

/// Offline fixture evidence only; never imported by the Authority runtime.
///
/// Existing generator-equality tests establish these are complete Engine
/// snapshots. AuthorityPublicSnapshot validates protocol metadata and the
/// recursive privacy boundary; it is not a replacement for domain validation.
Map<String, Object?> publicSnapshotSizeEvidence(Map<String, Object?> fixtures) {
  final snapshots = <Map<String, Object?>>[];
  for (final fixture in publicSnapshotFixturePaths.entries) {
    for (final path in fixture.value) {
      Object? value = fixtures[fixture.key];
      for (final segment in path.split('.')) {
        value = _object(value, fixture.key, path)[segment];
      }
      final snapshot = AuthorityPublicSnapshot(
        _object(value, fixture.key, path),
      );
      // Measure the same sorted, integer-only compact JSON as PublicGameState,
      // excluding fixture indentation, envelopes, sentinels and report bytes.
      final bytes = utf8.encode(CanonicalDomainJson.encode(snapshot.snapshot));
      snapshots.add(<String, Object?>{
        'fixture': fixture.key,
        'snapshotPath': path,
        'serializedSnapshotBytes': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      });
    }
  }
  return <String, Object?>{
    'formatVersion': 1,
    'evidenceKind': 'synthetic-public-snapshot-fixtures',
    'serialization': 'CanonicalDomainJson/UTF-8',
    'snapshots': snapshots,
  };
}

Map<String, Object?> _object(Object? value, String fixture, String path) {
  if (value is Map<String, Object?>) return value;
  // Only curated identifiers are included; never echo the invalid value.
  throw FormatException('Missing or non-object fixture path: $fixture:$path');
}
