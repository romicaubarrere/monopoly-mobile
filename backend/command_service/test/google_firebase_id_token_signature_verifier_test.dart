import 'dart:convert';
import 'dart:io';

import 'package:board_command_service/security/firebase_identity_verifier.dart';
import 'package:board_command_service/security/google_firebase_id_token_signature_verifier.dart';
import 'package:board_command_service/security/google_secure_token_certificates.dart';
import 'package:test/test.dart';

void main() {
  test(
    'verifies Firebase RS256 token and caches certificate by max-age',
    () async {
      var loadCount = 0;
      final signatureVerifier = GoogleFirebaseIdTokenSignatureVerifier(
        cache: GoogleSecureTokenCertificateCache(
          fetch: () async {
            loadCount += 1;
            return _certificateResponse;
          },
          now: () => DateTime.utc(2026, 8, 26, 12, 30),
        ),
      );
      final verifier = FirebaseIdentityVerifier(
        projectId: 'fixture-project',
        signatureVerifier: signatureVerifier,
        now: () => DateTime.utc(2026, 8, 26, 12, 30),
      );

      final first = await verifier.verify(_fixtureToken);
      final second = await verifier.verify(_fixtureToken);

      expect(first.uid, 'uid-fixture');
      expect(second.uid, 'uid-fixture');
      expect(loadCount, 1);
    },
  );

  test('concurrent cold lookups share one certificate fetch', () async {
    var loadCount = 0;
    final certificates = GoogleSecureTokenCertificateCache(
      fetch: () async {
        loadCount += 1;
        await Future<void>.delayed(Duration.zero);
        return _certificateResponse;
      },
      now: () => DateTime.utc(2026, 8, 26, 12, 30),
    );

    final results = await Future.wait(<Future<String>>[
      certificates.certificateForKid('fixture-kid'),
      certificates.certificateForKid('fixture-kid'),
    ]);

    expect(results, everyElement(_fixtureCertificate));
    expect(loadCount, 1);
  });

  test(
    'unknown key fails from valid cache without fetch amplification',
    () async {
      var loadCount = 0;
      final certificates = GoogleSecureTokenCertificateCache(
        fetch: () async {
          loadCount += 1;
          return _certificateResponse;
        },
        now: () => DateTime.utc(2026, 8, 26, 12, 30),
      );
      await certificates.certificateForKid('fixture-kid');

      await expectLater(
        certificates.certificateForKid('missing-kid'),
        throwsA(
          isA<SecureTokenCertificateException>().having(
            (error) => error.code,
            'code',
            'unknown_kid',
          ),
        ),
      );
      expect(loadCount, 1);
    },
  );

  test(
    'HTTP fetcher carries canonical cache headers and bounded JSON',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.set(
          HttpHeaders.cacheControlHeader,
          'public, max-age=3600',
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(_certificateResponse.body);
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
      final fetcher = GoogleSecureTokenCertificateHttpFetcher(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/certificates'),
      );

      final response = await fetcher.call();
      final cache = GoogleSecureTokenCertificateCache(
        fetch: () async => response,
        now: () => DateTime.utc(2026, 8, 26, 12, 30),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(await cache.certificateForKid('fixture-kid'), _fixtureCertificate);
    },
  );

  test('HTTP fetcher rejects plaintext non-loopback endpoints', () {
    expect(
      () => GoogleSecureTokenCertificateHttpFetcher(
        endpoint: Uri.parse('http://example.com/certificates'),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'firebaseCertificateEndpointMustUseHttps',
        ),
      ),
    );
  });
}

final _certificateResponse = CertificateFetchResponse(
  statusCode: HttpStatus.ok,
  headers: const <String, String>{'Cache-Control': 'public, max-age=3600'},
  body: jsonEncode(<String, String>{'fixture-kid': _fixtureCertificate}),
);

const _fixtureToken =
    'eyJraWQiOiJmaXh0dXJlLWtpZCIsImFsZyI6IlJTMjU2IiwidHlwIjoiSldUIn0.'
    'eyJhdWQiOiJmaXh0dXJlLXByb2plY3QiLCJpc3MiOiJodHRwczovL3NlY3VyZXRva2Vu'
    'Lmdvb2dsZS5jb20vZml4dHVyZS1wcm9qZWN0IiwiZXhwIjoxNzg3NzUyODAwLCJpYXQi'
    'OjE3ODc3NDU2MDAsImF1dGhfdGltZSI6MTc4Nzc0NTYwMCwic3ViIjoidWlkLWZpeHR1'
    'cmUifQ.'
    'wB3BsJN6gf6H_M8R_t4qR3aLV0N9yYQCkXeNzySgQldA0F3X4zE2et8xdBEl3g97k59R'
    'r602dxqa0sZH5T7cnWW-anyUnBqzwkUNCehWL7Yr4tRDFFh-f7lTlm4t-RN9Kay3KSGH'
    'yYSDQMMMHvUiuQjGMePVA17vOL7mo6y7w3XmHKWC3tvkE_QMGnaj7JooAmv39VXJm_aE'
    'XdDbOXmPYvGVbap5rLCUHq7Q20FRUBaCral6Cti15KQf8Dh9ljWuOZbypqGnVydEyHgH'
    'Ij8d_suhHdYBNSrptVVKaOLDhSunN2v_twLfaS-yvCx3_DsAS-A5PpPsWvbPMJ_say1Q'
    'vQ';

const _fixtureCertificate = '''-----BEGIN CERTIFICATE-----
MIIDMjCCAhoCCQD3O5GD6JcncDANBgkqhkiG9w0BAQsFADBbMQswCQYDVQQGEwJG
UjEWMBQGA1UECAwNSWxlLWRlLUZyYW5jZTEOMAwGA1UEBwwFUGFyaXMxJDAiBgkq
hkiG9w0BCQEWFWdvLmpyb3Vzc2VsQGdtYWlsLmNvbTAeFw0yMzA4MjMxODU3MTJa
Fw0yNDA4MjIxODU3MTJaMFsxCzAJBgNVBAYTAkZSMRYwFAYDVQQIDA1JbGUtZGUt
RnJhbmNlMQ4wDAYDVQQHDAVQYXJpczEkMCIGCSqGSIb3DQEJARYVZ28uanJvdXNz
ZWxAZ21haWwuY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAx69b
2rwfqWdHv9L6e38xJQ0k9E336wBry76OkFJp/AHczRhIsrVthnmBgTBBp4vyPPf0
untElrFamlyY6g5V6nn2VMz828n3fVEcGodL3BxSpPmzO2bLzsb5UYSmMMd8Gjcz
pXH3rZQeYaRQoh6LaFCS/bG1Y6AcjG7NwUD/O4A0kQH5IHTYcre90HuJsZVwaOwM
vt3USyWZlSHoCQ0NircZbINuZ2J/OH6TkB5c6FOATEikWb1X5SlG5SZZacFxEw7w
+dhZbyE3qNqnXk2nqwVJTllQGA99YSc3z1CMp7eC2e5OqH+95ZAR/d2TnFX2Hsgh
rbeHxjDSYiccYx5FZwIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQAAN08vxGGcZYKq
/5lPRUYr7+KzMr5wHQdEUluPVtMiYjpOeuP+vXtO+tgmabCJqlXGg/O0H/GhczGX
cGYEPye5ftjiRPYLjvAgHotJH2gnJ5w5y5bRYw3+r/JQkueEd617iHFNL2j0atxf
ULgfOfPXjLu+2Ch8c8z/J5u52H6xpXBNDRNCnfm2nqwMcsRXCitLMENxMv9IBmJD
y5hfMtlcFb7XOmlHr0eRuR1U4IVF4k9v2b1vCWYWJLhJHRWQFaLQPGm0Y/1KL1F3
eXA81iNBFKIzqgiB0SSRxIt+mx4ZHg7QCwAYqzLFK8m59KRCz+eD1Ho/cO9NC/rZ
vwLdy6e2
-----END CERTIFICATE-----''';
