import 'package:board_mobile/infrastructure/mobile_authority_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'explicit configuration preserves the Authority and Firebase values',
    () {
      final config = MobileAuthorityConfiguration(
        authorityBaseUri: Uri.parse('https://authority.example.test'),
        firebaseApiKey: 'api-key',
        firebaseAppId: 'app-id',
        firebaseMessagingSenderId: 'sender-id',
        firebaseProjectId: 'project-id',
        presetId: 'express',
        firebaseAuthEmulator: const FirebaseAuthEmulator(
          host: '127.0.0.1',
          port: 9099,
        ),
      );

      expect(config.authorityBaseUri.scheme, 'https');
      expect(config.firebaseProjectId, 'project-id');
      expect(config.presetId, 'express');
      expect(config.firebaseAuthEmulator?.port, 9099);
    },
  );
}
