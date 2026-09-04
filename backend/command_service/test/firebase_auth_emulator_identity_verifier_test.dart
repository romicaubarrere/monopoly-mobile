import 'dart:convert';

import 'package:board_command_service/security/firebase_identity_verifier.dart';
import 'package:test/test.dart';

void main() {
  test(
    'accepts only an unsigned token from the configured demo boundary',
    () async {
      final verifier = FirebaseAuthEmulatorIdentityVerifier.fromEnvironment(
        projectId: 'demo-board-game-local',
        environment: const <String, String>{
          'FIREBASE_AUTH_EMULATOR_HOST': '127.0.0.1:9099',
        },
        now: () => DateTime.utc(2026, 8, 27, 1, 30),
      );

      final identity = await verifier.verify(_token());

      expect(identity.uid, 'emulator-uid-1');
      expect(identity.authTime, DateTime.utc(2026, 8, 27, 1, 29));
    },
  );

  test('permits only explicit numeric IPv4 or IPv6 loopback hosts', () {
    for (final host in const <String>['127.0.0.1:9099', '[::1]:9099']) {
      expect(
        () => FirebaseAuthEmulatorIdentityVerifier(
          projectId: 'demo-board-game-local',
          emulatorHost: host,
        ),
        returnsNormally,
      );
    }

    for (final host in const <String>[
      '10.0.0.2:9099',
      'auth.example.com:9099',
      'localhost:9099',
      'http://127.0.0.1:9099',
      '127.0.0.1',
      '127.0.0.1:9099/path',
    ]) {
      expect(
        () => FirebaseAuthEmulatorIdentityVerifier(
          projectId: 'demo-board-game-local',
          emulatorHost: host,
        ),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('cannot be enabled for a resource-backed project or missing host', () {
    expect(
      () => FirebaseAuthEmulatorIdentityVerifier(
        projectId: 'production-project',
        emulatorHost: '127.0.0.1:9099',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'firebaseAuthEmulatorProjectMustBeDemo',
        ),
      ),
    );
    expect(
      () => FirebaseAuthEmulatorIdentityVerifier.fromEnvironment(
        projectId: 'demo-board-game-local',
        environment: const <String, String>{},
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'firebaseAuthEmulatorHostMissing',
        ),
      ),
    );
  });

  test('rejects signed, keyed, mismatched and expired tokens', () async {
    final verifier = FirebaseAuthEmulatorIdentityVerifier(
      projectId: 'demo-board-game-local',
      emulatorHost: '127.0.0.1:9099',
      now: () => DateTime.utc(2026, 8, 27, 1, 30),
    );

    await _expectIdentityFailure(
      verifier.verify(_token(algorithm: 'RS256', signature: 'signed')),
      'malformed_token',
    );
    await _expectIdentityFailure(
      verifier.verify(_token(kid: 'production-kid')),
      'unexpected_kid',
    );
    await _expectIdentityFailure(
      verifier.verify(_token(audience: 'other-project')),
      'invalid_audience',
    );
    await _expectIdentityFailure(
      verifier.verify(_token(expiresAt: DateTime.utc(2026, 8, 27, 1, 30))),
      'expired_token',
    );
  });
}

Future<void> _expectIdentityFailure(Future<Object?> future, String code) =>
    expectLater(
      future,
      throwsA(
        isA<IdentityVerificationException>().having(
          (error) => error.code,
          'code',
          code,
        ),
      ),
    );

String _token({
  String algorithm = 'none',
  String signature = '',
  String? kid,
  String audience = 'demo-board-game-local',
  DateTime? expiresAt,
}) {
  String encode(Map<String, Object?> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final header = <String, Object?>{'alg': algorithm, 'typ': 'JWT'};
  if (kid != null) header['kid'] = kid;
  final issuedAt = DateTime.utc(2026, 8, 27, 1, 29);
  final issuerProject = 'demo-board-game-local';
  return '${encode(header)}.'
      '${encode(<String, Object?>{'aud': audience, 'iss': 'https://securetoken.google.com/$issuerProject', 'exp': (expiresAt ?? DateTime.utc(2026, 8, 27, 2, 30)).millisecondsSinceEpoch ~/ 1000, 'iat': issuedAt.millisecondsSinceEpoch ~/ 1000, 'auth_time': issuedAt.millisecondsSinceEpoch ~/ 1000, 'sub': 'emulator-uid-1'})}.'
      '$signature';
}
