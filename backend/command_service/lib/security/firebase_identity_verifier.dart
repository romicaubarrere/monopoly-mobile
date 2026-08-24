import 'dart:convert';
import 'dart:typed_data';

final class VerifiedIdentity {
  const VerifiedIdentity({required this.uid, required this.authTime});

  final String uid;
  final DateTime authTime;
}

abstract interface class IdTokenSignatureVerifier {
  Future<bool> verify({
    required String kid,
    required Uint8List signingInput,
    required Uint8List signature,
  });
}

final class IdentityVerificationException implements Exception {
  const IdentityVerificationException(this.code);

  final String code;

  @override
  String toString() => 'IdentityVerificationException($code)';
}

/// Strict Firebase ID-token envelope/claims verifier.
///
/// Cryptographic RS256 verification is deliberately injected. The canonical M1
/// implementation may use `dart_jsonwebtoken` only behind [IdTokenSignatureVerifier].
/// Token material is never exposed through error values or loggable state.
final class FirebaseIdentityVerifier {
  const FirebaseIdentityVerifier({
    required this.projectId,
    required IdTokenSignatureVerifier signatureVerifier,
    DateTime Function()? now,
  }) : _signatureVerifier = signatureVerifier,
       _now = now ?? DateTime.now;

  final String projectId;
  final IdTokenSignatureVerifier _signatureVerifier;
  final DateTime Function() _now;

  Future<VerifiedIdentity> verify(String token) async {
    final parts = token.split('.');
    if (parts.length != 3 || parts.any((part) => part.isEmpty)) {
      throw const IdentityVerificationException('malformed_token');
    }

    final header = _decodeJsonObject(parts[0], 'invalid_header');
    if (header['alg'] != 'RS256') {
      throw const IdentityVerificationException('unsupported_algorithm');
    }
    final kid = header['kid'];
    if (kid is! String || kid.isEmpty) {
      throw const IdentityVerificationException('missing_kid');
    }

    final payload = _decodeJsonObject(parts[1], 'invalid_payload');
    final now = _now().toUtc();
    final expectedIssuer = 'https://securetoken.google.com/$projectId';

    if (payload['aud'] != projectId) {
      throw const IdentityVerificationException('invalid_audience');
    }
    if (payload['iss'] != expectedIssuer) {
      throw const IdentityVerificationException('invalid_issuer');
    }

    final exp = _requiredEpochSeconds(payload, 'exp');
    final iat = _requiredEpochSeconds(payload, 'iat');
    final authTime = _requiredEpochSeconds(payload, 'auth_time');
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    if (exp <= nowSeconds) {
      throw const IdentityVerificationException('expired_token');
    }
    if (iat > nowSeconds) {
      throw const IdentityVerificationException('issued_in_future');
    }
    if (authTime > nowSeconds) {
      throw const IdentityVerificationException('auth_time_in_future');
    }

    final sub = payload['sub'];
    if (sub is! String || sub.isEmpty || sub.length > 128) {
      throw const IdentityVerificationException('invalid_subject');
    }

    final signingInput = Uint8List.fromList(
      utf8.encode('${parts[0]}.${parts[1]}'),
    );
    final signature = _decodeBase64Url(parts[2], 'invalid_signature');
    final signatureValid = await _signatureVerifier.verify(
      kid: kid,
      signingInput: signingInput,
      signature: signature,
    );
    if (!signatureValid) {
      throw const IdentityVerificationException('invalid_signature');
    }

    return VerifiedIdentity(
      uid: sub,
      authTime: DateTime.fromMillisecondsSinceEpoch(
        authTime * 1000,
        isUtc: true,
      ),
    );
  }

  static Map<String, Object?> _decodeJsonObject(String encoded, String code) {
    try {
      final decoded = jsonDecode(utf8.decode(_decodeBase64Url(encoded, code)));
      if (decoded is! Map<String, Object?>) {
        throw IdentityVerificationException(code);
      }
      return decoded;
    } on IdentityVerificationException {
      rethrow;
    } on Object {
      throw IdentityVerificationException(code);
    }
  }

  static Uint8List _decodeBase64Url(String value, String code) {
    try {
      return Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
    } on Object {
      throw IdentityVerificationException(code);
    }
  }

  static int _requiredEpochSeconds(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is! int || value < 0) {
      throw IdentityVerificationException('invalid_$key');
    }
    return value;
  }
}
