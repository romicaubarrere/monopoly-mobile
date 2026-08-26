import 'dart:async';

import 'package:board_backend_api/backend_api.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'wire adapter preserves command identity and validates public reply',
    () async {
      final transport = _Transport();
      final client = WireAuthorityClient(transport);
      final request = AuthorityCommandRequest.game(
        GameCommand(
          commandId: 'cmd-roll-1',
          schemaVersion: 1,
          expectedStateVersion: 2,
          clientInstanceId: 'client-1',
          gameId: 'game-1',
          actorPlayerId: 'player-1',
          type: GameCommandType.rollDice,
          payload: const <String, Object?>{},
        ),
      );

      final reply = await client.send(request);

      expect(transport.lastCommand, request.toWireJson());
      expect(reply.status, AuthorityCommandStatus.accepted);
      expect(reply.snapshot!.stateVersion, 3);
    },
  );

  test('wire adapter rejects private snapshot material', () async {
    final transport = _Transport()..privateSnapshot = true;
    final client = WireAuthorityClient(transport);

    expect(
      client.watchGame('game-1').first,
      throwsA(
        isA<ClientAuthorityContractViolation>().having(
          (error) => error.code,
          'code',
          'privateMaterialForbidden',
        ),
      ),
    );
  });

  test(
    'reconnect carries identity only and decodes exact retry action',
    () async {
      final transport = _Transport();
      final client = WireAuthorityClient(transport);
      final identity = UncertainCommandIdentity(
        commandId: 'cmd-roll-1',
        inputHashVersion: 1,
        inputHash: List<String>.filled(64, 'a').join(),
      );

      final reply = await client.reconnect(
        AuthorityReconnectRequest(
          gameId: 'game-1',
          observedStateVersion: 2,
          uncertainCommand: identity,
        ),
      );

      expect(transport.lastReconnect, isNot(contains('snapshot')));
      expect(
        transport.lastReconnect!['uncertainCommand'],
        isNot(contains('payload')),
      );
      expect(reply.disposition, ReconnectDisposition.retrySameCommand);
      expect(
        reply.commandResolution!.action,
        CommandResolutionAction.retrySameCommand,
      );
    },
  );
}

final class _Transport implements AuthorityWireTransport {
  Map<String, Object?>? lastCommand;
  Map<String, Object?>? lastReconnect;
  bool privateSnapshot = false;

  @override
  Future<Map<String, Object?>> sendCommand(Map<String, Object?> request) async {
    lastCommand = request;
    return <String, Object?>{
      'commandId': request['command'] is Map<String, Object?>
          ? (request['command']! as Map<String, Object?>)['commandId']
          : null,
      'status': 'accepted',
      'versionBefore': 2,
      'versionAfter': 3,
      'publicResult': const <String, Object?>{
        'dice': <int>[4, 3],
      },
      'snapshot': _snapshot(3),
    };
  }

  @override
  Future<Map<String, Object?>> reconnect(Map<String, Object?> request) async {
    lastReconnect = request;
    return <String, Object?>{
      'disposition': 'retrySameCommand',
      'snapshot': _snapshot(2),
      'commandResolution': <String, Object?>{
        'identity': request['uncertainCommand'],
        'action': 'retrySameCommand',
      },
    };
  }

  @override
  Stream<Map<String, Object?>> watchPublicGame(String gameId) async* {
    final snapshot = _snapshot(3);
    if (privateSnapshot) snapshot['seedBytes'] = 'forbidden';
    yield snapshot;
  }
}

Map<String, Object?> _snapshot(int version) => <String, Object?>{
  'schemaVersion': 1,
  'stateVersion': version,
  'gameId': 'game-1',
  'rulesVersion': 'synthetic-rules-vp0',
  'rngVersion': 'hmac_sha256_counter_v1',
  'rngCommitment': List<String>.filled(64, '0').join(),
  'turnState': const <String, Object?>{
    'phase': 'awaitingRoll',
    'currentPlayerId': 'player-1',
  },
};
