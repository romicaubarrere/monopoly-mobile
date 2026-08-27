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
  _Fixture() {
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
    );
  }

  final _Gateway gateway = _Gateway();
  final _PendingStore store = _PendingStore();
  final _Ids ids = _Ids();
  final _Context context = _Context();
  late final AuthorityClientSession session;
  late final ConfirmedFirstPlayableRequestResolver requests;
  late final SessionFirstPlayableAuthorityBinding binding;
}

final class _Context implements FirstPlayableConfirmedContext {
  @override
  void applyCommandReply(
    AuthorityCommandRequest request,
    AuthorityCommandReply reply,
  ) {}

  @override
  String get actorPlayerId => 'player-1';

  @override
  String get auctionId => 'auction-1';

  @override
  String get gameId => 'game-1';

  @override
  String get propertyDecisionId => 'decision-1';

  @override
  String get propertyId => 'property-7';

  @override
  String get roomId => 'room-1';

  @override
  int get roomVersion => 6;

  @override
  int get stateVersion => 12;

  @override
  void replacePublicSnapshot(AuthorityPublicSnapshot snapshot) {}

  @override
  void replacePublicRoomSnapshot(AuthorityPublicRoomSnapshot snapshot) {}
}

final class _Ids implements AuthorityCommandIdSource {
  int _next = 0;

  @override
  String nextCommandId() => 'command-${++_next}';
}

final class _PendingStore implements PendingAuthorityCommandStore {
  AuthorityCommandRequest? value;

  @override
  Future<void> clear(String commandId) async {
    if (value?.commandId == commandId) value = null;
  }

  @override
  Future<AuthorityCommandRequest?> load() async => value;

  @override
  Future<void> save(AuthorityCommandRequest request) async => value = request;
}

final class _Gateway implements CommandGateway, AuthoritySnapshotRepository {
  final List<AuthorityCommandRequest> sent = <AuthorityCommandRequest>[];
  bool reject = false;
  bool failSend = false;
  bool reconnectRejected = false;

  @override
  Future<AuthorityCommandReply> send(AuthorityCommandRequest request) async {
    sent.add(request);
    if (failSend) throw StateError('transport unavailable');
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
