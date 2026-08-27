import 'dart:convert';
import 'dart:io';

import 'package:board_backend_api/backend_api.dart';

import '../ingress/command_ingress.dart';
import '../security/firebase_identity_verifier.dart';
import '../security/membership_authorizer.dart';

/// Authority implementation behind the authenticated HTTP boundary.
///
/// Implementations must authorize membership and delegate gameplay transitions
/// to the existing Engine planners/persistence. The HTTP layer owns no rules.
abstract interface class AuthorityHttpExecutor {
  Future<AuthorityExecutionResult<AuthorityCommandReply>> executeCommand({
    required IngressContext context,
    required VerifiedIdentity identity,
    required AuthorityCommandRequest request,
  });

  Future<AuthorityReconnectReply> reconnect({
    required IngressContext context,
    required VerifiedIdentity identity,
    required AuthorityReconnectRequest request,
  });

  Future<AuthorityPublicSnapshot> readPublicGame({
    required IngressContext context,
    required VerifiedIdentity identity,
    required String gameId,
  });

  Future<AuthorityPublicRoomSnapshot> readPublicRoom({
    required IngressContext context,
    required VerifiedIdentity identity,
    required String roomId,
  });
}

/// Minimal authenticated network ingress used by Flutter and local emulators.
///
/// The bearer token is verified out-of-band, command fingerprints are
/// recomputed from canonical contracts, and every egress object is rejected if
/// it contains authority-private material.
final class AuthorityHttpIngress {
  AuthorityHttpIngress({
    required AuthorityIdentityVerifier identityVerifier,
    required CommandIngress commandIngress,
    required AuthorityHttpExecutor executor,
    DateTime Function()? now,
  }) : // Public named parameters cannot initialize private fields directly.
       // ignore: prefer_initializing_formals
       _identityVerifier = identityVerifier,
       // ignore: prefer_initializing_formals
       _commandIngress = commandIngress,
       // ignore: prefer_initializing_formals
       _executor = executor,
       _now = now ?? DateTime.now;

  static const int _maximumRequestBytes = 1024 * 1024;

  final AuthorityIdentityVerifier _identityVerifier;
  final CommandIngress _commandIngress;
  final AuthorityHttpExecutor _executor;
  final DateTime Function() _now;

  Future<void> handle(HttpRequest request) async {
    final context = IngressContext(requestReceivedAt: _now().toUtc());
    try {
      final identity = await _authenticate(request);
      final path = request.uri.pathSegments;
      if (request.method == 'POST' &&
          _matches(path, const <String>['v1', 'authority', 'commands'])) {
        await _handleCommand(request, context, identity);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const <String>['v1', 'authority', 'reconnect'])) {
        final wire = await _readJsonObject(request);
        final result = await _executor.reconnect(
          context: context,
          identity: identity,
          request: AuthorityReconnectRequest.fromWireJson(wire),
        );
        await _writeJson(
          request.response,
          HttpStatus.ok,
          validatedAuthorityPublicWireObject(result.toWireJson()),
        );
        return;
      }
      if (request.method == 'GET' &&
          path.length == 4 &&
          path[0] == 'v1' &&
          path[1] == 'authority' &&
          path[2] == 'games' &&
          path[3].isNotEmpty) {
        final result = await _executor.readPublicGame(
          context: context,
          identity: identity,
          gameId: path[3],
        );
        await _writeJson(
          request.response,
          HttpStatus.ok,
          validatedAuthorityPublicWireObject(result.toWireJson()),
        );
        return;
      }
      if (request.method == 'GET' &&
          path.length == 4 &&
          path[0] == 'v1' &&
          path[1] == 'authority' &&
          path[2] == 'rooms' &&
          path[3].isNotEmpty) {
        final result = await _executor.readPublicRoom(
          context: context,
          identity: identity,
          roomId: path[3],
        );
        await _writeJson(
          request.response,
          HttpStatus.ok,
          validatedAuthorityPublicWireObject(result.toWireJson()),
        );
        return;
      }
      await _error(request.response, HttpStatus.notFound, 'routeNotFound');
    } on IdentityVerificationException {
      await _error(
        request.response,
        HttpStatus.unauthorized,
        'authenticationRejected',
      );
    } on MembershipAuthorizationException {
      await _error(request.response, HttpStatus.forbidden, 'actorForbidden');
    } on ClientAuthorityContractViolation catch (error) {
      await _error(request.response, HttpStatus.badRequest, error.code);
    } on _AuthorityHttpRequestException catch (error) {
      await _error(request.response, error.statusCode, error.code);
    } on Object {
      await _error(
        request.response,
        HttpStatus.internalServerError,
        'authorityUnavailable',
      );
    }
  }

  Future<void> _handleCommand(
    HttpRequest httpRequest,
    IngressContext context,
    VerifiedIdentity identity,
  ) async {
    final wire = await _readJsonObject(httpRequest);
    final request = AuthorityCommandRequest.fromWireJson(wire);
    final expectedVersion = request.family == AuthorityCommandFamily.game
        ? request.command['expectedStateVersion']! as int
        : (request.command['expectedRoomVersion'] as int? ?? 0);
    final result = await _commandIngress.handle<AuthorityCommandReply>(
      ingressContext: context,
      command: IngressCommandEnvelope(
        kind: request.family == AuthorityCommandFamily.game
            ? IngressCommandKind.game
            : IngressCommandKind.room,
        commandId: request.commandId,
        inputHashVersion: request.inputHashVersion,
        expectedVersion: expectedVersion,
      ),
      execute: (capturedContext, _) => _executor.executeCommand(
        context: capturedContext,
        identity: identity,
        request: request,
      ),
    );
    await _writeJson(
      httpRequest.response,
      HttpStatus.ok,
      validatedAuthorityPublicWireObject(result.toWireJson()),
    );
  }

  Future<VerifiedIdentity> _authenticate(HttpRequest request) async {
    final values = request.headers[HttpHeaders.authorizationHeader];
    if (values == null || values.length != 1) {
      throw const IdentityVerificationException('missing_token');
    }
    final value = values.single;
    const prefix = 'Bearer ';
    if (!value.startsWith(prefix) || value.length == prefix.length) {
      throw const IdentityVerificationException('malformed_token');
    }
    return _identityVerifier.verify(value.substring(prefix.length));
  }

  static Future<Map<String, Object?>> _readJsonObject(
    HttpRequest request,
  ) async {
    final contentType = request.headers.contentType;
    if (contentType?.mimeType != ContentType.json.mimeType) {
      throw const _AuthorityHttpRequestException(
        HttpStatus.unsupportedMediaType,
        'jsonContentTypeRequired',
      );
    }
    final bytes = <int>[];
    await for (final chunk in request) {
      if (bytes.length + chunk.length > _maximumRequestBytes) {
        throw const _AuthorityHttpRequestException(
          HttpStatus.requestEntityTooLarge,
          'requestTooLarge',
        );
      }
      bytes.addAll(chunk);
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, Object?>) return decoded;
    } on FormatException {
      // Normalize malformed client input to the public error below.
    }
    throw const _AuthorityHttpRequestException(
      HttpStatus.badRequest,
      'invalidJsonObject',
    );
  }

  static bool _matches(List<String> actual, List<String> expected) =>
      actual.length == expected.length &&
      List<bool>.generate(
        actual.length,
        (index) => actual[index] == expected[index],
      ).every((matches) => matches);

  static Future<void> _error(
    HttpResponse response,
    int statusCode,
    String code,
  ) => _writeJson(response, statusCode, <String, Object?>{
    'error': <String, Object?>{'code': code},
  });

  static Future<void> _writeJson(
    HttpResponse response,
    int statusCode,
    Map<String, Object?> value,
  ) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(value));
    await response.close();
  }
}

final class _AuthorityHttpRequestException implements Exception {
  const _AuthorityHttpRequestException(this.statusCode, this.code);

  final int statusCode;
  final String code;
}
