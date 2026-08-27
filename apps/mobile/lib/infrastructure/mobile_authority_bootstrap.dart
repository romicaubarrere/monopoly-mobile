import 'package:board_backend_api/backend_api.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

final class MobileAuthorityBootstrap {
  const MobileAuthorityBootstrap._();

  static const _clientInstanceKey = 'la_vuelta.authority.v1.client-instance';

  static Future<FirstPlayableAuthorityClient> fromEnvironment() async {
    final config = MobileAuthorityConfiguration.fromEnvironment();
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: config.firebaseApiKey,
        appId: config.firebaseAppId,
        messagingSenderId: config.firebaseMessagingSenderId,
        projectId: config.firebaseProjectId,
      ),
    );

    final auth = FirebaseAuth.instance;
    final emulator = config.firebaseAuthEmulator;
    if (emulator != null) {
      await auth.useAuthEmulator(emulator.host, emulator.port);
    }
    await _ensureAnonymousIdentity(auth);

    final preferences = await SharedPreferences.getInstance();
    final clientInstanceId = await _clientInstanceId(preferences);
    final storage = FirstPlayableAuthorityDeviceStorage(
      read: (key) async => preferences.getString(key),
      write: (key, value) async {
        final persisted = value == null
            ? await preferences.remove(key)
            : await preferences.setString(key, value);
        if (!persisted) throw StateError('deviceStorageWriteRejected');
      },
    );

    final client = FirstPlayableAuthorityClient.httpWithDeviceStorage(
      baseUri: config.authorityBaseUri,
      idTokenProvider: () => _idToken(auth),
      deviceStorage: storage,
      commandIds: const _UuidCommandIdSource(),
      clientInstanceId: clientInstanceId,
      presetId: config.presetId,
    );
    await client.restore();
    return client;
  }

  static Future<void> _ensureAnonymousIdentity(FirebaseAuth auth) async {
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
    if (auth.currentUser == null) {
      throw StateError('firebaseIdentityUnavailable');
    }
  }

  static Future<String> _idToken(FirebaseAuth auth) async {
    await _ensureAnonymousIdentity(auth);
    final token = await auth.currentUser!.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('firebaseIdTokenUnavailable');
    }
    return token;
  }

  static Future<String> _clientInstanceId(SharedPreferences preferences) async {
    final existing = preferences.getString(_clientInstanceKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    if (!await preferences.setString(_clientInstanceKey, created)) {
      throw StateError('clientInstancePersistenceRejected');
    }
    return created;
  }
}

final class MobileAuthorityConfiguration {
  const MobileAuthorityConfiguration({
    required this.authorityBaseUri,
    required this.firebaseApiKey,
    required this.firebaseAppId,
    required this.firebaseMessagingSenderId,
    required this.firebaseProjectId,
    required this.presetId,
    this.firebaseAuthEmulator,
  });

  factory MobileAuthorityConfiguration.fromEnvironment() {
    const authorityOrigin = String.fromEnvironment('AUTHORITY_BASE_URL');
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
    const presetId = String.fromEnvironment('FIRST_PLAYABLE_PRESET_ID');
    const emulatorHost = String.fromEnvironment('FIREBASE_AUTH_EMULATOR_HOST');
    const emulatorPort = int.fromEnvironment(
      'FIREBASE_AUTH_EMULATOR_PORT',
      defaultValue: 0,
    );

    final baseUri = Uri.tryParse(authorityOrigin);
    if (baseUri == null || !baseUri.hasScheme || !baseUri.hasAuthority) {
      throw const FormatException('invalidAuthorityBaseUrl');
    }
    for (final entry in <String, String>{
      'FIREBASE_API_KEY': apiKey,
      'FIREBASE_APP_ID': appId,
      'FIREBASE_MESSAGING_SENDER_ID': senderId,
      'FIREBASE_PROJECT_ID': projectId,
      'FIRST_PLAYABLE_PRESET_ID': presetId,
    }.entries) {
      if (entry.value.trim().isEmpty) {
        throw FormatException('missing${entry.key}');
      }
    }
    final hasEmulatorHost = emulatorHost.isNotEmpty;
    final hasEmulatorPort = emulatorPort > 0 && emulatorPort <= 65535;
    if (hasEmulatorHost != hasEmulatorPort) {
      throw const FormatException('invalidFirebaseAuthEmulator');
    }

    return MobileAuthorityConfiguration(
      authorityBaseUri: baseUri,
      firebaseApiKey: apiKey,
      firebaseAppId: appId,
      firebaseMessagingSenderId: senderId,
      firebaseProjectId: projectId,
      presetId: presetId,
      firebaseAuthEmulator: hasEmulatorHost
          ? FirebaseAuthEmulator(host: emulatorHost, port: emulatorPort)
          : null,
    );
  }

  final Uri authorityBaseUri;
  final String firebaseApiKey;
  final String firebaseAppId;
  final String firebaseMessagingSenderId;
  final String firebaseProjectId;
  final String presetId;
  final FirebaseAuthEmulator? firebaseAuthEmulator;
}

final class FirebaseAuthEmulator {
  const FirebaseAuthEmulator({required this.host, required this.port});

  final String host;
  final int port;
}

final class _UuidCommandIdSource implements AuthorityCommandIdSource {
  const _UuidCommandIdSource();

  @override
  String nextCommandId() => const Uuid().v4();
}
