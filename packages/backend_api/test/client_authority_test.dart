import 'dart:async';

import 'package:board_backend_api/backend_api.dart';
import 'package:board_game_contracts/game_contracts.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  group('Flutter to Authority command boundary', () {
    test('room request preserves canonical command and retry identity', () {
      final command = RoomCommand(
        commandId: 'cmd-ready-1',
        schemaVersion: 1,
        expectedRoomVersion: 7,
        clientInstanceId: 'client-a',
        type: RoomCommandType.setReady,
        payload: const <String, Object?>{'roomId': 'room-1', 'ready': true},
        sentAt: DateTime.utc(2026, 8, 26),
      );
      final first = AuthorityCommandRequest.room(command);
      final retry = AuthorityCommandRequest.room(command);

      expect(first.command, command.toJson());
      expect(first.asRoomCommand, same(command));
      expect(first.asRoomCommand.toJson(), first.command);
      expect(first.inputHashVersion, 1);
      expect(first.inputHash, retry.inputHash);
      expect(first.toCanonicalWireJson(), retry.toCanonicalWireJson());
      expect(first.toWireJson(), isNot(contains('authorization')));
    });

    test('game identity excludes transport time and client instance', () {
      AuthorityCommandRequest build({
        required String clientInstanceId,
        required DateTime sentAt,
      }) => AuthorityCommandRequest.game(
        GameCommand(
          commandId: 'cmd-roll-1',
          schemaVersion: 1,
          expectedStateVersion: 4,
          clientInstanceId: clientInstanceId,
          gameId: 'game-1',
          actorPlayerId: 'player-1',
          type: GameCommandType.rollDice,
          payload: const <String, Object?>{},
          sentAt: sentAt,
        ),
      );

      final first = build(
        clientInstanceId: 'client-a',
        sentAt: DateTime.utc(2026, 8, 26),
      );
      final sameSemantic = build(
        clientInstanceId: 'client-b',
        sentAt: DateTime.utc(2026, 8, 27),
      );

      expect(first.inputHash, sameSemantic.inputHash);
      expect(first.asGameCommand.toJson(), first.command);
      expect(first.inputHash, hasLength(64));
      expect(
        first.toCanonicalWireJson(),
        isNot(sameSemantic.toCanonicalWireJson()),
      );
    });

    test('semantic payload or state version changes the collision hash', () {
      AuthorityCommandRequest buy(int version, String propertyId) =>
          AuthorityCommandRequest.game(
            GameCommand(
              commandId: 'cmd-buy-1',
              schemaVersion: 1,
              expectedStateVersion: version,
              clientInstanceId: 'client-a',
              gameId: 'game-1',
              actorPlayerId: 'player-1',
              type: GameCommandType.buyProperty,
              payload: <String, Object?>{'propertyId': propertyId},
            ),
          );

      expect(
        buy(4, 'property-1').inputHash,
        isNot(buy(5, 'property-1').inputHash),
      );
      expect(
        buy(4, 'property-1').inputHash,
        isNot(buy(4, 'property-2').inputHash),
      );
    });

    test('ingress recomputes fingerprint and rejects body mutation', () {
      final request = AuthorityCommandRequest.game(
        GameCommand(
          commandId: 'cmd-buy-ingress-1',
          schemaVersion: 1,
          expectedStateVersion: 4,
          clientInstanceId: 'client-a',
          gameId: 'game-1',
          actorPlayerId: 'player-1',
          type: GameCommandType.buyProperty,
          payload: const <String, Object?>{'propertyId': 'property-1'},
        ),
      );
      final wire = request.toWireJson();

      expect(
        AuthorityCommandRequest.fromWireJson(wire),
        isA<AuthorityCommandRequest>()
            .having((value) => value.inputHash, 'inputHash', request.inputHash)
            .having(
              (value) => value.asGameCommand.toJson(),
              'validated game command',
              request.command,
            ),
      );
      expect(
        () => AuthorityCommandRequest.fromWireJson(<String, Object?>{
          ...wire,
          'command': <String, Object?>{
            ...(wire['command']! as Map<String, Object?>),
            'expectedStateVersion': 5,
          },
        }),
        throwsA(
          isA<ClientAuthorityContractViolation>().having(
            (error) => error.code,
            'code',
            'semanticFingerprintMismatch',
          ),
        ),
      );
    });

    test('typed accessors fail closed across command families', () {
      final roomRequest = AuthorityCommandRequest.room(
        RoomCommand(
          commandId: 'cmd-ready-family-1',
          schemaVersion: 1,
          expectedRoomVersion: 7,
          clientInstanceId: 'client-a',
          type: RoomCommandType.setReady,
          payload: const <String, Object?>{'roomId': 'room-1', 'ready': true},
        ),
      );
      final gameRequest = AuthorityCommandRequest.game(
        GameCommand(
          commandId: 'cmd-roll-family-1',
          schemaVersion: 1,
          expectedStateVersion: 4,
          clientInstanceId: 'client-a',
          gameId: 'game-1',
          actorPlayerId: 'player-1',
          type: GameCommandType.rollDice,
          payload: const <String, Object?>{},
        ),
      );

      for (final accessWrongFamily in <Object? Function()>[
        () => roomRequest.asGameCommand,
        () => gameRequest.asRoomCommand,
      ]) {
        expect(
          accessWrongFamily,
          throwsA(
            isA<ClientAuthorityContractViolation>().having(
              (error) => error.code,
              'code',
              'commandFamilyMismatch',
            ),
          ),
        );
      }
    });
  });

  group('public snapshot privacy and replacement', () {
    test('accepts public RNG commitment and versioned snapshot', () {
      final snapshot = _snapshot(3);

      expect(snapshot.schemaVersion, 1);
      expect(snapshot.stateVersion, 3);
      expect(snapshot.gameId, 'game-1');
      expect(snapshot.toCanonicalJson(), contains('rngCommitment'));
    });

    test('rejects authority-private material at any depth', () {
      for (final privateField in <String>[
        'seedBytes',
        'streamCounters',
        'futureDeckOrder',
        'authorization',
      ]) {
        expect(
          () => AuthorityPublicSnapshot(<String, Object?>{
            ..._snapshotJson(3),
            'nested': <String, Object?>{privateField: 'forbidden'},
          }),
          throwsA(
            isA<ClientAuthorityContractViolation>().having(
              (error) => error.code,
              'code',
              'privateMaterialForbidden',
            ),
          ),
        );
      }
    });

    test('snapshot is deeply immutable', () {
      final snapshot = _snapshot(3);
      final turnState = snapshot.snapshot['turnState']! as Map<String, Object?>;

      expect(
        () => turnState['phase'] = 'clientOverride',
        throwsUnsupportedError,
      );
    });

    test('reply versions enforce exactly-once accepted mutation', () {
      final accepted = AuthorityCommandReply(
        commandId: 'cmd-roll-1',
        status: AuthorityCommandStatus.accepted,
        versionBefore: 2,
        versionAfter: 3,
        snapshot: _snapshot(3),
      );
      final rejected = AuthorityCommandReply(
        commandId: 'cmd-roll-2',
        status: AuthorityCommandStatus.rejected,
        versionBefore: 3,
        versionAfter: 3,
        errorCode: 'notCurrentTurn',
      );

      expect(accepted.snapshot!.stateVersion, 3);
      expect(accepted.toWireJson(), <String, Object?>{
        'commandId': 'cmd-roll-1',
        'status': 'accepted',
        'versionBefore': 2,
        'versionAfter': 3,
        'publicResult': const <String, Object?>{},
        'snapshot': _snapshotJson(3),
      });
      expect(rejected.errorCode, 'notCurrentTurn');
      expect(
        () => AuthorityCommandReply(
          commandId: 'cmd-bad',
          status: AuthorityCommandStatus.accepted,
          versionBefore: 3,
          versionAfter: 3,
        ),
        throwsA(isA<ClientAuthorityContractViolation>()),
      );
    });
  });

  group('public room snapshot routing metadata', () {
    test('exposes Authority-issued gameId only when present and valid', () {
      final lobby = AuthorityPublicRoomSnapshot(_roomSnapshotJson());
      final active = AuthorityPublicRoomSnapshot(
        _roomSnapshotJson(gameId: 'game-1'),
      );

      expect(lobby.gameId, isNull);
      expect(active.gameId, 'game-1');
    });

    test('rejects malformed optional gameId', () {
      for (final gameId in <Object?>['', 7]) {
        expect(
          () => AuthorityPublicRoomSnapshot(_roomSnapshotJson(gameId: gameId)),
          throwsA(
            isA<ClientAuthorityContractViolation>().having(
              (error) => error.code,
              'code',
              'invalidRoomSnapshotGameId',
            ),
          ),
        );
      }
    });

    test('rejects incoherent status and game routing', () {
      expect(
        () => AuthorityPublicRoomSnapshot(<String, Object?>{
          ..._roomSnapshotJson(gameId: 'game-1'),
          'status': 'open',
        }),
        throwsA(_violation('inconsistentRoomSnapshotGameRouting')),
      );
      expect(
        () => AuthorityPublicRoomSnapshot(<String, Object?>{
          ..._roomSnapshotJson(gameId: 'game-1'),
          'status': 'paused',
        }),
        throwsA(_violation('invalidRoomSnapshotMetadata')),
      );
      expect(
        () => AuthorityPublicRoomSnapshot(<String, Object?>{
          ..._roomSnapshotJson(),
          'status': 'active',
        }),
        throwsA(_violation('inconsistentRoomSnapshotGameRouting')),
      );
    });
  });

  group('lost ACK and reconnect contract', () {
    final request = AuthorityCommandRequest.game(
      GameCommand(
        commandId: 'cmd-buy-1',
        schemaVersion: 1,
        expectedStateVersion: 8,
        clientInstanceId: 'client-a',
        gameId: 'game-1',
        actorPlayerId: 'player-1',
        type: GameCommandType.buyProperty,
        payload: const <String, Object?>{'propertyId': 'property-1'},
      ),
    );

    test('uncertain reconnect sends identity without command payload', () {
      final reconnect = AuthorityReconnectRequest(
        gameId: 'game-1',
        observedStateVersion: 8,
        uncertainCommand: request.uncertainIdentity,
      );
      final json = reconnect.toWireJson();
      final uncertain = json['uncertainCommand']! as Map<String, Object?>;

      expect(uncertain['commandId'], 'cmd-buy-1');
      expect(uncertain['inputHash'], request.inputHash);
      expect(uncertain, isNot(contains('payload')));
      expect(json, isNot(contains('snapshot')));
    });

    test('durable result resolves lost ACK without a second command', () {
      final resolution = ReconnectCommandResolution(
        identity: request.uncertainIdentity,
        action: CommandResolutionAction.useDurableResult,
        publicResult: const <String, Object?>{
          'commandId': 'cmd-buy-1',
          'status': 'accepted',
          'stateVersionBefore': 8,
          'stateVersionAfter': 9,
        },
      );
      final reply = AuthorityReconnectReply(
        disposition: ReconnectDisposition.uncertainConfirmed,
        snapshot: _snapshot(9),
        commandResolution: resolution,
      );

      expect(
        reply.commandResolution!.action,
        CommandResolutionAction.useDurableResult,
      );
      expect(reply.snapshot.stateVersion, 9);
      final wire = reply.toWireJson();
      expect(wire['disposition'], 'uncertainConfirmed');
      expect(
        (wire['commandResolution']! as Map<String, Object?>)['identity'],
        request.uncertainIdentity.toWireJson(),
      );
    });

    test('reconnect dispositions fail closed on mismatched actions', () {
      expect(
        () => AuthorityReconnectReply(
          disposition: ReconnectDisposition.semanticCollision,
          snapshot: _snapshot(8),
          commandResolution: ReconnectCommandResolution(
            identity: request.uncertainIdentity,
            action: CommandResolutionAction.retrySameCommand,
          ),
        ),
        throwsA(
          isA<ClientAuthorityContractViolation>().having(
            (error) => error.code,
            'code',
            'reconnectResolutionMismatch',
          ),
        ),
      );
    });

    test('missing receipt requires retry of the exact same request', () async {
      final gateway = _RecordingGateway();
      await gateway.send(request);
      await gateway.send(request);

      expect(gateway.sent, hasLength(2));
      expect(gateway.sent.first.commandId, gateway.sent.last.commandId);
      expect(gateway.sent.first.inputHash, gateway.sent.last.inputHash);
      expect(
        gateway.sent.first.toCanonicalWireJson(),
        gateway.sent.last.toCanonicalWireJson(),
      );
    });

    test(
      'repository exposes replacement snapshots and reconnect only',
      () async {
        final repository = _RecordingGateway();
        final next = repository.watchGame('game-1').first;
        repository.publish(_snapshot(10));

        expect((await next).stateVersion, 10);
        final reply = await repository.reconnect(
          AuthorityReconnectRequest(gameId: 'game-1', observedStateVersion: 9),
        );
        expect(reply.disposition, ReconnectDisposition.snapshotAdvanced);
        expect(reply.snapshot.stateVersion, 10);
      },
    );
  });
}

AuthorityPublicSnapshot _snapshot(int stateVersion) =>
    AuthorityPublicSnapshot(_snapshotJson(stateVersion));

Map<String, Object?> _snapshotJson(int stateVersion) => <String, Object?>{
  'schemaVersion': 1,
  'stateVersion': stateVersion,
  'rulesVersion': 'synthetic-rules-vp0',
  'rngVersion': 'hmac_sha256_counter_v1',
  'rngCommitment': List<String>.filled(64, '0').join(),
  'gameId': 'game-1',
  'roomId': 'room-1',
  'status': 'active',
  'turnState': const <String, Object?>{
    'phase': 'awaitingRoll',
    'currentPlayerId': 'player-1',
  },
};

Map<String, Object?> _roomSnapshotJson({Object? gameId}) => <String, Object?>{
  'schemaVersion': 1,
  'roomId': 'room-1',
  'roomVersion': 1,
  'status': gameId == null ? 'open' : 'active',
  'gameId': ?gameId,
  'hostPlayerId': 'player-1',
  'actorPlayerId': 'player-1',
  'presetId': 'synthetic-vp0',
  'rulesVersion': 'synthetic-rules-vp0',
  'members': const <Object?>[
    <String, Object?>{'playerId': 'player-1', 'kind': 'human', 'ready': false},
  ],
};

Matcher _violation(String code) => isA<ClientAuthorityContractViolation>()
    .having((error) => error.code, 'code', code);

final class _RecordingGateway
    implements CommandGateway, AuthoritySnapshotRepository {
  final List<AuthorityCommandRequest> sent = <AuthorityCommandRequest>[];
  final StreamController<AuthorityPublicSnapshot> _snapshots =
      StreamController<AuthorityPublicSnapshot>.broadcast();
  AuthorityPublicSnapshot _current = _snapshot(10);

  void publish(AuthorityPublicSnapshot snapshot) {
    _current = snapshot;
    _snapshots.add(snapshot);
  }

  @override
  Future<AuthorityCommandReply> send(AuthorityCommandRequest request) async {
    sent.add(request);
    return AuthorityCommandReply(
      commandId: request.commandId,
      status: AuthorityCommandStatus.duplicate,
      versionBefore: 8,
      versionAfter: 9,
    );
  }

  @override
  Stream<AuthorityPublicSnapshot> watchGame(String gameId) {
    if (gameId != 'game-1') {
      return const Stream<AuthorityPublicSnapshot>.empty();
    }
    return _snapshots.stream;
  }

  @override
  Future<AuthorityReconnectReply> reconnect(
    AuthorityReconnectRequest request,
  ) async => AuthorityReconnectReply(
    disposition: request.observedStateVersion == _current.stateVersion
        ? ReconnectDisposition.upToDate
        : ReconnectDisposition.snapshotAdvanced,
    snapshot: _current,
  );
}
