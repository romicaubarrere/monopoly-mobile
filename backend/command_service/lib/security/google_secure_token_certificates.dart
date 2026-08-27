import 'dart:convert';
import 'dart:io';

const googleSecureTokenCertificatesUrl =
    'https://www.googleapis.com/robot/v1/metadata/x509/'
    'securetoken@system.gserviceaccount.com';

final class CertificateFetchResponse {
  const CertificateFetchResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
}

typedef SecureTokenCertificateFetcher =
    Future<CertificateFetchResponse> Function();

/// Bounded HTTPS fetcher for Google's canonical Firebase Auth certificates.
/// Loopback HTTP is accepted only to exercise the adapter against local tests.
final class GoogleSecureTokenCertificateHttpFetcher {
  GoogleSecureTokenCertificateHttpFetcher({HttpClient? client, Uri? endpoint})
    : _client = client ?? HttpClient(),
      _endpoint = endpoint ?? Uri.parse(googleSecureTokenCertificatesUrl) {
    final address = InternetAddress.tryParse(_endpoint.host);
    final loopback =
        _endpoint.host == 'localhost' || address?.isLoopback == true;
    if (_endpoint.scheme != 'https' && !loopback) {
      throw const FormatException('firebaseCertificateEndpointMustUseHttps');
    }
  }

  static const int _maximumResponseBytes = 1024 * 1024;

  final HttpClient _client;
  final Uri _endpoint;

  Future<CertificateFetchResponse> call() async {
    final request = await _client.getUrl(_endpoint);
    request.followRedirects = false;
    final response = await request.close();
    final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
      if (buffer.length + chunk.length > _maximumResponseBytes) {
        throw const FormatException('firebaseCertificateResponseTooLarge');
      }
      buffer.addAll(chunk);
      return buffer;
    });
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(',');
    });
    return CertificateFetchResponse(
      statusCode: response.statusCode,
      headers: Map.unmodifiable(headers),
      body: utf8.decode(bytes),
    );
  }
}

final class SecureTokenCertificateException implements Exception {
  const SecureTokenCertificateException(this.code);

  final String code;

  @override
  String toString() => 'SecureTokenCertificateException($code)';
}

/// Caches Google's Firebase secure-token certificate map using response
/// `Cache-Control: max-age` as required by ADR-007.
final class GoogleSecureTokenCertificateCache {
  GoogleSecureTokenCertificateCache({
    required SecureTokenCertificateFetcher fetch,
    DateTime Function()? now,
  }) : _fetch = fetch,
       _now = now ?? DateTime.now;

  final SecureTokenCertificateFetcher _fetch;
  final DateTime Function() _now;

  Map<String, String> _certificates = const <String, String>{};
  DateTime? _expiresAt;
  Future<void>? _refreshInFlight;

  Future<String> certificateForKid(String kid) async {
    if (kid.isEmpty) {
      throw const SecureTokenCertificateException('missing_kid');
    }

    if (_isFresh()) {
      final certificate = _certificates[kid];
      if (certificate != null) {
        return certificate;
      }
      throw const SecureTokenCertificateException('unknown_kid');
    }

    await _refreshCertificates();
    final certificate = _certificates[kid];
    if (certificate == null) {
      throw const SecureTokenCertificateException('unknown_kid');
    }
    return certificate;
  }

  bool _isFresh() {
    final expiresAt = _expiresAt;
    if (expiresAt == null || _certificates.isEmpty) {
      return false;
    }
    return _now().toUtc().isBefore(expiresAt);
  }

  Future<void> _refreshCertificates() async {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final refresh = _refresh();
    _refreshInFlight = refresh;
    try {
      await refresh;
    } finally {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<void> _refresh() async {
    final response = await _fetch();
    if (response.statusCode != 200) {
      throw const SecureTokenCertificateException('certificate_fetch_failed');
    }

    final maxAgeSeconds = _parseMaxAge(response.headers);
    final certificates = _parseCertificateMap(response.body);

    _certificates = certificates;
    _expiresAt = _now().toUtc().add(Duration(seconds: maxAgeSeconds));
  }

  static int _parseMaxAge(Map<String, String> headers) {
    String? cacheControl;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'cache-control') {
        cacheControl = entry.value;
        break;
      }
    }
    if (cacheControl == null) {
      throw const SecureTokenCertificateException('missing_cache_max_age');
    }

    for (final directive in cacheControl.split(',')) {
      final parts = directive.trim().split('=');
      if (parts.length == 2 && parts[0].toLowerCase() == 'max-age') {
        final value = int.tryParse(parts[1].trim());
        if (value != null && value > 0) {
          return value;
        }
      }
    }
    throw const SecureTokenCertificateException('invalid_cache_max_age');
  }

  static Map<String, String> _parseCertificateMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?> || decoded.isEmpty) {
        throw const SecureTokenCertificateException(
          'invalid_certificate_response',
        );
      }
      final certificates = <String, String>{};
      for (final entry in decoded.entries) {
        final certificate = entry.value;
        if (entry.key.isEmpty ||
            certificate is! String ||
            certificate.isEmpty) {
          throw const SecureTokenCertificateException(
            'invalid_certificate_response',
          );
        }
        certificates[entry.key] = certificate;
      }
      return Map<String, String>.unmodifiable(certificates);
    } on SecureTokenCertificateException {
      rethrow;
    } on Object {
      throw const SecureTokenCertificateException(
        'invalid_certificate_response',
      );
    }
  }
}
