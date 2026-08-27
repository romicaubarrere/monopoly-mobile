import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:board_backend_api/backend_api.dart';
import 'package:board_command_service/http/authority_http_ingress.dart';
import 'package:board_command_service/ingress/command_ingress.dart';
import 'package:board_command_service/observability/authority_observability.dart';
import 'package:board_command_service/security/firebase_identity_verifier.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Flutter wire reaches typed authenticated ingress without actor data',
    () async {
      final executor = _Executor();
      final ingress = AuthorityHttpIngress(
        identityVerifier: FirebaseIdentityVerifier(
          projectId: 'synthetic-project',
          signatureVerifier: const _SignatureVerifier(),
          now: () => DateTime.utc(2026, 8, 26, 4),
        ),
        commandIngress: const CommandIngress(
          observability: BestEffortAuthorityObservability(
            NoopAuthorityLogSink(),
          ),
        ),
        executor: executor,
        now: () => DateTime.utc(2026, 8, 26, 3, 59, 59),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(ingress.handle);
      final transport = HttpAuthorityWireTransport(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        idTokenProvider: () async => _token(),
        snapshotPollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(() async {
        transport.close(force: true);
        await server.close(force: true);
      });
      final client = WireAuthorityClient(transport);
      final command = AuthorityCommandRequest.game(
        GameCommand(
          commandId: 'cmd-roll-http-1',
          schemaVersion: 1,
          expectedStateVersion: 0,
          clientInstanceId: 'client-http-1',
          gameId: 'game-1',
          actorPlayerId: 'player-1',
          type: GameCommandType.rollDice,
          payload: const <String, Object?>{},
        ),
      );

      final reply = await client.send(command);
      final reconnect = await client.reconnect(
        AuthorityReconnectRequest(gameId: 'game-1', observedStateVersion: 1),
      );
      final watched = await client.watchGame('game-1').first;
      final room = await client.watchRoom('room-1').first;

      expect(reply.status, AuthorityCommandStatus.accepted);
      expect(reply.snapshot!.stateVersion, 1);
      expect(reconnect.disposition, ReconnectDisposition.upToDate);
      expect(watched.stateVersion, 1);
      expect(room.roomVersion, 2);
      expect(jsonEncode(room.toWireJson()), isNot(contains('uid')));
      expect(executor.uid, 'uid-synthetic-1');
      expect(executor.command!.inputHash, command.inputHash);
      expect(executor.command!.command, isNot(contains('uid')));
      expect(executor.receivedAt, DateTime.utc(2026, 8, 26, 3, 59, 59));
    },
  );

  test('malformed identity returns only a safe authentication code', () async {
    final ingress = AuthorityHttpIngress(
      identityVerifier: FirebaseIdentityVerifier(
        projectId: 'synthetic-project',
        signatureVerifier: const _SignatureVerifier(),
      ),
      commandIngress: const CommandIngress(
        observability: BestEffortAuthorityObservability(NoopAuthorityLogSink()),
      ),
      executor: _Executor(),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(ingress.handle);
    final transport = HttpAuthorityWireTransport(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      idTokenProvider: () async => 'not-a-jwt',
    );
    addTearDown(() async {
      transport.close(force: true);
      await server.close(force: true);
    });

    expect(
      transport.reconnect(<String, Object?>{
        'gameId': 'game-1',
        'observedStateVersion': 0,
      }),
      throwsA(
        isA<AuthorityTransportException>().having(
          (error) => error.code,
          'code',
          'authenticationRejected',
        ),
      ),
    );
  });
}

final class _Executor implements AuthorityHttpExecutor {
  String? uid;
  DateTime? receivedAt;
  AuthorityCommandRequest? command;

  @override
  Future<AuthorityExecutionResult<AuthorityCommandReply>> executeCommand({
    required IngressContext context,
    required VerifiedIdentity identity,
    required AuthorityCommandRequest request,
  }) async {
    uid = identity.uid;
    receivedAt = context.requestReceivedAt;
    command = request;
    return AuthorityExecutionResult<AuthorityCommandReply>(
      value: AuthorityCommandReply(
        commandId: request.commandId,
        status: AuthorityCommandStatus.accepted,
        versionBefore: 0,
        versionAfter: 1,
        publicResult: const <String, Object?>{'stateVersionAfter': 1},
        snapshot: AuthorityPublicSnapshot(_snapshot()),
      ),
      outcome: AuthorityOutcome.success,
      reason: AuthorityReason.none,
    );
  }

  @override
  Future<AuthorityPublicSnapshot> readPublicGame({
    required IngressContext context,
    required VerifiedIdentity identity,
    required String gameId,
  }) async => AuthorityPublicSnapshot(_snapshot());

  @override
  Future<AuthorityPublicRoomSnapshot> readPublicRoom({
    required IngressContext context,
    required VerifiedIdentity identity,
    required String roomId,
  }) async => AuthorityPublicRoomSnapshot(_roomSnapshot());

  @override
  Future<AuthorityReconnectReply> reconnect({
    required IngressContext context,
    required VerifiedIdentity identity,
    required AuthorityReconnectRequest request,
  }) async => AuthorityReconnectReply(
    disposition: ReconnectDisposition.upToDate,
    snapshot: AuthorityPublicSnapshot(_snapshot()),
  );
}

final class _SignatureVerifier implements IdTokenSignatureVerifier {
  const _SignatureVerifier();

  @override
  Future<bool> verify({
    required String kid,
    required Uint8List signingInput,
    required Uint8List signature,
  }) async => true;
}

String _token() {
  String encode(Map<String, Object?> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode(<String, Object?>{'alg': 'RS256', 'kid': 'synthetic-kid'})}.'
      '${encode(<String, Object?>{'aud': 'synthetic-project', 'iss': 'https://securetoken.google.com/synthetic-project', 'exp': 1787720400, 'iat': 1787716740, 'auth_time': 1787716740, 'sub': 'uid-synthetic-1'})}.c2lnbmF0dXJl';
}

Map<String, Object?> _snapshot() => <String, Object?>{
  'schemaVersion': 1,
  'stateVersion': 1,
  'gameId': 'game-1',
  'rulesVersion': 'synthetic-rules-vp0',
  'rngVersion': 'hmac_sha256_counter_v1',
  'rngCommitment': List<String>.filled(64, '0').join(),
  'turnState': const <String, Object?>{
    'phase': 'awaitingRoll',
    'currentPlayerId': 'player-1',
  },
};

Map<String, Object?> _roomSnapshot() => const <String, Object?>{
  'schemaVersion': 1,
  'roomId': 'room-1',
  'roomVersion': 2,
  'status': 'open',
  'hostPlayerId': 'player-1',
  'actorPlayerId': 'player-1',
  'presetId': 'express',
  'rulesVersion': 'synthetic-rules-vp0',
  'members': <Object?>[
    <String, Object?>{'playerId': 'player-1', 'kind': 'human', 'ready': true},
  ],
};
