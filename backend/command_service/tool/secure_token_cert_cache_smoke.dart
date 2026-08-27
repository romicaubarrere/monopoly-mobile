import 'package:board_command_service/security/google_secure_token_certificates.dart';

Future<void> main() async {
  var now = DateTime.utc(2026, 8, 24, 2, 30);
  var calls = 0;
  final responses = <CertificateFetchResponse>[
    const CertificateFetchResponse(
      statusCode: 200,
      headers: <String, String>{'Cache-Control': 'public, max-age=60'},
      body: '{"kid-a":"synthetic-cert-a"}',
    ),
    const CertificateFetchResponse(
      statusCode: 200,
      headers: <String, String>{'cache-control': 'max-age=120, public'},
      body: '{"kid-a":"synthetic-cert-a2","kid-b":"synthetic-cert-b"}',
    ),
    const CertificateFetchResponse(
      statusCode: 200,
      headers: <String, String>{'Cache-Control': 'max-age=30'},
      body: '{"kid-a":"synthetic-cert-a3"}',
    ),
  ];

  final cache = GoogleSecureTokenCertificateCache(
    fetch: () async {
      final response = responses[calls];
      calls += 1;
      return response;
    },
    now: () => now,
  );

  _expect(
    await cache.certificateForKid('kid-a') == 'synthetic-cert-a',
    'first fetch mismatch',
  );
  _expect(calls == 1, 'first lookup must fetch once');

  _expect(
    await cache.certificateForKid('kid-a') == 'synthetic-cert-a',
    'fresh cache mismatch',
  );
  _expect(calls == 1, 'fresh lookup must not refetch');

  await _expectFailure(cache.certificateForKid('kid-b'), 'unknown_kid');
  _expect(calls == 1, 'unknown kid must not force a fresh-cache refetch');

  now = now.add(const Duration(seconds: 121));
  _expect(
    await cache.certificateForKid('kid-a') == 'synthetic-cert-a2',
    'expired cache refresh mismatch',
  );
  _expect(calls == 2, 'expired cache must refetch');

  await _expectFailure(
    GoogleSecureTokenCertificateCache(
      fetch: () async => const CertificateFetchResponse(
        statusCode: 200,
        headers: <String, String>{'Cache-Control': 'public'},
        body: '{"kid-a":"synthetic-cert"}',
      ),
    ).certificateForKid('kid-a'),
    'invalid_cache_max_age',
  );

  await _expectFailure(
    GoogleSecureTokenCertificateCache(
      fetch: () async => const CertificateFetchResponse(
        statusCode: 503,
        headers: <String, String>{'Cache-Control': 'max-age=60'},
        body: 'untrusted-body',
      ),
    ).certificateForKid('kid-a'),
    'certificate_fetch_failed',
  );
}

Future<void> _expectFailure(Future<String> future, String code) async {
  try {
    await future;
  } on SecureTokenCertificateException catch (error) {
    _expect(error.code == code, 'expected $code, got ${error.code}');
    return;
  }
  throw StateError('expected certificate failure: $code');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
