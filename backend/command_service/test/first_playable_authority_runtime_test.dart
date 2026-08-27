import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:board_backend_api/backend_api.dart';
import 'package:board_command_service/command_service.dart'
    hide ReconnectDisposition;
import 'package:board_command_service/ingress/command_ingress.dart';
import 'package:board_command_service/observability/authority_observability.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_roll_fixture.dart';

void main() {
  test(
    'composition root carries Flutter Roll and lost-ACK through one authority',
    () async {
      final store = _RuntimeStore();
      final logs = _LogSink();
      final runtime = FirstPlayableAuthorityRuntime(
        identityVerifier: FirebaseIdentityVerifier(
          projectId: 'synthetic-project',
          signatureVerifier: const _SignatureVerifier(),
          now: () => DateTime.utc(2026, 8, 26, 12, 30),
        ),
        store: store,
        rulesCatalogRepository: PinnedFirstPlayableRulesCatalogRepository(
          activeRulesVersion: syntheticRollCatalog().rulesVersion,
          catalogs: <RulesCatalog>[syntheticRollCatalog()],
        ),
        observability: BestEffortAuthorityObservability(logs),
        now: () => DateTime.utc(2026, 8, 26, 12, 30),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(runtime.handle);
      final transport = HttpAuthorityWireTransport(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        idTokenProvider: () async => _token(),
      );
      addTearDown(() async {
        transport.close(force: true);
        await server.close(force: true);
      });
      final client = WireAuthorityClient(transport);
      final request = AuthorityCommandRequest.game(syntheticRollCommand());

      final accepted = await client.send(request);
      final lostAckRetry = await client.send(request);
      final reconnect = await client.reconnect(
        AuthorityReconnectRequest(
          gameId: syntheticRollCommand().gameId,
          observedStateVersion: 0,
          uncertainCommand: request.uncertainIdentity,
        ),
      );

      expect(accepted.status, AuthorityCommandStatus.accepted);
      expect(lostAckRetry.status, AuthorityCommandStatus.duplicate);
      expect(store.writeCount, 1);
      expect(store.state.header.stateVersion, 1);
      expect(reconnect.disposition, ReconnectDisposition.uncertainConfirmed);
      expect(
        reconnect.commandResolution!.action,
        CommandResolutionAction.useDurableResult,
      );
      expect(logs.events, hasLength(2));
      expect(logs.events.first['outcome'], 'success');
      expect(logs.events.last['outcome'], 'duplicate');
      expect(logs.events.expand((event) => event.keys), isNot(contains('uid')));
      expect(
        jsonEncode(logs.events),
        isNot(anyOf(contains('uid-p1'), contains(request.inputHash))),
      );
    },
  );
}

final class _RuntimeStore implements FirstPlayableAuthorityStore {
  PublicGameState state = syntheticRollState();
  AuthorityPrivateRngSnapshot privateRng = syntheticRollPrivateState();
  StoredAuthorityCommandReceipt? receipt;
  var writeCount = 0;

  FirstPlayableGameTransactionView _view({String? commandId}) =>
      FirstPlayableGameTransactionView(
        publicState: state,
        memberUidByPlayerId: const <String, String>{'p1': 'uid-p1'},
        privateRng: privateRng,
        storedReceipt: commandId == receipt?.receipt.commandId ? receipt : null,
      );

  @override
  Future<FirstPlayableRoomEntryTransactionResult> transactRoomEntry({
    required FirstPlayableRoomEntryKind kind,
    required String codeHash,
    String? roomId,
    required String commandId,
    required FirstPlayableRoomEntryTransactionCallback evaluate,
  }) => throw UnimplementedError('Roll runtime test does not enter a room');

  @override
  Future<FirstPlayableGameReadResult> readGame({
    required String gameId,
    String? commandId,
  }) async {
    _requireGame(gameId);
    return FirstPlayableGameReadResult(
      view: _view(commandId: commandId),
      metrics: AuthorityExecutionMetrics(
        firestoreReadCount: commandId == null ? 2 : 3,
        schemaVersion: state.header.schemaVersion,
        stateVersion: state.header.stateVersion,
      ),
    );
  }

  @override
  Future<FirstPlayableGameTransactionResult> transactGame({
    required String gameId,
    required String commandId,
    required FirstPlayableGameTransactionCallback evaluate,
  }) async {
    _requireGame(gameId);
    final decision = evaluate(_view(commandId: commandId));
    var writes = 0;
    if (decision.publicStateAfter != null) {
      state = decision.publicStateAfter!;
      writes += 1;
    }
    if (decision.privateRngAfter != null) {
      privateRng = decision.privateRngAfter!;
      writes += 1;
    }
    if (decision.receiptToPersist != null) {
      receipt = decision.receiptToPersist;
      writeCount += 1;
      writes += 1;
    }
    return FirstPlayableGameTransactionResult(
      decision: decision,
      metrics: AuthorityExecutionMetrics(
        firestoreReadCount: 3,
        firestoreWriteCount: writes,
        schemaVersion: state.header.schemaVersion,
        stateVersion: state.header.stateVersion,
      ),
    );
  }

  @override
  Future<FirstPlayableRoomTransactionResult> transactRoom({
    required String roomId,
    required String commandId,
    required FirstPlayableRoomTransactionCallback evaluate,
  }) => throw UnimplementedError('Roll runtime test does not enter a room');

  void _requireGame(String gameId) {
    if (gameId != state.header.gameId) {
      throw const FirstPlayableAuthorityExecutorViolation('gameUnavailable');
    }
  }
}

final class _LogSink implements AuthorityLogSink {
  final events = <Map<String, Object>>[];

  @override
  void write(Map<String, Object> fields) => events.add(fields);
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
      '${encode(<String, Object?>{'aud': 'synthetic-project', 'iss': 'https://securetoken.google.com/synthetic-project', 'exp': 1787749200, 'iat': 1787746800, 'auth_time': 1787746800, 'sub': 'uid-p1'})}.c2lnbmF0dXJl';
}
