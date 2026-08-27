import 'dart:async';

import 'package:board_backend_api/backend_api.dart';
import 'package:test/test.dart';

void main() {
  test(
    'composition consumes remote snapshots before the next command',
    () async {
      final transport = _Transport();
      final locatorStore = _LocatorStore();
      final client = FirstPlayableAuthorityClient.withTransport(
        transport: transport,
        pendingStore: _PendingStore(),
        sessionLocatorStore: locatorStore,
        commandIds: _Ids(),
        clientInstanceId: 'client-1',
        presetId: 'synthetic-vp0',
      );
      addTearDown(client.close);

      expect(
        (await client.perform(FirstPlayableAuthorityAction.createRoom))
            .accepted,
        isTrue,
      );
      expect(
        (await client.perform(FirstPlayableAuthorityAction.setReady)).accepted,
        isTrue,
      );
      final started = await client.perform(
        FirstPlayableAuthorityAction.startGame,
      );
      expect(started.accepted, isTrue, reason: started.safeErrorCode);
      expect(transport.watchedGameId, 'game-1');

      await Future<void>.delayed(Duration.zero);
      transport.gameSnapshots.add(_gameSnapshot(4));
      await Future<void>.delayed(Duration.zero);

      expect(
        (await client.perform(FirstPlayableAuthorityAction.roll)).accepted,
        isTrue,
      );
      expect(transport.lastCommand!['expectedStateVersion'], 4);
      expect(locatorStore.value!.gameId, 'game-1');
    },
  );

  test('composition sends only presetId for CreateRoom', () async {
    final transport = _Transport();
    final client = FirstPlayableAuthorityClient.withTransport(
      transport: transport,
      pendingStore: _PendingStore(),
      sessionLocatorStore: _LocatorStore(),
      commandIds: _Ids(),
      clientInstanceId: 'client-1',
      presetId: 'express',
    );
    addTearDown(client.close);

    await client.perform(FirstPlayableAuthorityAction.createRoom);

    expect(transport.lastCommand!['payload'], <String, Object?>{
      'presetDraft': <String, Object?>{'presetId': 'express'},
    });
    expect(transport.lastCommand, isNot(contains('rulesVersion')));
  });

  test(
    'composition restores context from authenticated public reads',
    () async {
      final transport = _Transport();
      final locatorStore = _LocatorStore();
      final first = FirstPlayableAuthorityClient.withTransport(
        transport: transport,
        pendingStore: _PendingStore(),
        sessionLocatorStore: locatorStore,
        commandIds: _Ids(),
        clientInstanceId: 'client-1',
        presetId: 'synthetic-vp0',
      );
      await first.perform(FirstPlayableAuthorityAction.createRoom);
      await first.perform(FirstPlayableAuthorityAction.setReady);
      await first.perform(FirstPlayableAuthorityAction.startGame);
      await first.close();

      transport.currentGameSnapshot = _gameSnapshot(7);
      final restored = FirstPlayableAuthorityClient.withTransport(
        transport: transport,
        pendingStore: _PendingStore(),
        sessionLocatorStore: locatorStore,
        commandIds: _Ids(),
        clientInstanceId: 'client-1',
        presetId: 'synthetic-vp0',
      );
      addTearDown(restored.close);

      final result = await restored.restore();
      expect(result.accepted, isTrue, reason: result.safeErrorCode);
      await restored.perform(FirstPlayableAuthorityAction.roll);

      expect(transport.lastCommand!['expectedStateVersion'], 7);
      expect(transport.lastCommand!['actorPlayerId'], 'player-1');
    },
  );
}

final class _Transport implements AuthorityWireTransport {
  final StreamController<Map<String, Object?>> gameSnapshots =
      StreamController<Map<String, Object?>>.broadcast(sync: true);
  Map<String, Object?>? lastCommand;
  String? watchedGameId;
  Map<String, Object?> currentGameSnapshot = _gameSnapshot(1);

  @override
  Future<Map<String, Object?>> sendCommand(Map<String, Object?> request) async {
    final command = request['command']! as Map<String, Object?>;
    lastCommand = command;
    final commandId = command['commandId'];
    final type = command['type'];
    return switch (type) {
      'CreateRoom' => <String, Object?>{
        'commandId': commandId,
        'status': 'accepted',
        'versionBefore': 0,
        'versionAfter': 1,
        'publicResult': const <String, Object?>{
          'roomId': 'room-1',
          'roomVersion': 1,
          'actorPlayerId': 'player-1',
        },
      },
      'SetReady' => <String, Object?>{
        'commandId': commandId,
        'status': 'accepted',
        'versionBefore': 1,
        'versionAfter': 2,
        'publicResult': const <String, Object?>{
          'roomId': 'room-1',
          'roomVersion': 2,
        },
      },
      'StartGame' => <String, Object?>{
        'commandId': commandId,
        'status': 'accepted',
        'versionBefore': 2,
        'versionAfter': 3,
        'publicResult': const <String, Object?>{
          'roomId': 'room-1',
          'roomVersion': 3,
          'gameId': 'game-1',
          'stateVersion': 1,
        },
      },
      'RollDice' => <String, Object?>{
        'commandId': commandId,
        'status': 'accepted',
        'versionBefore': command['expectedStateVersion'],
        'versionAfter': (command['expectedStateVersion']! as int) + 1,
        'snapshot': _gameSnapshot(
          (command['expectedStateVersion']! as int) + 1,
        ),
      },
      _ => throw StateError('unexpected command $type'),
    };
  }

  @override
  Future<Map<String, Object?>> reconnect(Map<String, Object?> request) =>
      throw UnimplementedError();

  @override
  Stream<Map<String, Object?>> watchPublicGame(String gameId) async* {
    watchedGameId = gameId;
    yield currentGameSnapshot;
    yield* gameSnapshots.stream;
  }

  @override
  Stream<Map<String, Object?>> watchPublicRoom(String roomId) async* {
    yield <String, Object?>{
      'schemaVersion': 1,
      'roomId': roomId,
      'roomVersion': 2,
      'status': 'open',
      'hostPlayerId': 'player-1',
      'actorPlayerId': 'player-1',
      'presetId': 'synthetic-vp0',
      'rulesVersion': 'synthetic-rules-vp0',
      'members': const <Object?>[
        <String, Object?>{
          'playerId': 'player-1',
          'kind': 'human',
          'ready': true,
        },
      ],
    };
  }
}

final class _LocatorStore implements FirstPlayableSessionLocatorStore {
  FirstPlayableSessionLocator? value;

  @override
  Future<FirstPlayableSessionLocator?> load() async => value;

  @override
  Future<void> save(FirstPlayableSessionLocator locator) async =>
      value = locator;
}

final class _PendingStore implements PendingAuthorityCommandStore {
  AuthorityCommandRequest? value;

  @override
  Future<void> clear(String commandId) async => value = null;

  @override
  Future<AuthorityCommandRequest?> load() async => value;

  @override
  Future<void> save(AuthorityCommandRequest request) async => value = request;
}

final class _Ids implements AuthorityCommandIdSource {
  int next = 0;

  @override
  String nextCommandId() => 'command-${++next}';
}

Map<String, Object?> _gameSnapshot(int version) => <String, Object?>{
  'schemaVersion': 1,
  'stateVersion': version,
  'gameId': 'game-1',
  'roomId': 'room-1',
  'rulesVersion': 'synthetic-rules-vp0',
  'rngVersion': 'hmac_sha256_counter_v1',
  'rngCommitment': List<String>.filled(64, '0').join(),
  'turnState': const <String, Object?>{
    'phase': 'awaitingRoll',
    'currentPlayerId': 'player-1',
  },
};
