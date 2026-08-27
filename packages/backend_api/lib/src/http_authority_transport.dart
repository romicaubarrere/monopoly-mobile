import 'dart:convert';
import 'dart:io';

import 'client_authority_adapter.dart';

typedef AuthorityIdTokenProvider = Future<String> Function();

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
    HttpClient? httpClient,
  }) : _baseUri = _validateBaseUri(baseUri),
       // A public named parameter cannot initialize a private field directly.
       // ignore: prefer_initializing_formals
       _idTokenProvider = idTokenProvider,
       _snapshotPollInterval = snapshotPollInterval,
       _httpClient = httpClient ?? HttpClient() {
    if (snapshotPollInterval <= Duration.zero) {
      throw ArgumentError.value(
        snapshotPollInterval,
        'snapshotPollInterval',
        'must be positive',
      );
    }
  }

  static const int _maximumResponseBytes = 1024 * 1024;

  final Uri _baseUri;
  final AuthorityIdTokenProvider _idTokenProvider;
  final Duration _snapshotPollInterval;
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
    while (true) {
      yield await _request('GET', path);
      await Future<void>.delayed(_snapshotPollInterval);
    }
  }

  @override
  Stream<Map<String, Object?>> watchPublicRoom(String roomId) async* {
    if (roomId.isEmpty || roomId.contains('/')) {
      throw const AuthorityTransportException('invalidRoomId');
    }
    final path = '/v1/authority/rooms/${Uri.encodeComponent(roomId)}';
    while (true) {
      yield await _request('GET', path);
      await Future<void>.delayed(_snapshotPollInterval);
    }
  }

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
      final responseBody = await _readJsonObject(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AuthorityTransportException(switch (response.statusCode) {
          HttpStatus.unauthorized => 'authenticationRejected',
          HttpStatus.forbidden => 'actorForbidden',
          HttpStatus.conflict => 'authorityConflict',
          _ => 'authorityUnavailable',
        });
      }
      return responseBody;
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
