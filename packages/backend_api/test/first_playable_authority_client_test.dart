import 'dart:async';

import 'package:board_backend_api/backend_api.dart';
import 'package:board_game_core/game_core.dart';
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

  test(
    'guest receives host start through room and game snapshot streams',
    () async {
      final transport = _StreamingTransport();
      final locatorStore = _LocatorStore();
      final client = FirstPlayableAuthorityClient.withTransport(
        transport: transport,
        pendingStore: _PendingStore(),
        sessionLocatorStore: locatorStore,
        commandIds: _Ids(),
        clientInstanceId: 'guest-client-1',
        presetId: 'synthetic-vp0',
      );
      var clientClosed = false;
      addTearDown(() async {
        if (!clientClosed) await client.close();
        await transport.close();
      });
      final roomEvents = <AuthorityPublicRoomSnapshot>[];
      final gameEvents = <AuthorityPublicSnapshot>[];
      final roomEventsSubscription = client.roomSnapshots.listen(
        roomEvents.add,
      );
      final gameEventsSubscription = client.gameSnapshots.listen(
        gameEvents.add,
      );
      addTearDown(roomEventsSubscription.cancel);
      addTearDown(gameEventsSubscription.cancel);

      final joined = await client.perform(
        FirstPlayableAuthorityAction.joinRoom,
        input: 'ABC123',
      );

      expect(joined.accepted, isTrue, reason: joined.safeErrorCode);
      expect(transport.watchedRoomId, 'room-1');

      transport.roomSnapshots.add(_roomSnapshot(1));
      expect(client.confirmedRoomSnapshot?.gameId, isNull);
      expect(roomEvents.single.roomVersion, 1);

      transport.roomSnapshots.add(_roomSnapshot(2, gameId: 'game-guest'));
      await Future<void>.delayed(Duration.zero);
      expect(client.confirmedRoomSnapshot?.gameId, 'game-guest');
      expect(transport.watchedGameId, 'game-guest');
      expect(locatorStore.value?.gameId, 'game-guest');

      transport.gameSnapshots.add(_gameSnapshot(0, gameId: 'game-guest'));
      expect(client.confirmedGameSnapshot?.gameId, 'game-guest');
      expect(gameEvents.single.stateVersion, 0);

      await client.close();
      clientClosed = true;
      expect(transport.roomSnapshots.hasListener, isFalse);
      expect(transport.gameSnapshots.hasListener, isFalse);
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

  test(
    'restore ignores a stale device game locator for an open room',
    () async {
      final transport = _Transport();
      final locatorStore = _LocatorStore()
        ..value = FirstPlayableSessionLocator(
          roomId: 'room-1',
          gameId: 'stale-game',
        );
      final client = FirstPlayableAuthorityClient.withTransport(
        transport: transport,
        pendingStore: _PendingStore(),
        sessionLocatorStore: locatorStore,
        commandIds: _Ids(),
        clientInstanceId: 'client-1',
        presetId: 'synthetic-vp0',
      );
      addTearDown(client.close);

      final result = await client.restore();

      expect(result.accepted, isTrue, reason: result.safeErrorCode);
      expect(transport.watchedGameId, isNull);
      expect(locatorStore.value?.roomId, 'room-1');
      expect(locatorStore.value?.gameId, isNull);
    },
  );

  test('failed restore blocks a new mutation before transport', () async {
    final transport = _Transport();
    final client = FirstPlayableAuthorityClient.withTransport(
      transport: transport,
      pendingStore: _PendingStore(),
      sessionLocatorStore: _FailingLocatorStore(),
      commandIds: _Ids(),
      clientInstanceId: 'client-1',
      presetId: 'synthetic-vp0',
    );
    addTearDown(client.close);

    final restored = await client.restore();
    final create = await client.perform(
      FirstPlayableAuthorityAction.createRoom,
    );

    expect(restored.safeErrorCode, 'sessionLocatorCorrupt');
    expect(create.safeErrorCode, 'sessionLocatorCorrupt');
    expect(transport.lastCommand, isNull);
  });

  for (final type in <RoomCommandType>[
    RoomCommandType.createRoom,
    RoomCommandType.joinRoom,
    RoomCommandType.setReady,
  ]) {
    test(
      'restores and explicitly replays an uncertain ${type.wireValue}',
      () async {
        final transport = _PendingRoomRecoveryTransport();
        final store = _PendingStore()..value = _pendingRoomRequest(type);
        final locatorStore = _LocatorStore();
        final client = FirstPlayableAuthorityClient.withTransport(
          transport: transport,
          pendingStore: store,
          sessionLocatorStore: locatorStore,
          commandIds: _Ids(),
          clientInstanceId: 'client-1',
          presetId: 'synthetic-vp0',
        );
        addTearDown(client.close);
        addTearDown(transport.close);

        final restored = await client.restore();

        expect(restored.outcome, FirstPlayableAuthorityOutcome.uncertain);
        expect(restored.safeErrorCode, 'pendingCommandRecoveryRequired');
        expect(client.requiresReconciliation, isTrue);
        expect(transport.commands, isEmpty);

        final replayed = await client.perform(
          FirstPlayableAuthorityAction.reconnect,
        );

        expect(replayed.accepted, isTrue, reason: replayed.safeErrorCode);
        expect(client.requiresReconciliation, isFalse);
        expect(transport.commands, hasLength(1));
        expect(
          transport.commands.single['commandId'],
          store.lastClearedCommandId,
        );
        expect(locatorStore.value?.roomId, 'room-1');
        if (type == RoomCommandType.createRoom) {
          expect(client.latestCreatedRoomCode, 'ABC123');
        }

        await Future<void>.delayed(Duration.zero);
        final later = await client.perform(
          FirstPlayableAuthorityAction.setReady,
        );

        expect(later.accepted, isTrue, reason: later.safeErrorCode);
        expect(transport.commands, hasLength(2));
      },
    );
  }

  test(
    'retains an accepted room identity until its public locator is durable',
    () async {
      final transport = _PendingRoomRecoveryTransport();
      final store = _PendingStore();
      final locatorStore = _LocatorStore()..failSave = true;
      final first = FirstPlayableAuthorityClient.withTransport(
        transport: transport,
        pendingStore: store,
        sessionLocatorStore: locatorStore,
        commandIds: _Ids(),
        clientInstanceId: 'client-1',
        presetId: 'synthetic-vp0',
      );
      addTearDown(transport.close);

      final acceptedBeforeCrash = await first.perform(
        FirstPlayableAuthorityAction.createRoom,
      );

      expect(
        acceptedBeforeCrash.outcome,
        FirstPlayableAuthorityOutcome.blocked,
      );
      expect(
        acceptedBeforeCrash.safeErrorCode,
        'sessionLocatorStoreUnavailable',
      );
      expect(store.value, isNotNull);
      await first.close();

      locatorStore.failSave = false;
      final restored = FirstPlayableAuthorityClient.withTransport(
        transport: transport,
        pendingStore: store,
        sessionLocatorStore: locatorStore,
        commandIds: _Ids(),
        clientInstanceId: 'client-1',
        presetId: 'synthetic-vp0',
      );
      addTearDown(restored.close);

      final recovery = await restored.restore();
      final replayed = await restored.perform(
        FirstPlayableAuthorityAction.reconnect,
      );

      expect(recovery.outcome, FirstPlayableAuthorityOutcome.uncertain);
      expect(replayed.accepted, isTrue, reason: replayed.safeErrorCode);
      expect(store.value, isNull);
      expect(locatorStore.value?.roomId, 'room-1');
      expect(transport.commands, hasLength(2));
      expect(
        transport.commands.first['commandId'],
        transport.commands.last['commandId'],
      );
    },
  );

  test(
    'keeps a durable room command reconcilable when locator restore fails',
    () async {
      final transport = _PendingRoomRecoveryTransport();
      final store = _PendingStore()
        ..value = _pendingRoomRequest(RoomCommandType.createRoom);
      final locatorStore = _LocatorStore()..failLoad = true;
      final client = FirstPlayableAuthorityClient.withTransport(
        transport: transport,
        pendingStore: store,
        sessionLocatorStore: locatorStore,
        commandIds: _Ids(),
        clientInstanceId: 'client-1',
        presetId: 'synthetic-vp0',
      );
      addTearDown(client.close);
      addTearDown(transport.close);

      final restored = await client.restore();

      expect(restored.outcome, FirstPlayableAuthorityOutcome.uncertain);
      expect(restored.safeErrorCode, 'pendingCommandRecoveryRequired');
      expect(client.requiresReconciliation, isTrue);
      expect(locatorStore.loadCalls, 0);
      expect(transport.commands, isEmpty);
    },
  );

  test(
    'availability loss does not latch and reconnect restarts the game watch',
    () async {
      final transport = _Transport();
      final client = FirstPlayableAuthorityClient.withTransport(
        transport: transport,
        pendingStore: _PendingStore(),
        sessionLocatorStore: _LocatorStore(),
        commandIds: _Ids(),
        clientInstanceId: 'client-1',
        presetId: 'synthetic-vp0',
      );
      addTearDown(client.close);

      await client.perform(FirstPlayableAuthorityAction.createRoom);
      await client.perform(FirstPlayableAuthorityAction.setReady);
      final started = await client.perform(
        FirstPlayableAuthorityAction.startGame,
      );
      expect(started.accepted, isTrue, reason: started.safeErrorCode);
      expect(transport.gameWatchCount, 1);

      transport.gameSnapshots.addError(
        const AuthorityTransportException('authorityUnavailable'),
      );
      await Future<void>.delayed(Duration.zero);

      final reconnected = await client.perform(
        FirstPlayableAuthorityAction.reconnect,
      );
      expect(reconnected.accepted, isTrue, reason: reconnected.safeErrorCode);
      expect(transport.gameWatchCount, 2);

      final rolled = await client.perform(FirstPlayableAuthorityAction.roll);
      expect(rolled.accepted, isTrue, reason: rolled.safeErrorCode);
    },
  );

  test(
    'terminal game stream errors are surfaced and block mutations',
    () async {
      final transport = _Transport();
      final client = FirstPlayableAuthorityClient.withTransport(
        transport: transport,
        pendingStore: _PendingStore(),
        sessionLocatorStore: _LocatorStore(),
        commandIds: _Ids(),
        clientInstanceId: 'client-1',
        presetId: 'synthetic-vp0',
      );
      addTearDown(client.close);
      final streamErrors = <Object>[];
      final subscription = client.gameSnapshots.listen(
        (_) {},
        onError: streamErrors.add,
      );
      addTearDown(subscription.cancel);

      await client.perform(FirstPlayableAuthorityAction.createRoom);
      await client.perform(FirstPlayableAuthorityAction.setReady);
      await client.perform(FirstPlayableAuthorityAction.startGame);
      final commandCount = transport.commandCount;
      transport.gameSnapshots.addError(
        const AuthorityTransportException('authenticationRejected'),
      );
      await Future<void>.delayed(Duration.zero);

      final rolled = await client.perform(FirstPlayableAuthorityAction.roll);

      expect(rolled.outcome, FirstPlayableAuthorityOutcome.blocked);
      expect(rolled.safeErrorCode, 'authenticationRejected');
      expect(transport.commandCount, commandCount);
      expect(
        streamErrors.single,
        isA<AuthorityTransportException>().having(
          (error) => error.code,
          'code',
          'authenticationRejected',
        ),
      );
    },
  );

  test('game stream contract failures block later mutations', () async {
    final transport = _Transport();
    final client = FirstPlayableAuthorityClient.withTransport(
      transport: transport,
      pendingStore: _PendingStore(),
      sessionLocatorStore: _LocatorStore(),
      commandIds: _Ids(),
      clientInstanceId: 'client-1',
      presetId: 'synthetic-vp0',
    );
    addTearDown(client.close);

    await client.perform(FirstPlayableAuthorityAction.createRoom);
    await client.perform(FirstPlayableAuthorityAction.setReady);
    await client.perform(FirstPlayableAuthorityAction.startGame);
    transport.gameSnapshots.addError(
      const ClientAuthorityContractViolation('privateMaterialForbidden'),
    );
    await Future<void>.delayed(Duration.zero);

    final rolled = await client.perform(FirstPlayableAuthorityAction.roll);
    expect(rolled.outcome, FirstPlayableAuthorityOutcome.blocked);
    expect(rolled.safeErrorCode, 'privateMaterialForbidden');
  });

  test(
    'room availability loss can be explicitly refreshed without blocking',
    () async {
      final transport = _StreamingTransport();
      final client = FirstPlayableAuthorityClient.withTransport(
        transport: transport,
        pendingStore: _PendingStore(),
        sessionLocatorStore: _LocatorStore(),
        commandIds: _Ids(),
        clientInstanceId: 'guest-client-1',
        presetId: 'synthetic-vp0',
      );
      addTearDown(() async {
        await client.close();
        await transport.close();
      });

      final joined = await client.perform(
        FirstPlayableAuthorityAction.joinRoom,
        input: 'ABC123',
      );
      expect(joined.accepted, isTrue, reason: joined.safeErrorCode);
      expect(transport.roomWatchCount, 1);

      transport.roomSnapshots.addError(
        const AuthorityTransportException('authenticationRejected'),
      );
      await transport.roomSnapshots.close();

      final refreshed = await client.refreshConfirmedRoom();
      expect(refreshed.roomVersion, 2);
      expect(transport.roomWatchCount, 3);

      final ready = await client.perform(FirstPlayableAuthorityAction.setReady);
      expect(ready.accepted, isTrue, reason: ready.safeErrorCode);
    },
  );

  test(
    'a same-version lobby refresh restarts a completed game watch',
    () async {
      final transport = _Transport();
      final client = FirstPlayableAuthorityClient.withTransport(
        transport: transport,
        pendingStore: _PendingStore(),
        sessionLocatorStore: _LocatorStore(),
        commandIds: _Ids(),
        clientInstanceId: 'client-1',
        presetId: 'synthetic-vp0',
      );
      addTearDown(client.close);

      await client.perform(FirstPlayableAuthorityAction.createRoom);
      await client.perform(FirstPlayableAuthorityAction.setReady);
      await client.perform(FirstPlayableAuthorityAction.startGame);
      await client.refreshConfirmedRoom();
      expect(transport.gameWatchCount, 1);
      await transport.gameSnapshots.close();
      await Future<void>.delayed(Duration.zero);
      transport.roomSnapshots.add(_roomSnapshot(3, gameId: 'game-1'));
      await Future<void>.delayed(Duration.zero);
      expect(transport.gameWatchCount, 1);

      final room = await client.refreshConfirmedRoom();

      expect(room.gameId, 'game-1');
      expect(transport.gameWatchCount, 2);
    },
  );

  test('restore bounds a one-shot room read', () async {
    final transport = _HangingRoomTransport();
    final client = FirstPlayableAuthorityClient.withTransport(
      transport: transport,
      pendingStore: _PendingStore(),
      sessionLocatorStore: _LocatorStore()
        ..value = FirstPlayableSessionLocator(roomId: 'room-1'),
      commandIds: _Ids(),
      clientInstanceId: 'client-1',
      presetId: 'synthetic-vp0',
      snapshotReadTimeout: const Duration(milliseconds: 1),
    );
    addTearDown(() async {
      await client.close();
      await transport.close();
    });

    final result = await client.restore();

    expect(result.outcome, FirstPlayableAuthorityOutcome.blocked);
    expect(result.safeErrorCode, 'sessionRestoreUnavailable');
  });
}

final class _Transport implements AuthorityWireTransport {
  final StreamController<Map<String, Object?>> gameSnapshots =
      StreamController<Map<String, Object?>>.broadcast(sync: true);
  final StreamController<Map<String, Object?>> roomSnapshots =
      StreamController<Map<String, Object?>>.broadcast(sync: true);
  Map<String, Object?>? lastCommand;
  int commandCount = 0;
  String? watchedGameId;
  int gameWatchCount = 0;
  Map<String, Object?> currentGameSnapshot = _gameSnapshot(1);
  Map<String, Object?> currentRoomSnapshot = _roomSnapshot(2);

  @override
  Future<Map<String, Object?>> sendCommand(Map<String, Object?> request) async {
    final command = request['command']! as Map<String, Object?>;
    commandCount += 1;
    lastCommand = command;
    final commandId = command['commandId'];
    final type = command['type'];
    if (type == 'StartGame') {
      currentRoomSnapshot = _roomSnapshot(3, gameId: 'game-1');
    }
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
  Future<Map<String, Object?>> reconnect(Map<String, Object?> request) async =>
      <String, Object?>{
        'disposition': 'upToDate',
        'snapshot': _gameSnapshot(request['observedStateVersion']! as int),
      };

  @override
  Stream<Map<String, Object?>> watchPublicGame(String gameId) async* {
    watchedGameId = gameId;
    gameWatchCount += 1;
    yield currentGameSnapshot;
    yield* gameSnapshots.stream;
  }

  @override
  Stream<Map<String, Object?>> watchPublicRoom(String roomId) async* {
    yield currentRoomSnapshot;
    yield* roomSnapshots.stream;
  }
}

final class _StreamingTransport implements AuthorityWireTransport {
  final StreamController<Map<String, Object?>> roomSnapshots =
      StreamController<Map<String, Object?>>.broadcast(sync: true);
  final StreamController<Map<String, Object?>> gameSnapshots =
      StreamController<Map<String, Object?>>.broadcast(sync: true);
  final StreamController<Map<String, Object?>> recoveredRoomSnapshots =
      StreamController<Map<String, Object?>>.broadcast(sync: true);
  String? watchedRoomId;
  String? watchedGameId;
  int roomWatchCount = 0;
  var _firstRoomWatch = true;

  @override
  Future<Map<String, Object?>> sendCommand(Map<String, Object?> request) async {
    final command = request['command']! as Map<String, Object?>;
    return switch (command['type']) {
      'JoinRoom' => <String, Object?>{
        'commandId': command['commandId'],
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
        'commandId': command['commandId'],
        'status': 'accepted',
        'versionBefore': command['expectedRoomVersion'],
        'versionAfter': (command['expectedRoomVersion']! as int) + 1,
        'publicResult': <String, Object?>{
          'roomId': 'room-1',
          'roomVersion': (command['expectedRoomVersion']! as int) + 1,
        },
      },
      _ => throw StateError('unexpected command ${command['type']}'),
    };
  }

  @override
  Future<Map<String, Object?>> reconnect(Map<String, Object?> request) =>
      throw UnimplementedError();

  @override
  Stream<Map<String, Object?>> watchPublicGame(String gameId) {
    watchedGameId = gameId;
    return gameSnapshots.stream;
  }

  @override
  Stream<Map<String, Object?>> watchPublicRoom(String roomId) {
    watchedRoomId = roomId;
    roomWatchCount += 1;
    if (_firstRoomWatch) {
      _firstRoomWatch = false;
      return roomSnapshots.stream;
    }
    return _recoveredRoomWatch();
  }

  Stream<Map<String, Object?>> _recoveredRoomWatch() async* {
    yield _roomSnapshot(2);
    yield* recoveredRoomSnapshots.stream;
  }

  Future<void> close() async {
    await roomSnapshots.close();
    await recoveredRoomSnapshots.close();
    await gameSnapshots.close();
  }
}

final class _HangingRoomTransport implements AuthorityWireTransport {
  final StreamController<Map<String, Object?>> _rooms =
      StreamController<Map<String, Object?>>.broadcast();

  @override
  Future<Map<String, Object?>> reconnect(Map<String, Object?> request) =>
      throw UnimplementedError();

  @override
  Future<Map<String, Object?>> sendCommand(Map<String, Object?> request) =>
      throw UnimplementedError();

  @override
  Stream<Map<String, Object?>> watchPublicGame(String gameId) =>
      const Stream<Map<String, Object?>>.empty();

  @override
  Stream<Map<String, Object?>> watchPublicRoom(String roomId) => _rooms.stream;

  Future<void> close() => _rooms.close();
}

final class _PendingRoomRecoveryTransport implements AuthorityWireTransport {
  final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
  final StreamController<Map<String, Object?>> _roomSnapshots =
      StreamController<Map<String, Object?>>.broadcast(sync: true);
  int _roomVersion = 1;

  @override
  Future<Map<String, Object?>> sendCommand(Map<String, Object?> request) async {
    final command = request['command']! as Map<String, Object?>;
    commands.add(command);
    final type = command['type']! as String;
    final versionBefore = command['expectedRoomVersion'] as int? ?? 0;
    _roomVersion = versionBefore + 1;
    return <String, Object?>{
      'commandId': command['commandId'],
      'status': 'duplicate',
      'versionBefore': versionBefore,
      'versionAfter': _roomVersion,
      'publicResult': <String, Object?>{
        'status': 'accepted',
        'roomId': 'room-1',
        'roomVersion': _roomVersion,
        if (type == 'CreateRoom' || type == 'JoinRoom')
          'actorPlayerId': 'player-1',
        if (type == 'CreateRoom') 'roomCode': 'ABC123',
      },
    };
  }

  @override
  Future<Map<String, Object?>> reconnect(Map<String, Object?> request) =>
      throw StateError('room retry must not use game reconnect');

  @override
  Stream<Map<String, Object?>> watchPublicGame(String gameId) =>
      const Stream<Map<String, Object?>>.empty();

  @override
  Stream<Map<String, Object?>> watchPublicRoom(String roomId) async* {
    yield _roomSnapshot(_roomVersion);
    yield* _roomSnapshots.stream;
  }

  Future<void> close() => _roomSnapshots.close();
}

final class _LocatorStore implements FirstPlayableSessionLocatorStore {
  FirstPlayableSessionLocator? value;
  int loadCalls = 0;
  bool failLoad = false;
  bool failSave = false;

  @override
  Future<FirstPlayableSessionLocator?> load() async {
    loadCalls += 1;
    if (failLoad) throw StateError('device storage unavailable');
    return value;
  }

  @override
  Future<void> save(FirstPlayableSessionLocator locator) async {
    if (failSave) throw StateError('device storage unavailable');
    value = locator;
  }
}

final class _FailingLocatorStore implements FirstPlayableSessionLocatorStore {
  @override
  Future<FirstPlayableSessionLocator?> load() =>
      throw const ClientAuthorityContractViolation('sessionLocatorCorrupt');

  @override
  Future<void> save(FirstPlayableSessionLocator locator) async {}
}

final class _PendingStore implements PendingAuthorityCommandStore {
  AuthorityCommandRequest? value;
  String? lastClearedCommandId;

  @override
  Future<void> clear(String commandId) async {
    lastClearedCommandId = commandId;
    value = null;
  }

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

Map<String, Object?> _roomSnapshot(
  int version, {
  String? gameId,
}) => <String, Object?>{
  'schemaVersion': 1,
  'roomId': 'room-1',
  'roomVersion': version,
  'status': gameId == null ? 'open' : 'active',
  'gameId': ?gameId,
  'hostPlayerId': 'player-1',
  'actorPlayerId': 'player-1',
  'presetId': 'synthetic-vp0',
  'rulesVersion': 'synthetic-rules-vp0',
  'members': const <Object?>[
    <String, Object?>{'playerId': 'player-1', 'kind': 'human', 'ready': true},
  ],
};

Map<String, Object?> _gameSnapshot(int version, {String gameId = 'game-1'}) =>
    <String, Object?>{
      'schemaVersion': 1,
      'stateVersion': version,
      'gameId': gameId,
      'roomId': 'room-1',
      'rulesVersion': 'synthetic-rules-vp0',
      'rngVersion': 'hmac_sha256_counter_v1',
      'rngCommitment': List<String>.filled(64, '0').join(),
      'turnState': const <String, Object?>{
        'phase': 'awaitingRoll',
        'currentPlayerId': 'player-1',
      },
    };

AuthorityCommandRequest _pendingRoomRequest(RoomCommandType type) =>
    AuthorityCommandRequest.room(
      RoomCommand(
        commandId: 'pending-${type.wireValue.toLowerCase()}-1',
        schemaVersion: 1,
        expectedRoomVersion: type == RoomCommandType.setReady ? 1 : null,
        clientInstanceId: 'client-1',
        type: type,
        payload: switch (type) {
          RoomCommandType.createRoom => const <String, Object?>{
            'presetDraft': <String, Object?>{'presetId': 'synthetic-vp0'},
          },
          RoomCommandType.joinRoom => const <String, Object?>{
            'roomCode': 'ABC123',
          },
          RoomCommandType.setReady => const <String, Object?>{
            'roomId': 'room-1',
            'ready': true,
          },
          _ => throw ArgumentError.value(type, 'type', 'unsupported fixture'),
        },
      ),
    );
