import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:board_command_service/command_service.dart';
import 'package:board_command_service/observability/authority_observability.dart';
import 'package:board_game_core/game_core.dart';

import '../test/support/synthetic_roll_fixture.dart';

Future<void> main() async {
  final environment = Platform.environment;
  final projectId =
      environment['GCLOUD_PROJECT'] ?? environment['FIREBASE_PROJECT_ID'];
  if (projectId == null || !projectId.startsWith('demo-')) {
    throw const FormatException('emulatorProjectMustBeDemo');
  }
  final firestoreHost = environment['FIRESTORE_EMULATOR_HOST'];
  if (firestoreHost == null || firestoreHost.isEmpty) {
    throw const FormatException('firestoreEmulatorHostMissing');
  }
  final listenHost = environment['AUTHORITY_EMULATOR_HOST'] ?? '127.0.0.1';
  final listenPort = _environmentInt(
    environment,
    'AUTHORITY_EMULATOR_PORT',
    fallback: 8787,
    minimum: 1,
    maximum: 65535,
  );
  final roomCodeTtlSeconds = _environmentInt(
    environment,
    'FIRST_PLAYABLE_ROOM_CODE_TTL_SECONDS',
    fallback: 1800,
    minimum: 60,
    maximum: 86400,
  );
  final catalog = syntheticRollCatalog();
  final runtime = FirstPlayableAuthorityRuntime.withEnvironmentMaterials(
    identityVerifier: FirebaseAuthEmulatorIdentityVerifier.fromEnvironment(
      projectId: projectId,
      environment: environment,
    ),
    store: FirstPlayableFirestoreRestStore(
      config: FirstPlayableFirestoreRestConfig.emulator(
        projectId: projectId,
        host: firestoreHost,
      ),
    ),
    rulesCatalogRepository: PinnedFirstPlayableRulesCatalogRepository(
      activeRulesVersion: catalog.rulesVersion,
      catalogs: <RulesCatalog>[catalog],
    ),
    observability: BestEffortAuthorityObservability(_JsonLineLogSink()),
    roomCodeTtl: Duration(seconds: roomCodeTtlSeconds),
    environment: environment,
  );
  final server = await FirstPlayableAuthorityServer.bind(
    runtime: runtime,
    host: listenHost,
    port: listenPort,
  );
  stdout.writeln(
    jsonEncode(<String, Object>{
      'event': 'firstPlayableAuthorityEmulatorListening',
      'origin': server.baseUri.toString(),
      'projectId': projectId,
      'rulesVersion': catalog.rulesVersion,
      'presetIds': catalog.presets
          .map((preset) => preset.presetId)
          .toList(growable: false),
    }),
  );

  await Future.any<void>(<Future<void>>[
    ProcessSignal.sigint.watch().first.then((_) {}),
    ProcessSignal.sigterm.watch().first.then((_) {}),
  ]);
  await server.close(force: true);
}

int _environmentInt(
  Map<String, String> environment,
  String name, {
  required int fallback,
  required int minimum,
  required int maximum,
}) {
  final raw = environment[name];
  final value = raw == null ? fallback : int.tryParse(raw);
  if (value == null || value < minimum || value > maximum) {
    throw FormatException('invalidEnvironmentInteger:$name');
  }
  return value;
}

final class _JsonLineLogSink implements AuthorityLogSink {
  @override
  void write(Map<String, Object> fields) {
    stdout.writeln(
      jsonEncode(<String, Object>{'event': 'authority', ...fields}),
    );
  }
}
