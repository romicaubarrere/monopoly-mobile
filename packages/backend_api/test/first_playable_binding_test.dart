import 'dart:async';

import 'package:board_backend_api/backend_api.dart';
import 'package:test/test.dart';

void main() {
  test('binding advances only after accepted Authority ACK', () async {
    final fixture = _Fixture();

    final result = await fixture.binding.perform(
      FirstPlayableAuthorityAction.setReady,
    );

    expect(result.outcome, FirstPlayableAuthorityOutcome.accepted);
    expect(fixture.gateway.sent, hasLength(1));
    expect(fixture.gateway.sent.single.command['type'], 'SetReady');
    expect(fixture.gateway.sent.single.command['expectedRoomVersion'], 6);
    expect(fixture.store.value, isNull);
  });

  test('Start refreshes authoritative room version before sending', () async {
    final fixture = _Fixture()..gateway.roomSnapshotVersion = 9;

    final result = await fixture.binding.perform(
      FirstPlayableAuthorityAction.startGame,
    );

    expect(result.outcome, FirstPlayableAuthorityOutcome.accepted);
    expect(fixture.gateway.roomReads, 1);
    expect(fixture.gateway.sent.single.command['expectedRoomVersion'], 9);
  });

  test(
    'Start blocks before transport when lobby snapshot is unavailable',
    () async {
      final fixture = _Fixture()..gateway.failRoomSnapshot = true;

      final result = await fixture.binding.perform(
        FirstPlayableAuthorityAction.startGame,
      );

      expect(result.outcome, FirstPlayableAuthorityOutcome.blocked);
      expect(result.safeErrorCode, 'roomSnapshotUnavailable');
      expect(fixture.gateway.sent, isEmpty);
    },
  );

  test('Start bounds a retrying room read before command transport', () async {
    final fixture = _Fixture(
      roomSnapshotReadTimeout: const Duration(milliseconds: 1),
    )..gateway.hangRoomSnapshot = true;
    addTearDown(fixture.close);

    final result = await fixture.binding.perform(
      FirstPlayableAuthorityAction.startGame,
    );

    expect(result.outcome, FirstPlayableAuthorityOutcome.blocked);
    expect(result.safeErrorCode, 'roomSnapshotUnavailable');
    expect(fixture.gateway.sent, isEmpty);
  });

  test(
    'binding exposes safe rejection without optimistic acceptance',
    () async {
      final fixture = _Fixture()..gateway.reject = true;

      final result = await fixture.binding.perform(
        FirstPlayableAuthorityAction.roll,
      );

      expect(result.outcome, FirstPlayableAuthorityOutcome.rejected);
      expect(result.safeErrorCode, 'notActivePlayer');
      expect(fixture.session.state.snapshot, isNull);
    },
  );

  test('transport loss remains uncertain and retains exact request', () async {
    final fixture = _Fixture()..gateway.failSend = true;

    final result = await fixture.binding.perform(
      FirstPlayableAuthorityAction.declineProperty,
    );

    expect(result.outcome, FirstPlayableAuthorityOutcome.uncertain);
    expect(result.safeErrorCode, 'commandOutcomeUncertain');
    expect(fixture.store.value, same(fixture.gateway.sent.single));
  });

  test('durable rejected reconnect remains visibly rejected', () async {
    final fixture = _Fixture()..gateway.failSend = true;
    await fixture.binding.perform(FirstPlayableAuthorityAction.roll);
    fixture.gateway.failSend = false;
    fixture.gateway.reconnectRejected = true;

    final result = await fixture.binding.perform(
      FirstPlayableAuthorityAction.reconnect,
    );

    expect(result.outcome, FirstPlayableAuthorityOutcome.rejected);
    expect(result.safeErrorCode, 'durableCommandRejected');
    expect(fixture.store.value, isNull);
  });

  test(
    'reconnect retries an uncertain room command without a game id',
    () async {
      final fixture = _Fixture()
        ..gateway.failSend = true
        ..context.gameAvailable = false;
      final first = await fixture.binding.perform(
        FirstPlayableAuthorityAction.setReady,
      );
      fixture.gateway.failSend = false;

      final retried = await fixture.binding.perform(
        FirstPlayableAuthorityAction.reconnect,
      );

      expect(first.outcome, FirstPlayableAuthorityOutcome.uncertain);
      expect(retried.outcome, FirstPlayableAuthorityOutcome.accepted);
      expect(fixture.gateway.reconnects, 0);
      expect(fixture.gateway.sent, hasLength(2));
      expect(fixture.gateway.sent.first, same(fixture.gateway.sent.last));
      expect(fixture.store.value, isNull);
    },
  );

  test(
    'room replay keeps a durable duplicate rejection visibly rejected',
    () async {
      final fixture = _Fixture()
        ..gateway.failSend = true
        ..context.gameAvailable = false;
      final first = await fixture.binding.perform(
        FirstPlayableAuthorityAction.setReady,
      );
      fixture.gateway
        ..failSend = false
        ..replayRejected = true;

      final replayed = await fixture.binding.perform(
        FirstPlayableAuthorityAction.reconnect,
      );

      expect(first.outcome, FirstPlayableAuthorityOutcome.uncertain);
      expect(replayed.outcome, FirstPlayableAuthorityOutcome.rejected);
      expect(replayed.safeErrorCode, 'staleVersion');
      expect(fixture.context.applyCalls, 0);
      expect(fixture.store.value, isNull);
    },
  );

  test('pending store fault blocks reconnect without transport', () async {
    final fixture = _Fixture()..store.failLoad = true;

    final result = await fixture.binding.perform(
      FirstPlayableAuthorityAction.reconnect,
    );

    expect(result.outcome, FirstPlayableAuthorityOutcome.blocked);
    expect(result.safeErrorCode, 'pendingCommandStoreUnavailable');
    expect(fixture.gateway.reconnects, 0);
  });

  test('resolver uses confirmed decision and auction identifiers', () {
    final fixture = _Fixture();

    final buy = fixture.requests.commandFor(
      FirstPlayableAuthorityAction.buyProperty,
    );
    final bid = fixture.requests.commandFor(
      FirstPlayableAuthorityAction.placeBid,
      input: '240',
    );

    expect(buy.command['expectedStateVersion'], 12);
    expect(buy.command['payload'], <String, Object?>{
      'decisionId': 'decision-1',
      'propertyId': 'property-7',
    });
    expect(bid.command['payload'], <String, Object?>{
      'amount': 240,
      'auctionId': 'auction-1',
    });
  });

  test('invalid presentation input is blocked before transport', () async {
    final fixture = _Fixture();

    final result = await fixture.binding.perform(
      FirstPlayableAuthorityAction.placeBid,
      input: 'not-an-integer',
    );

    expect(result.outcome, FirstPlayableAuthorityOutcome.blocked);
    expect(result.safeErrorCode, 'invalidBidAmount');
    expect(fixture.gateway.sent, isEmpty);
  });
}

final class _Fixture {
  _Fixture({Duration roomSnapshotReadTimeout = const Duration(seconds: 10)}) {
    session = AuthorityClientSession(
      gateway: gateway,
      snapshots: gateway,
      pendingStore: store,
    );
    requests = ConfirmedFirstPlayableRequestResolver(
      commands: FirstPlayableAuthorityCommands(
        clientInstanceId: 'client-1',
        commandIds: ids,
      ),
      context: context,
      createRoomPresetDraft: const <String, Object?>{
        'presetId': 'synthetic-vp0',
      },
    );
    binding = SessionFirstPlayableAuthorityBinding(
      session: session,
      requests: requests,
      roomSnapshots: gateway,
      roomSnapshotReadTimeout: roomSnapshotReadTimeout,
    );
  }

  final _Gateway gateway = _Gateway();
  final _PendingStore store = _PendingStore();
  final _Ids ids = _Ids();
  final _Context context = _Context();
  late final AuthorityClientSession session;
  late final ConfirmedFirstPlayableRequestResolver requests;
  late final SessionFirstPlayableAuthorityBinding binding;

  Future<void> close() async {
    await session.close();
    await gateway.close();
  }
}

final class _Context implements FirstPlayableConfirmedContext {
  int _roomVersion = 6;
  bool gameAvailable = true;
  int applyCalls = 0;

  @override
  void applyCommandReply(
    AuthorityCommandRequest request,
    AuthorityCommandReply reply,
  ) {
    applyCalls += 1;
  }

  @override
  String get actorPlayerId => 'player-1';

  @override
  String get auctionId => 'auction-1';

  @override
  String get gameId {
    if (!gameAvailable) {
      throw const ClientAuthorityContractViolation('confirmedGameUnavailable');
    }
    return 'game-1';
  }

  @override
  String get propertyDecisionId => 'decision-1';

  @override
  String get propertyId => 'property-7';

  @override
  String get roomId => 'room-1';

  @override
  int get roomVersion => _roomVersion;

  @override
  int get stateVersion => 12;

  @override
  void replacePublicSnapshot(AuthorityPublicSnapshot snapshot) {}

  @override
  void replacePublicRoomSnapshot(AuthorityPublicRoomSnapshot snapshot) {
    _roomVersion = snapshot.roomVersion;
  }
}

final class _Ids implements AuthorityCommandIdSource {
  int _next = 0;

  @override
  String nextCommandId() => 'command-${++_next}';
}

final class _PendingStore implements PendingAuthorityCommandStore {
  AuthorityCommandRequest? value;
  bool failLoad = false;

  @override
  Future<void> clear(String commandId) async {
    if (value?.commandId == commandId) value = null;
  }

  @override
  Future<AuthorityCommandRequest?> load() async {
    if (failLoad) throw StateError('device storage unavailable');
    return value;
  }

  @override
  Future<void> save(AuthorityCommandRequest request) async => value = request;
}

final class _Gateway
    implements
        CommandGateway,
        AuthoritySnapshotRepository,
        AuthorityRoomSnapshotRepository {
  final List<AuthorityCommandRequest> sent = <AuthorityCommandRequest>[];
  bool reject = false;
  bool failSend = false;
  bool replayRejected = false;
  bool reconnectRejected = false;
  bool failRoomSnapshot = false;
  bool hangRoomSnapshot = false;
  int roomSnapshotVersion = 6;
  int roomReads = 0;
  int reconnects = 0;
  final StreamController<AuthorityPublicRoomSnapshot> _hangingRoomSnapshots =
      StreamController<AuthorityPublicRoomSnapshot>.broadcast();

  @override
  Future<AuthorityCommandReply> send(AuthorityCommandRequest request) async {
    sent.add(request);
    if (failSend) throw StateError('transport unavailable');
    if (replayRejected) {
      final expected =
          (request.command['expectedStateVersion'] ??
                  request.command['expectedRoomVersion'] ??
                  0)
              as int;
      return AuthorityCommandReply(
        commandId: request.commandId,
        status: AuthorityCommandStatus.duplicate,
        versionBefore: expected,
        versionAfter: expected,
        errorCode: 'staleVersion',
        publicResult: <String, Object?>{
          'commandId': request.commandId,
          'status': 'rejected',
          'stateVersionBefore': expected,
          'stateVersionAfter': expected,
          'errorCode': 'staleVersion',
        },
      );
    }
    if (reject) {
      return AuthorityCommandReply(
        commandId: request.commandId,
        status: AuthorityCommandStatus.rejected,
        versionBefore: 12,
        versionAfter: 12,
        errorCode: 'notActivePlayer',
      );
    }
    final expected =
        (request.command['expectedStateVersion'] ??
                request.command['expectedRoomVersion'] ??
                0)
            as int;
    return AuthorityCommandReply(
      commandId: request.commandId,
      status: AuthorityCommandStatus.accepted,
      versionBefore: expected,
      versionAfter: expected + 1,
    );
  }

  @override
  Future<AuthorityReconnectReply> reconnect(
    AuthorityReconnectRequest request,
  ) async {
    reconnects += 1;
    final pending = request.uncertainCommand!;
    return AuthorityReconnectReply(
      disposition: reconnectRejected
          ? ReconnectDisposition.uncertainRejected
          : ReconnectDisposition.uncertainConfirmed,
      snapshot: _snapshot(12),
      commandResolution: ReconnectCommandResolution(
        identity: pending,
        action: CommandResolutionAction.useDurableResult,
        publicResult: <String, Object?>{
          'status': reconnectRejected ? 'rejected' : 'accepted',
        },
      ),
    );
  }

  @override
  Stream<AuthorityPublicSnapshot> watchGame(String gameId) =>
      const Stream<AuthorityPublicSnapshot>.empty();

  @override
  Stream<AuthorityPublicRoomSnapshot> watchRoom(String roomId) {
    roomReads += 1;
    if (failRoomSnapshot) {
      return Stream<AuthorityPublicRoomSnapshot>.error(
        StateError('snapshot unavailable'),
      );
    }
    if (hangRoomSnapshot) return _hangingRoomSnapshots.stream;
    return Stream<AuthorityPublicRoomSnapshot>.value(
      AuthorityPublicRoomSnapshot(<String, Object?>{
        'schemaVersion': 1,
        'roomId': roomId,
        'roomVersion': roomSnapshotVersion,
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
      }),
    );
  }

  Future<void> close() => _hangingRoomSnapshots.close();
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
