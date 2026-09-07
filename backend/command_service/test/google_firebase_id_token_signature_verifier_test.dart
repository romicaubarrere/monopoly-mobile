import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:board_command_service/security/firebase_identity_verifier.dart';
import 'package:board_command_service/security/google_firebase_id_token_signature_verifier.dart';
import 'package:board_command_service/security/google_secure_token_certificates.dart';
import 'package:board_command_service/security/membership_authorizer.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
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

  test(
    'a newly published kid refreshes once and verifies a real signature',
    () async {
      var loads = 0;
      final cache = GoogleSecureTokenCertificateCache(
        fetch: () async {
          loads += 1;
          return loads == 1
              ? CertificateFetchResponse(
                  statusCode: HttpStatus.ok,
                  headers: const {'Cache-Control': 'max-age=3600'},
                  body: jsonEncode({'previous-kid': _fixtureCertificate}),
                )
              : _certificateResponse;
        },
        now: () => DateTime.utc(2026, 8, 26, 12, 30),
      );
      await cache.certificateForKid('previous-kid');
      final verifier = FirebaseIdentityVerifier(
        projectId: 'fixture-project',
        signatureVerifier: GoogleFirebaseIdTokenSignatureVerifier(cache: cache),
        now: () => DateTime.utc(2026, 8, 26, 12, 30),
      );

      expect((await verifier.verify(_fixtureToken)).uid, 'uid-fixture');
      expect(loads, 2);
      expect((await verifier.verify(_fixtureToken)).uid, 'uid-fixture');
      expect(loads, 2);
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
    'unknown keys get at most one extra refresh while the cache is fresh',
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

      for (var index = 0; index < 20; index += 1) {
        await expectLater(
          certificates.certificateForKid('missing-kid-$index'),
          throwsA(
            isA<SecureTokenCertificateException>().having(
              (error) => error.code,
              'code',
              'unknown_kid',
            ),
          ),
        );
      }
      expect(loadCount, 2);
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

  _registerNegativeSuite();
}

void _registerNegativeSuite() {
  group('ADR-007 real-provider negative gate', () {
    for (final algorithm in ['none', 'HS256', 'PS256', 'RS512', 'ES256']) {
      test('rejects $algorithm before certificate lookup', () async {
        final harness = _VerifierHarness();
        await _expectRejected(
          harness,
          _changedToken(header: {'alg': algorithm}),
          'unsupported_algorithm',
        );
        expect(harness.loads, 0);
      });
    }

    test(
      'rejects a valid HS256 MAC made with public certificate material',
      () async {
        final harness = _VerifierHarness();
        final token = JWT(_fixturePayload(), header: {'kid': 'fixture-kid'})
            .sign(
              SecretKey(_fixtureCertificate),
              algorithm: JWTAlgorithm.HS256,
              noIssueAt: true,
            );
        await _expectRejected(harness, token, 'unsupported_algorithm');
        expect(harness.loads, 0);
      },
    );

    for (final kid in <Object?>[null, '', 42]) {
      test('rejects missing/invalid kid ${kid.runtimeType}', () async {
        final harness = _VerifierHarness();
        await _expectRejected(
          harness,
          _changedToken(header: {'kid': kid}),
          'missing_kid',
        );
        expect(harness.loads, 0);
      });
    }

    final nowSeconds =
        DateTime.utc(2026, 8, 26, 12, 30).millisecondsSinceEpoch ~/ 1000;
    final invalidClaims = <(String, Object?, String)>[
      ('aud', 'other-project', 'invalid_audience'),
      ('aud', ['fixture-project'], 'invalid_audience'),
      ('iss', 'https://securetoken.google.com/other-project', 'invalid_issuer'),
      ('exp', nowSeconds, 'expired_token'),
      ('exp', nowSeconds - 1, 'expired_token'),
      ('iat', nowSeconds + 1, 'issued_in_future'),
      ('auth_time', nowSeconds + 1, 'auth_time_in_future'),
      ('sub', '', 'invalid_subject'),
      ('sub', null, 'invalid_subject'),
      ('sub', List.filled(129, 'x').join(), 'invalid_subject'),
    ];
    for (var index = 0; index < invalidClaims.length; index += 1) {
      final (claim, value, code) = invalidClaims[index];
      test('rejects invalid $claim case $index before crypto', () async {
        final harness = _VerifierHarness();
        await _expectRejected(
          harness,
          _changedToken(payload: {claim: value}),
          code,
        );
        expect(harness.loads, 0);
      });
    }
    for (final claim in ['exp', 'iat', 'auth_time']) {
      for (final value in <Object?>[null, '123', -1, 1.5, true]) {
        test('rejects malformed $claim ${value.runtimeType}', () async {
          final harness = _VerifierHarness();
          await _expectRejected(
            harness,
            _changedToken(payload: {claim: value}),
            'invalid_$claim',
          );
          expect(harness.loads, 0);
        });
      }
    }

    test('altered signature fails against the real X509 public key', () async {
      final signature = base64Url.decode(
        base64Url.normalize(_fixtureToken.split('.')[2]),
      );
      signature[0] ^= 1;
      final harness = _VerifierHarness();
      await _expectRejected(
        harness,
        _changedToken(
          signature: base64Url.encode(signature).replaceAll('=', ''),
        ),
        'invalid_signature',
      );
      expect(harness.loads, 1);
    });
    test(
      'a different valid subject cannot reuse the original signature',
      () async {
        final harness = _VerifierHarness();
        await _expectRejected(
          harness,
          _changedToken(payload: {'sub': 'different-uid'}),
          'invalid_signature',
        );
        expect(harness.loads, 1);
      },
    );
    test(
      'valid signature cannot verify against an unrelated RSA modulus',
      () async {
        final certificate = _unrelatedPublicCertificate();
        // Prove this is parseable key material, not merely a broken-PEM test.
        final original = RSAPublicKey.cert(_fixtureCertificate).key;
        final unrelated = RSAPublicKey.cert(certificate).key;
        expect(unrelated.modulus, isNot(original.modulus));
        final harness = _VerifierHarness()
          ..response = _responseWithCertificate(certificate);
        await _expectRejected(harness, _fixtureToken, 'invalid_signature');
        expect(harness.loads, 1);
      },
    );

    for (final certificate in [
      'invalid-certificate',
      '-----BEGIN CERTIFICATE-----\ninvalid\n-----END CERTIFICATE-----',
    ]) {
      test(
        'malformed certificate fails closed ${certificate.length}',
        () async {
          final harness = _VerifierHarness()
            ..response = _responseWithCertificate(certificate);
          await _expectRejected(harness, _fixtureToken, 'invalid_signature');
        },
      );
    }
    test(
      'unknown kid after refresh fails without repeated fresh-cache fetches',
      () async {
        final harness = _VerifierHarness();
        for (var index = 0; index < 20; index += 1) {
          await _expectRejected(
            harness,
            _changedToken(header: {'kid': 'unknown-$index'}),
            'invalid_signature',
          );
        }
        expect(
          harness.loads,
          2,
        ); // Initial map plus one controlled extra refresh.
      },
    );
    test('expired cache is refreshed exactly at max-age', () async {
      final harness = _VerifierHarness();
      await harness.verifier.verify(_fixtureToken);
      harness.now = harness.now.add(const Duration(seconds: 3599));
      await harness.verifier.verify(_fixtureToken);
      expect(harness.loads, 1);
      harness.now = harness.now.add(const Duration(seconds: 1));
      await harness.verifier.verify(_fixtureToken);
      expect(harness.loads, 2);
    });
    test(
      'failed unknown-key refresh retains a still-valid matching key',
      () async {
        final harness = _VerifierHarness();
        await harness.verifier.verify(_fixtureToken);
        harness.fetchFailure = StateError('untrusted provider error');
        await _expectRejected(
          harness,
          _changedToken(header: {'kid': 'new-kid'}),
          'invalid_signature',
        );
        expect(
          (await harness.verifier.verify(_fixtureToken)).uid,
          'uid-fixture',
        );
        for (var index = 0; index < 10; index += 1) {
          await _expectRejected(
            harness,
            _changedToken(header: {'kid': 'missing-$index'}),
            'invalid_signature',
          );
        }
        expect(harness.loads, 2);
      },
    );
    test('expired key is never used when its refresh fails', () async {
      final harness = _VerifierHarness();
      await harness.verifier.verify(_fixtureToken);
      harness.now = harness.now.add(const Duration(hours: 1));
      harness.fetchFailure = StateError('untrusted provider error');
      await _expectRejected(harness, _fixtureToken, 'invalid_signature');
      expect(harness.loads, 2);
    });
    test(
      'cold fetch failure rejects without leaking the provider error',
      () async {
        final harness = _VerifierHarness()
          ..fetchFailure = StateError('untrusted provider error');
        await _expectRejected(harness, _fixtureToken, 'invalid_signature');
        expect(harness.loads, 1);
      },
    );
    final badResponses = <CertificateFetchResponse>[
      const CertificateFetchResponse(
        statusCode: 503,
        headers: {},
        body: 'upstream error',
      ),
      const CertificateFetchResponse(statusCode: 200, headers: {}, body: '{}'),
      CertificateFetchResponse(
        statusCode: 200,
        headers: const {'Cache-Control': 'max-age=0'},
        body: _certificateResponse.body,
      ),
      const CertificateFetchResponse(
        statusCode: 200,
        headers: {'Cache-Control': 'max-age=60'},
        body: 'not-json',
      ),
    ];
    for (var index = 0; index < badResponses.length; index += 1) {
      test('invalid certificate response $index fails closed', () async {
        final harness = _VerifierHarness()..response = badResponses[index];
        await _expectRejected(harness, _fixtureToken, 'invalid_signature');
      });
    }

    test('concurrent new-kid lookups share one controlled refresh', () async {
      var loads = 0;
      final started = Completer<void>();
      final refreshed = Completer<CertificateFetchResponse>();
      final cache = GoogleSecureTokenCertificateCache(
        fetch: () async {
          loads += 1;
          if (loads == 1) return _certificateResponse;
          started.complete();
          return refreshed.future;
        },
        now: () => DateTime.utc(2026, 8, 26, 12, 30),
      );
      await cache.certificateForKid('fixture-kid');
      final pending = Future.wait(
        List.generate(20, (_) => cache.certificateForKid('rotated-kid')),
      );
      await started.future;
      expect(loads, 2);
      // Matching cached keys stay usable while the unknown-key refresh waits.
      expect(await cache.certificateForKid('fixture-kid'), _fixtureCertificate);
      refreshed.complete(
        CertificateFetchResponse(
          statusCode: 200,
          headers: const {'Cache-Control': 'max-age=3600'},
          body: jsonEncode({
            'fixture-kid': _fixtureCertificate,
            'rotated-kid': _fixtureCertificate,
          }),
        ),
      );
      expect(await pending, everyElement(_fixtureCertificate));
      expect(loads, 2);
    });

    test('expiry replenishes the controlled refresh budget but refresh itself does not', () async {
      final harness = _VerifierHarness();
      await harness.verifier.verify(_fixtureToken);
      await _expectRejected(
        harness,
        _changedToken(header: {'kid': 'missing'}),
        'invalid_signature',
      );
      expect(harness.loads, 2);
      harness.now = harness.now.add(const Duration(hours: 1));
      await harness.verifier.verify(_fixtureToken);
      expect(harness.loads, 3);
      await _expectRejected(
        harness,
        _changedToken(header: {'kid': 'missing-again'}),
        'invalid_signature',
      );
      await _expectRejected(
        harness,
        _changedToken(header: {'kid': 'missing-third'}),
        'invalid_signature',
      );
      expect(harness.loads, 4);
    });

    final memberships = <(AuthorityMembership?, String)>[
      (null, 'not_a_member'),
      (
        const AuthorityMembership(
          uid: 'different-uid',
          gameId: 'game-fixture',
          playerId: 'player-fixture',
          isHost: true,
        ),
        'not_a_member',
      ),
      (
        const AuthorityMembership(
          uid: 'uid-fixture',
          gameId: 'other-game',
          playerId: 'player-fixture',
          isHost: true,
        ),
        'membership_scope_mismatch',
      ),
      (
        const AuthorityMembership(
          uid: 'uid-fixture',
          gameId: 'game-fixture',
          playerId: 'other-player',
          isHost: true,
        ),
        'actor_mismatch',
      ),
      (
        const AuthorityMembership(
          uid: 'uid-fixture',
          gameId: 'game-fixture',
          playerId: 'player-fixture',
          isHost: false,
        ),
        'host_required',
      ),
    ];
    for (var index = 0; index < memberships.length; index += 1) {
      final (membership, code) = memberships[index];
      test(
        'real authenticated uid still requires separate authorization $index',
        () async {
          final identity = await _VerifierHarness().verifier.verify(
            _fixtureToken,
          );
          final authorizer = MembershipAuthorizer(
            _FixtureMembershipStore(membership),
          );
          await expectLater(
            authorizer.requireMember(
              authenticatedUid: identity.uid,
              gameId: 'game-fixture',
              claimedPlayerId: 'player-fixture',
              requireHost: true,
            ),
            throwsA(
              isA<MembershipAuthorizationException>().having(
                (error) => error.code,
                'code',
                code,
              ),
            ),
          );
        },
      );
    }
  });
}

class _VerifierHarness {
  DateTime now = DateTime.utc(2026, 8, 26, 12, 30);
  int loads = 0;
  Object? fetchFailure;
  CertificateFetchResponse response = _certificateResponse;
  late final cache = GoogleSecureTokenCertificateCache(
    fetch: () async {
      loads += 1;
      final failure = fetchFailure;
      if (failure != null) throw failure;
      return response;
    },
    now: () => now,
  );
  late final verifier = FirebaseIdentityVerifier(
    projectId: 'fixture-project',
    signatureVerifier: GoogleFirebaseIdTokenSignatureVerifier(cache: cache),
    now: () => now,
  );
}

Future<void> _expectRejected(
  _VerifierHarness harness,
  String token,
  String code,
) async {
  IdentityVerificationException? failure;
  final logs = <String>[];
  await runZoned(
    () async {
      try {
        await harness.verifier.verify(token);
      } on IdentityVerificationException catch (error) {
        failure = error;
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => logs.add(line),
    ),
  );
  expect(failure, isNotNull, reason: 'Invalid identity must never be accepted');
  expect(failure!.code, code);
  expect(failure.toString(), 'IdentityVerificationException($code)');
  expect(logs, isEmpty);
}

Map<String, Object?> _fixturePayload() => Map<String, Object?>.from(
  jsonDecode(
    utf8.decode(
      base64Url.decode(base64Url.normalize(_fixtureToken.split('.')[1])),
    ),
  ) as Map,
);

String _changedToken({
  Map<String, Object?>? header,
  Map<String, Object?>? payload,
  String? signature,
}) {
  final parts = _fixtureToken.split('.');
  String changed(String part, Map<String, Object?> changes) {
    final decoded = Map<String, Object?>.from(
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(part))))
          as Map,
    );
    decoded.addAll(changes);
    return base64Url
        .encode(utf8.encode(jsonEncode(decoded)))
        .replaceAll('=', '');
  }

  return '${header == null ? parts[0] : changed(parts[0], header)}.'
      '${payload == null ? parts[1] : changed(parts[1], payload)}.'
      '${signature ?? parts[2]}';
}

CertificateFetchResponse _responseWithCertificate(String certificate) =>
    CertificateFetchResponse(
      statusCode: 200,
      headers: const {'Cache-Control': 'max-age=3600'},
      body: jsonEncode({'fixture-kid': certificate}),
    );

String _unrelatedPublicCertificate() {
  // Change only the public RSA modulus inside the existing synthetic X509 DER.
  // No private key is generated, committed or needed; this is not PKI validation.
  final bytes = base64.decode(
    _fixtureCertificate
        .split('\n')
        .where((line) => !line.startsWith('-----'))
        .join(),
  );
  const prefix = [0x02, 0x82, 0x01, 0x01, 0x00]; // 2048-bit positive INTEGER.
  var offset = -1;
  for (var index = 0; index <= bytes.length - prefix.length; index += 1) {
    if (List.generate(
      prefix.length,
      (n) => bytes[index + n] == prefix[n],
    ).every((match) => match)) {
      offset = index + prefix.length;
      break;
    }
  }
  if (offset < 0) throw StateError('Synthetic RSA modulus not found');
  bytes[offset] ^= 1;
  return '-----BEGIN CERTIFICATE-----\n${base64.encode(bytes)}\n-----END CERTIFICATE-----';
}

class _FixtureMembershipStore implements MembershipStore {
  _FixtureMembershipStore(this.membership);
  final AuthorityMembership? membership;
  @override
  Future<AuthorityMembership?> findMembership({
    required String uid,
    required String gameId,
  }) async => membership;
}

final _certificateResponse = CertificateFetchResponse(
  statusCode: HttpStatus.ok,
  headers: const <String, String>{'Cache-Control': 'public, max-age=3600'},
  body: jsonEncode(<String, String>{'fixture-kid': _fixtureCertificate}),
);

const _fixtureToken =
    'eyJraWQiOiJmaXh0dXJlLWtpZCIsImFsZyI6IlJTMjU2IiwidHlwIjoiSldUIn0.' // pragma: allowlist secret
    'eyJhdWQiOiJmaXh0dXJlLXByb2plY3QiLCJpc3MiOiJodHRwczovL3NlY3VyZXRva2Vu' // pragma: allowlist secret
    'Lmdvb2dsZS5jb20vZml4dHVyZS1wcm9qZWN0IiwiZXhwIjoxNzg3NzUyODAwLCJpYXQi' // pragma: allowlist secret
    'OjE3ODc3NDU2MDAsImF1dGhfdGltZSI6MTc4Nzc0NTYwMCwic3ViIjoidWlkLWZpeHR1' // pragma: allowlist secret
    'cmUifQ.' // pragma: allowlist secret
    'wB3BsJN6gf6H_M8R_t4qR3aLV0N9yYQCkXeNzySgQldA0F3X4zE2et8xdBEl3g97k59R' // pragma: allowlist secret
    'r602dxqa0sZH5T7cnWW-anyUnBqzwkUNCehWL7Yr4tRDFFh-f7lTlm4t-RN9Kay3KSGH' // pragma: allowlist secret
    'yYSDQMMMHvUiuQjGMePVA17vOL7mo6y7w3XmHKWC3tvkE_QMGnaj7JooAmv39VXJm_aE' // pragma: allowlist secret
    'XdDbOXmPYvGVbap5rLCUHq7Q20FRUBaCral6Cti15KQf8Dh9ljWuOZbypqGnVydEyHgH' // pragma: allowlist secret
    'Ij8d_suhHdYBNSrptVVKaOLDhSunN2v_twLfaS-yvCx3_DsAS-A5PpPsWvbPMJ_say1Q' // pragma: allowlist secret
    'vQ'; // pragma: allowlist secret

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
