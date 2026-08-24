import 'dart:convert';
import 'dart:io';

Never _fail(String message) {
  stderr.writeln('spec-drift: $message');
  exit(1);
}

void main(List<String> args) {
  final file = File(args.isEmpty ? 'docs/specification_registry.json' : args.first);
  if (!file.existsSync()) _fail('registry not found: ${file.path}');

  final root = jsonDecode(file.readAsStringSync());
  if (root is! Map<String, dynamic>) _fail('registry root must be an object');
  if (root['schemaVersion'] != 1) _fail('unsupported schemaVersion');
  if (root['manifest'] != 'M1 Specification Manifest & Evidence Registry v1.2') {
    _fail('manifest drift: expected v1.2');
  }

  _checkCanonicalSources(root['canonicalSources']);
  _checkRanges(root['idRanges']);
  _checkAssignments(root['immutableAssignments']);
  _checkOperationalClaims(root['operationalClaims']);
  _checkContentFixture(root['contentFixture']);

  stdout.writeln('Specification registry drift guard: PASS');
}

void _checkCanonicalSources(Object? value) {
  if (value is! Map<String, dynamic>) _fail('canonicalSources missing');
  const expected = <String, String>{
    'product': 'Monopoly — Product Master Plan v0.4',
    'gameplay': 'Game Rules v1.1 — M1-aligned',
    'rulesCatalog': 'M1 RulesCatalog & PresetConfig Specification v0.1',
    'domain': 'M1 Domain Contracts & State Machine v0.7',
    'persistence': 'M1 Persistence & Authority Data Model v0.7',
    'rng': 'M1 Deterministic RNG Contract & Known-Answer Vectors v0.2',
    'quality': 'Quality & Test Strategy — Juego mobile v1.0',
    'nfr': 'NFRs & SLOs — Juego mobile v1.0',
    'traceability': 'MVP Traceability Matrix v1.2',
    'roadmap': 'Roadmap & Milestones — Monopoly v0.9',
    'risk': 'Risk Register — Monopoly v1.0',
    'decisions': 'Decision Log — Juego mobile DEC-001..065',
  };
  for (final entry in expected.entries) {
    if (value[entry.key] != entry.value) {
      _fail('canonical source drift for ${entry.key}: ${value[entry.key]}');
    }
  }
}

void _checkRanges(Object? value) {
  if (value is! Map<String, dynamic>) _fail('idRanges missing');
  const expected = <String, List<int>>{
    'TV': [1, 41],
    'NFR': [1, 46],
    'R': [1, 40],
    'ADR': [1, 10],
    'DEC': [1, 65],
  };
  for (final entry in expected.entries) {
    final range = value[entry.key];
    if (range is! Map<String, dynamic> ||
        range['min'] != entry.value[0] ||
        range['max'] != entry.value[1]) {
      _fail('${entry.key} registry range drift/reuse risk');
    }
  }
}

void _checkAssignments(Object? value) {
  if (value is! Map<String, dynamic>) _fail('immutableAssignments missing');
  const required = <String, String>{
    'DEC-064': 'lazy authoritative deadline resolution + member wake-up / ADR-010',
    'DEC-065': 'approved content intent; exact payload recovery remains separate',
    'TV-35': 'canonical semantic fingerprint exact hash',
    'TV-39': 'duplicate command semantics',
    'TV-40': 'room-code logical expiry',
    'TV-41': 'room-code concurrent reclaim',
  };
  final seenMeanings = <String, String>{};
  for (final entry in value.entries) {
    final meaning = entry.value?.toString() ?? '';
    final prior = seenMeanings[meaning];
    if (meaning.isEmpty) _fail('empty immutable assignment: ${entry.key}');
    if (prior != null) _fail('reused immutable meaning: $prior and ${entry.key}');
    seenMeanings[meaning] = entry.key;
  }
  for (final entry in required.entries) {
    if (value[entry.key] != entry.value) _fail('immutable assignment drift: ${entry.key}');
  }
}

void _checkOperationalClaims(Object? value) {
  if (value is! Map<String, dynamic>) _fail('operationalClaims missing');
  const expected = <String, String>{
    'repository': 'materialized',
    'githubAppWrite': 'available',
    'm0Exit': 'green',
    'm1Foundation': 'in_progress',
    'branchProtection': 'off',
  };
  for (final entry in expected.entries) {
    if (value[entry.key] != entry.value) {
      _fail('stale operational blocker/current-state drift: ${entry.key}');
    }
  }
}

void _checkContentFixture(Object? value) {
  if (value is! Map<String, dynamic>) _fail('contentFixture missing');
  if (value['decision'] != 'DEC-065') _fail('content fixture must be bound to DEC-065');
  if (value['status'] != 'partial') {
    _fail('DEC-065 fixture cannot be promoted without exact provenance');
  }
  if (value['exactPayloadChecksum'] != null) {
    _fail('partial DEC-065 fixture must not claim an exact checksum');
  }
  final missing = value['missing'];
  if (missing is! List || missing.length != 4) {
    _fail('DEC-065 missing provenance set changed; review canon before promotion');
  }
}
