import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'firebase_identity_verifier.dart';
import 'google_secure_token_certificates.dart';

/// Concrete RS256 verifier for [FirebaseIdentityVerifier].
///
/// Certificate fetch/cache and claim validation stay in their existing
/// server-side boundaries. Parse, fetch or signature errors fail closed and do
/// not expose token, signature or certificate material.
final class GoogleFirebaseIdTokenSignatureVerifier
    implements IdTokenSignatureVerifier {
  const GoogleFirebaseIdTokenSignatureVerifier({
    required GoogleSecureTokenCertificateCache cache,
  }) : _certificates = cache;

  factory GoogleFirebaseIdTokenSignatureVerifier.live({
    DateTime Function()? now,
  }) {
    final fetcher = GoogleSecureTokenCertificateHttpFetcher();
    return GoogleFirebaseIdTokenSignatureVerifier(
      cache: GoogleSecureTokenCertificateCache(fetch: fetcher.call, now: now),
    );
  }

  final GoogleSecureTokenCertificateCache _certificates;

  @override
  Future<bool> verify({
    required String kid,
    required Uint8List signingInput,
    required Uint8List signature,
  }) async {
    try {
      final certificate = await _certificates.certificateForKid(kid);
      final signingText = utf8.decode(signingInput, allowMalformed: false);
      if (signingText.split('.').length != 2) return false;
      final encodedSignature = base64Url.encode(signature).replaceAll('=', '');
      final token = '$signingText.$encodedSignature';
      final key = certificate.contains('BEGIN CERTIFICATE')
          ? RSAPublicKey.cert(certificate)
          : RSAPublicKey(certificate);
      JWT.verify(
        token,
        key,
        checkHeaderType: false,
        checkExpiresIn: false,
        checkNotBefore: false,
      );
      return true;
    } on Object {
      return false;
    }
  }
}
