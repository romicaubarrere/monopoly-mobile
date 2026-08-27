import 'dart:async';

import 'package:board_backend_api/backend_api.dart';
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

final class _PendingStore implements PendingAuthorityCommandStore {
  AuthorityCommandRequest? value;

  @override
  Future<void> save(AuthorityCommandRequest request) async => value = request;

  @override
  Future<AuthorityCommandRequest?> load() async => value;

  @override
  Future<void> clear(String commandId) async {
    if (value?.commandId == commandId) value = null;
  }
}

final class _Backend implements CommandGateway, AuthoritySnapshotRepository {
  final List<AuthorityCommandRequest> sent = <AuthorityCommandRequest>[];
  bool loseFirstAck = false;
  bool alwaysFail = false;
  AuthorityCommandRequest? pendingObservedAtSend;

  @override
  Future<AuthorityCommandReply> send(AuthorityCommandRequest request) async {
    sent.add(request);
    pendingObservedAtSend = request;
    if (alwaysFail || loseFirstAck && sent.length == 1) {
      throw StateError('transport disconnected');
    }
    return AuthorityCommandReply(
      commandId: request.commandId,
      status: AuthorityCommandStatus.accepted,
      versionBefore: 1,
      versionAfter: 2,
      snapshot: _snapshot(2),
    );
  }

  @override
  Future<AuthorityReconnectReply> reconnect(
    AuthorityReconnectRequest request,
  ) async => AuthorityReconnectReply(
    disposition: ReconnectDisposition.retrySameCommand,
    snapshot: _snapshot(1),
    commandResolution: ReconnectCommandResolution(
      identity: request.uncertainCommand!,
      action: CommandResolutionAction.retrySameCommand,
    ),
  );

  @override
  Stream<AuthorityPublicSnapshot> watchGame(String gameId) =>
      const Stream<AuthorityPublicSnapshot>.empty();
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
