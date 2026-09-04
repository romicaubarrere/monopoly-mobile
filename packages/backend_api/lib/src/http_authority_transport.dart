import 'dart:convert';
import 'dart:io';

import 'client_authority_adapter.dart';

typedef AuthorityIdTokenProvider = Future<String> Function();

/// Schedules the next public-snapshot poll.
///
/// The optional scheduler injection on [HttpAuthorityWireTransport] keeps the
/// transport's retry policy deterministic under a virtual test clock. Product
/// callers should use the default timer-backed implementation.
typedef AuthoritySnapshotPollDelay = Future<void> Function(Duration delay);

final class AuthorityTransportException implements Exception {
  const AuthorityTransportException(this.code);

  final String code;

  @override
  String toString() => 'AuthorityTransportException($code)';
}

/// Authenticated HTTP implementation of the minimal Flutter Authority wire.
///
/// ID tokens are attached only as an Authorization header and are never added
/// to command bodies or error values. Plain HTTP is restricted to loopback so
/// Firebase Emulator traffic cannot accidentally become a production mode.
final class HttpAuthorityWireTransport implements AuthorityWireTransport {
  HttpAuthorityWireTransport({
    required Uri baseUri,
    required AuthorityIdTokenProvider idTokenProvider,
    Duration snapshotPollInterval = const Duration(seconds: 1),
    Duration snapshotRetryMaxDelay = const Duration(seconds: 30),
    AuthoritySnapshotPollDelay? snapshotPollDelay,
    HttpClient? httpClient,
  }) : _baseUri = _validateBaseUri(baseUri),
       // A public named parameter cannot initialize a private field directly.
       // ignore: prefer_initializing_formals
       _idTokenProvider = idTokenProvider,
       _snapshotPollInterval = snapshotPollInterval,
       _snapshotRetryMaxDelay = snapshotRetryMaxDelay,
       _snapshotPollDelay = snapshotPollDelay ?? _wait,
       _httpClient = httpClient ?? HttpClient() {
    if (snapshotPollInterval <= Duration.zero) {
      throw ArgumentError.value(
        snapshotPollInterval,
        'snapshotPollInterval',
        'must be positive',
      );
    }
    if (snapshotRetryMaxDelay < snapshotPollInterval) {
      throw ArgumentError.value(
        snapshotRetryMaxDelay,
        'snapshotRetryMaxDelay',
        'must be greater than or equal to snapshotPollInterval',
      );
    }
  }

  static const int _maximumResponseBytes = 1024 * 1024;

  final Uri _baseUri;
  final AuthorityIdTokenProvider _idTokenProvider;
  final Duration _snapshotPollInterval;
  final Duration _snapshotRetryMaxDelay;
  final AuthoritySnapshotPollDelay _snapshotPollDelay;
  final HttpClient _httpClient;

  @override
  Future<Map<String, Object?>> sendCommand(Map<String, Object?> request) =>
      _request('POST', '/v1/authority/commands', body: request);

  @override
  Future<Map<String, Object?>> reconnect(Map<String, Object?> request) =>
      _request('POST', '/v1/authority/reconnect', body: request);

  @override
  Stream<Map<String, Object?>> watchPublicGame(String gameId) async* {
    if (gameId.isEmpty || gameId.contains('/')) {
      throw const AuthorityTransportException('invalidGameId');
    }
    final path = '/v1/authority/games/${Uri.encodeComponent(gameId)}';
    yield* _watchPublicSnapshot(path);
  }

  @override
  Stream<Map<String, Object?>> watchPublicRoom(String roomId) async* {
    if (roomId.isEmpty || roomId.contains('/')) {
      throw const AuthorityTransportException('invalidRoomId');
    }
    final path = '/v1/authority/rooms/${Uri.encodeComponent(roomId)}';
    yield* _watchPublicSnapshot(path);
  }

  Stream<Map<String, Object?>> _watchPublicSnapshot(String path) async* {
    var unavailableFailures = 0;
    while (true) {
      late final Map<String, Object?> snapshot;
      try {
        snapshot = await _request('GET', path);
      } on AuthorityTransportException catch (error) {
        if (error.code != 'authorityUnavailable') rethrow;
        unavailableFailures += 1;
        await _snapshotPollDelay(_retryDelay(unavailableFailures));
        continue;
      }
      unavailableFailures = 0;
      yield snapshot;
      await _snapshotPollDelay(_snapshotPollInterval);
    }
  }

  Duration _retryDelay(int unavailableFailures) {
    var delay = _snapshotPollInterval;
    for (var attempt = 1; attempt < unavailableFailures; attempt += 1) {
      if (delay >= _snapshotRetryMaxDelay) return _snapshotRetryMaxDelay;
      final remaining = _snapshotRetryMaxDelay - delay;
      if (delay > remaining) return _snapshotRetryMaxDelay;
      delay *= 2;
    }
    return delay > _snapshotRetryMaxDelay ? _snapshotRetryMaxDelay : delay;
  }

  static Future<void> _wait(Duration delay) => Future<void>.delayed(delay);

  void close({bool force = false}) => _httpClient.close(force: force);

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    try {
      final token = await _idTokenProvider();
      if (token.isEmpty ||
          token.trim() != token ||
          token.contains(RegExp(r'\s'))) {
        throw const AuthorityTransportException('authenticationUnavailable');
      }
      final request = await _httpClient.openUrl(method, _baseUri.resolve(path));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Error pages from proxies/load balancers are often HTML or plain
        // text. Classify the HTTP status before parsing so 5xx stays
        // retryable instead of being mistaken for a malformed Authority
        // success payload.
        await response.drain<void>();
        throw AuthorityTransportException(switch (response.statusCode) {
          HttpStatus.unauthorized => 'authenticationRejected',
          HttpStatus.forbidden => 'actorForbidden',
          HttpStatus.conflict => 'authorityConflict',
          _ => 'authorityUnavailable',
        });
      }
      return await _readJsonObject(response);
    } on AuthorityTransportException {
      rethrow;
    } on Object {
      throw const AuthorityTransportException('authorityUnavailable');
    }
  }

  static Future<Map<String, Object?>> _readJsonObject(
    HttpClientResponse response,
  ) async {
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > _maximumResponseBytes) {
        throw const AuthorityTransportException('responseTooLarge');
      }
      bytes.addAll(chunk);
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, Object?>) return decoded;
    } on FormatException {
      // Normalize malformed remote content to a safe transport code below.
    }
    throw const AuthorityTransportException('invalidAuthorityResponse');
  }

  static Uri _validateBaseUri(Uri value) {
    final loopback =
        value.host == 'localhost' ||
        value.host == '127.0.0.1' ||
        value.host == '::1';
    final validScheme =
        value.scheme == 'https' || value.scheme == 'http' && loopback;
    if (!validScheme ||
        value.host.isEmpty ||
        value.userInfo.isNotEmpty ||
        value.hasQuery ||
        value.hasFragment ||
        (value.path.isNotEmpty && value.path != '/')) {
      throw ArgumentError.value(value, 'baseUri', 'unsafe Authority origin');
    }
    return value.replace(path: '/');
  }
}
