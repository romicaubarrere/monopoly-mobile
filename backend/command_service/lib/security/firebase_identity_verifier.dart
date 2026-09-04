import 'dart:convert';
import 'dart:io';
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

abstract interface class AuthorityIdentityVerifier {
  Future<VerifiedIdentity> verify(String token);
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
final class FirebaseIdentityVerifier implements AuthorityIdentityVerifier {
  const FirebaseIdentityVerifier({
    required this.projectId,
    required this.signatureVerifier,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String projectId;
  final IdTokenSignatureVerifier signatureVerifier;
  final DateTime Function() _now;

  @override
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
    final identity = _verifiedIdentityFromClaims(
      payload: payload,
      projectId: projectId,
      now: _now().toUtc(),
    );

    final signingInput = Uint8List.fromList(
      utf8.encode('${parts[0]}.${parts[1]}'),
    );
    final signature = _decodeBase64Url(parts[2], 'invalid_signature');
    final signatureValid = await signatureVerifier.verify(
      kid: kid,
      signingInput: signingInput,
      signature: signature,
    );
    if (!signatureValid) {
      throw const IdentityVerificationException('invalid_signature');
    }

    return identity;
  }
}

/// Unsigned ID-token verifier for the Firebase Auth Emulator only.
///
/// Construction fails unless the project is a non-resource `demo-*` project
/// and `FIREBASE_AUTH_EMULATOR_HOST` is an explicit loopback host and port.
/// Production tokens and signed tokens are deliberately rejected here.
final class FirebaseAuthEmulatorIdentityVerifier
    implements AuthorityIdentityVerifier {
  FirebaseAuthEmulatorIdentityVerifier({
    required this.projectId,
    required String emulatorHost,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    if (!projectId.startsWith('demo-')) {
      throw const FormatException('firebaseAuthEmulatorProjectMustBeDemo');
    }
    _validateLoopbackEmulatorHost(emulatorHost);
  }

  factory FirebaseAuthEmulatorIdentityVerifier.fromEnvironment({
    required String projectId,
    Map<String, String>? environment,
    DateTime Function()? now,
  }) {
    final host =
        (environment ?? Platform.environment)['FIREBASE_AUTH_EMULATOR_HOST'];
    if (host == null || host.isEmpty) {
      throw const FormatException('firebaseAuthEmulatorHostMissing');
    }
    return FirebaseAuthEmulatorIdentityVerifier(
      projectId: projectId,
      emulatorHost: host,
      now: now,
    );
  }

  final String projectId;
  final DateTime Function() _now;

  @override
  Future<VerifiedIdentity> verify(String token) async {
    final parts = token.split('.');
    if (parts.length != 3 ||
        parts[0].isEmpty ||
        parts[1].isEmpty ||
        parts[2].isNotEmpty) {
      throw const IdentityVerificationException('malformed_token');
    }

    final header = _decodeJsonObject(parts[0], 'invalid_header');
    if (header['alg'] != 'none' || header['typ'] != 'JWT') {
      throw const IdentityVerificationException('unsupported_algorithm');
    }
    if (header.containsKey('kid')) {
      throw const IdentityVerificationException('unexpected_kid');
    }

    return _verifiedIdentityFromClaims(
      payload: _decodeJsonObject(parts[1], 'invalid_payload'),
      projectId: projectId,
      now: _now().toUtc(),
    );
  }
}

VerifiedIdentity _verifiedIdentityFromClaims({
  required Map<String, Object?> payload,
  required String projectId,
  required DateTime now,
}) {
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

  return VerifiedIdentity(
    uid: sub,
    authTime: DateTime.fromMillisecondsSinceEpoch(authTime * 1000, isUtc: true),
  );
}

void _validateLoopbackEmulatorHost(String value) {
  if (value.contains('://')) {
    throw const FormatException('firebaseAuthEmulatorHostMustNotUseScheme');
  }
  final uri = Uri.tryParse('http://$value');
  if (uri == null ||
      uri.host.isEmpty ||
      !uri.hasPort ||
      uri.port <= 0 ||
      uri.userInfo.isNotEmpty ||
      uri.path.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException('firebaseAuthEmulatorHostInvalid');
  }
  final address = InternetAddress.tryParse(uri.host);
  if (address?.isLoopback != true) {
    throw const FormatException('firebaseAuthEmulatorHostMustBeLoopback');
  }
}

Map<String, Object?> _decodeJsonObject(String encoded, String code) {
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

Uint8List _decodeBase64Url(String value, String code) {
  try {
    return Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
  } on Object {
    throw IdentityVerificationException(code);
  }
}

int _requiredEpochSeconds(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is! int || value < 0) {
    throw IdentityVerificationException('invalid_$key');
  }
  return value;
}
