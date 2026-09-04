import 'dart:async';

import 'package:board_backend_api/backend_api.dart';
import 'package:board_game_contracts/game_contracts.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  test('marks command uncertain before send and clears after ACK', () async {
    final store = _PendingStore();
    final backend = _Backend();
    final session = AuthorityClientSession(
      gateway: backend,
      snapshots: backend,
      pendingStore: store,
    );
    final request = _request();

    final reply = await session.send(request);

    expect(backend.pendingObservedAtSend, same(request));
    expect(store.value, isNull);
    expect(reply!.snapshot!.stateVersion, 2);
    expect(session.state.status, AuthoritySessionStatus.confirmed);
    await session.close();
  });

  test('deferred acknowledgement preserves a newer watched snapshot', () async {
    final pendingClear = Completer<void>();
    final snapshots = StreamController<AuthorityPublicSnapshot>(sync: true);
    final store = _PendingStore()..clearCompleter = pendingClear;
    final backend = _Backend()..gameSnapshots = snapshots.stream;
    final session = AuthorityClientSession(
      gateway: backend,
      snapshots: backend,
      pendingStore: store,
      deferAcceptedPendingClear: true,
    );
    session.watch('game-1');

    final reply = await session.send(_request());
    final acknowledgement = session.acknowledgeConfirmedPendingCommand();
    snapshots.add(_snapshot(reply!.snapshot!.stateVersion + 1));
    pendingClear.complete();

    expect(await acknowledgement, isTrue);
    expect(session.state.snapshot?.stateVersion, 3);
    expect(session.state.pendingCommand, isNull);
    await session.close();
    await snapshots.close();
  });

  test('lost ACK keeps exact request and reconnect retries it', () async {
    final store = _PendingStore();
    final backend = _Backend()..loseFirstAck = true;
    final session = AuthorityClientSession(
      gateway: backend,
      snapshots: backend,
      pendingStore: store,
    );
    final request = _request();

    expect(await session.send(request), isNull);
    expect(session.state.status, AuthoritySessionStatus.uncertain);
    expect(store.value, same(request));

    await session.reconnect('game-1');

    expect(backend.sent, hasLength(2));
    expect(backend.sent.first, same(backend.sent.last));
    expect(store.value, isNull);
    expect(session.state.status, AuthoritySessionStatus.confirmed);
    await session.close();
  });

  test('different command is blocked while outcome is uncertain', () async {
    final store = _PendingStore();
    final backend = _Backend()..alwaysFail = true;
    final session = AuthorityClientSession(
      gateway: backend,
      snapshots: backend,
      pendingStore: store,
    );
    await session.send(_request());

    final replacement = _request(commandId: 'cmd-replacement');
    expect(await session.send(replacement), isNull);
    expect(session.state.status, AuthoritySessionStatus.blocked);
    expect(session.state.safeErrorCode, 'uncertainCommandPending');
    expect(backend.sent, hasLength(1));
    await session.close();
  });

  test(
    'replays exact uncertain room command without a game reconnect',
    () async {
      final store = _PendingStore();
      final backend = _Backend()..loseFirstAck = true;
      final session = AuthorityClientSession(
        gateway: backend,
        snapshots: backend,
        pendingStore: store,
      );
      final request = AuthorityCommandRequest.room(
        RoomCommand(
          commandId: 'cmd-ready-1',
          schemaVersion: 1,
          expectedRoomVersion: 1,
          clientInstanceId: 'client-1',
          type: RoomCommandType.setReady,
          payload: const <String, Object?>{'roomId': 'room-1', 'ready': true},
        ),
      );

      expect(await session.send(request), isNull);
      final retry = await session.retryPendingCommand();

      expect(retry!.request, same(request));
      expect(retry.reply, isNotNull);
      expect(backend.sent, hasLength(2));
      expect(backend.sent.first, same(backend.sent.last));
      expect(store.value, isNull);
      expect(session.state.status, AuthoritySessionStatus.confirmed);
      await session.close();
    },
  );

  for (final type in <RoomCommandType>[
    RoomCommandType.createRoom,
    RoomCommandType.joinRoom,
  ]) {
    test(
      'replays an uncertain ${type.wireValue} with its exact identity',
      () async {
        final store = _PendingStore();
        final backend = _Backend()..loseFirstAck = true;
        final session = AuthorityClientSession(
          gateway: backend,
          snapshots: backend,
          pendingStore: store,
        );
        final request = _roomRequest(type);

        expect(await session.send(request), isNull);
        final retry = await session.retryPendingCommand();

        expect(retry?.request, same(request));
        expect(backend.sent, hasLength(2));
        expect(backend.sent.first, same(backend.sent.last));
        expect(store.value, isNull);
        await session.close();
      },
    );
  }

  for (final type in <RoomCommandType>[
    RoomCommandType.createRoom,
    RoomCommandType.joinRoom,
    RoomCommandType.setReady,
  ]) {
    test(
      'replays a durable ${type.wireValue} rejection after its ACK is lost',
      () async {
        final store = _PendingStore();
        final backend = _Backend()..loseDurableRejectedAck = true;
        final session = AuthorityClientSession(
          gateway: backend,
          snapshots: backend,
          pendingStore: store,
        );
        final request = _roomRequest(type);

        expect(await session.send(request), isNull);
        expect(session.state.status, AuthoritySessionStatus.uncertain);

        final retry = await session.retryPendingCommand();

        expect(retry?.request, same(request));
        expect(retry?.reply?.status, AuthorityCommandStatus.duplicate);
        expect(retry?.reply?.isRejectedOutcome, isTrue);
        expect(backend.sent, hasLength(2));
        expect(backend.sent.first, same(backend.sent.last));
        expect(store.value, isNull);
        expect(session.state.status, AuthoritySessionStatus.rejected);
        expect(session.state.safeErrorCode, 'staleVersion');
        await session.close();
      },
    );
  }

  test('does not replay a contract-blocked durable room command', () async {
    final store = _PendingStore();
    final backend = _Backend()..replyWithWrongCommandId = true;
    final session = AuthorityClientSession(
      gateway: backend,
      snapshots: backend,
      pendingStore: store,
    );
    final request = _roomRequest(RoomCommandType.setReady);

    expect(await session.send(request), isNull);
    expect(session.state.safeErrorCode, 'replyCommandMismatch');

    expect(await session.retryPendingCommand(), isNull);
    expect(backend.sent, hasLength(1));
    expect(store.value, same(request));
    expect(session.state.safeErrorCode, 'replyCommandMismatch');
    await session.close();
  });

  test(
    'does not use the room retry path for an uncertain game command',
    () async {
      final store = _PendingStore();
      final backend = _Backend()..loseFirstAck = true;
      final session = AuthorityClientSession(
        gateway: backend,
        snapshots: backend,
        pendingStore: store,
      );
      final request = _request();

      expect(await session.send(request), isNull);
      expect(await session.retryPendingCommand(), isNull);
      expect(backend.sent, hasLength(1));
      expect(
        session.state.safeErrorCode,
        'pendingCommandRequiresGameReconnect',
      );
      expect(store.value, same(request));
      await session.close();
    },
  );

  test('pending store read failure blocks before command transport', () async {
    final store = _PendingStore()..failLoad = true;
    final backend = _Backend();
    final session = AuthorityClientSession(
      gateway: backend,
      snapshots: backend,
      pendingStore: store,
    );

    expect(await session.send(_request()), isNull);
    expect(session.state.status, AuthoritySessionStatus.blocked);
    expect(session.state.safeErrorCode, 'pendingCommandStoreUnavailable');
    expect(backend.sent, isEmpty);
    await session.close();
  });

  test('pending store write failure blocks before command transport', () async {
    final store = _PendingStore()..failSave = true;
    final backend = _Backend();
    final session = AuthorityClientSession(
      gateway: backend,
      snapshots: backend,
      pendingStore: store,
    );

    expect(await session.send(_request()), isNull);
    expect(session.state.status, AuthoritySessionStatus.blocked);
    expect(session.state.safeErrorCode, 'pendingCommandStoreUnavailable');
    expect(backend.sent, isEmpty);
    await session.close();
  });

  test('corrupt pending command blocks reconnect before transport', () async {
    final store = _PendingStore()..corruptLoad = true;
    final backend = _Backend();
    final session = AuthorityClientSession(
      gateway: backend,
      snapshots: backend,
      pendingStore: store,
    );

    expect(await session.reconnect('game-1'), isNull);
    expect(session.state.status, AuthoritySessionStatus.blocked);
    expect(session.state.safeErrorCode, 'pendingCommandCorrupt');
    expect(backend.reconnects, 0);
    await session.close();
  });

  test('contract failure from reconnect fails closed', () async {
    final store = _PendingStore();
    final backend = _Backend()..reconnectContractViolation = true;
    final session = AuthorityClientSession(
      gateway: backend,
      snapshots: backend,
      pendingStore: store,
    );

    expect(await session.reconnect('game-1'), isNull);
    expect(session.state.status, AuthoritySessionStatus.blocked);
    expect(session.state.safeErrorCode, 'invalidReconnectPayload');
    expect(backend.reconnects, 1);
    await session.close();
  });

  test('canonical JSON store survives process replacement exactly', () async {
    String? durableValue;
    final store = JsonPendingAuthorityCommandStore(
      read: () async => durableValue,
      write: (value) async => durableValue = value,
    );
    final request = _request();

    await store.save(request);
    final restored = await store.load();

    expect(durableValue, request.toCanonicalWireJson());
    expect(restored!.toCanonicalWireJson(), request.toCanonicalWireJson());
    expect(restored.uncertainIdentity.inputHash, request.inputHash);
    await store.clear(request.commandId);
    expect(durableValue, isNull);
  });

  test('canonical JSON store fails closed on corrupt persisted data', () async {
    var durableValue = '{"family":"game"}';
    final store = JsonPendingAuthorityCommandStore(
      read: () async => durableValue,
      write: (value) async => durableValue = value ?? '',
    );

    expect(
      store.load(),
      throwsA(
        isA<ClientAuthorityContractViolation>().having(
          (error) => error.code,
          'code',
          'pendingCommandCorrupt',
        ),
      ),
    );
  });

  test('canonical JSON store cannot clear a different command', () async {
    String? durableValue;
    final store = JsonPendingAuthorityCommandStore(
      read: () async => durableValue,
      write: (value) async => durableValue = value,
    );
    final request = _request();
    await store.save(request);

    expect(
      store.clear('cmd-other'),
      throwsA(
        isA<ClientAuthorityContractViolation>().having(
          (error) => error.code,
          'code',
          'pendingCommandClearMismatch',
        ),
      ),
    );
    expect(durableValue, request.toCanonicalWireJson());
  });

  test('contract failure from a game stream fails closed', () async {
    final snapshots = StreamController<AuthorityPublicSnapshot>(sync: true);
    final backend = _Backend()..gameSnapshots = snapshots.stream;
    final session = AuthorityClientSession(
      gateway: backend,
      snapshots: backend,
      pendingStore: _PendingStore(),
    );
    addTearDown(() async {
      await session.close();
      await snapshots.close();
    });
    final terminations = <Object?>[];

    session.watch('game-1', onTerminated: terminations.add);
    snapshots.add(_snapshot(1));
    snapshots.addError(
      const ClientAuthorityContractViolation('privateMaterialForbidden'),
    );
    snapshots.add(_snapshot(2));
    await snapshots.close();

    expect(session.state.status, AuthoritySessionStatus.blocked);
    expect(session.state.safeErrorCode, 'privateMaterialForbidden');
    expect(session.state.snapshot?.stateVersion, 1);
    expect(
      terminations,
      hasLength(1),
      reason: 'a stream error followed by done terminates one watch once',
    );
    expect(
      terminations.single,
      isA<ClientAuthorityContractViolation>().having(
        (error) => error.code,
        'code',
        'privateMaterialForbidden',
      ),
    );
  });

  test('a completed game stream reports a restartable watch', () async {
    final snapshots = StreamController<AuthorityPublicSnapshot>(sync: true);
    final backend = _Backend()..gameSnapshots = snapshots.stream;
    final session = AuthorityClientSession(
      gateway: backend,
      snapshots: backend,
      pendingStore: _PendingStore(),
    );
    addTearDown(() async {
      await session.close();
      await snapshots.close();
    });
    final terminations = <Object?>[];

    session.watch('game-1', onTerminated: terminations.add);
    snapshots.add(_snapshot(1));
    await snapshots.close();

    expect(session.state.status, AuthoritySessionStatus.confirmed);
    expect(terminations, <Object?>[null]);
  });
}

AuthorityCommandRequest _request({String commandId = 'cmd-roll-1'}) =>
    AuthorityCommandRequest.game(
      GameCommand(
        commandId: commandId,
        schemaVersion: 1,
        expectedStateVersion: 1,
        clientInstanceId: 'client-1',
        gameId: 'game-1',
        actorPlayerId: 'player-1',
        type: GameCommandType.rollDice,
        payload: const <String, Object?>{},
      ),
    );

AuthorityCommandRequest _roomRequest(RoomCommandType type) =>
    AuthorityCommandRequest.room(
      RoomCommand(
        commandId: 'cmd-${type.wireValue.toLowerCase()}-1',
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

final class _PendingStore implements PendingAuthorityCommandStore {
  AuthorityCommandRequest? value;
  Completer<void>? clearCompleter;
  bool failLoad = false;
  bool failSave = false;
  bool corruptLoad = false;

  @override
  Future<void> save(AuthorityCommandRequest request) async {
    if (failSave) throw StateError('device storage unavailable');
    value = request;
  }

  @override
  Future<AuthorityCommandRequest?> load() async {
    if (corruptLoad) {
      throw const ClientAuthorityContractViolation('pendingCommandCorrupt');
    }
    if (failLoad) throw StateError('device storage unavailable');
    return value;
  }

  @override
  Future<void> clear(String commandId) async {
    final pendingClear = clearCompleter;
    if (pendingClear != null) await pendingClear.future;
    if (value?.commandId == commandId) value = null;
  }
}

final class _Backend implements CommandGateway, AuthoritySnapshotRepository {
  final List<AuthorityCommandRequest> sent = <AuthorityCommandRequest>[];
  bool loseFirstAck = false;
  bool loseDurableRejectedAck = false;
  bool alwaysFail = false;
  bool replyWithWrongCommandId = false;
  bool reconnectContractViolation = false;
  int reconnects = 0;
  AuthorityCommandRequest? pendingObservedAtSend;
  Stream<AuthorityPublicSnapshot> gameSnapshots =
      const Stream<AuthorityPublicSnapshot>.empty();

  @override
  Future<AuthorityCommandReply> send(AuthorityCommandRequest request) async {
    sent.add(request);
    pendingObservedAtSend = request;
    if (alwaysFail || loseFirstAck && sent.length == 1) {
      throw StateError('transport disconnected');
    }
    if (loseDurableRejectedAck) {
      if (sent.length == 1) throw StateError('transport disconnected');
      return AuthorityCommandReply(
        commandId: request.commandId,
        status: AuthorityCommandStatus.duplicate,
        versionBefore: 1,
        versionAfter: 1,
        errorCode: 'staleVersion',
        publicResult: <String, Object?>{
          'commandId': request.commandId,
          'status': 'rejected',
          'stateVersionBefore': 1,
          'stateVersionAfter': 1,
          'errorCode': 'staleVersion',
        },
      );
    }
    return AuthorityCommandReply(
      commandId: replyWithWrongCommandId ? 'cmd-different' : request.commandId,
      status: AuthorityCommandStatus.accepted,
      versionBefore: 1,
      versionAfter: 2,
      snapshot: _snapshot(2),
    );
  }

  @override
  Future<AuthorityReconnectReply> reconnect(
    AuthorityReconnectRequest request,
  ) async {
    reconnects += 1;
    if (reconnectContractViolation) {
      throw const ClientAuthorityContractViolation('invalidReconnectPayload');
    }
    return AuthorityReconnectReply(
      disposition: ReconnectDisposition.retrySameCommand,
      snapshot: _snapshot(1),
      commandResolution: ReconnectCommandResolution(
        identity: request.uncertainCommand!,
        action: CommandResolutionAction.retrySameCommand,
      ),
    );
  }

  @override
  Stream<AuthorityPublicSnapshot> watchGame(String gameId) => gameSnapshots;
}

AuthorityPublicSnapshot _snapshot(int version) =>
    AuthorityPublicSnapshot(<String, Object?>{
      'schemaVersion': 1,
      'stateVersion': version,
      'gameId': 'game-1',
      'rulesVersion': 'synthetic-rules-vp0',
      'rngVersion': 'hmac_sha256_counter_v1',
      'rngCommitment': List<String>.filled(64, '0').join(),
    });
