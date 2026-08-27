import 'dart:convert';
import 'dart:io';

import 'package:board_backend_api/backend_api.dart';
import 'package:board_command_service/command_service.dart';
import 'package:board_command_service/observability/authority_observability.dart';
import 'package:board_game_contracts/game_contracts.dart';
import 'package:board_game_core/game_core.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'support/synthetic_roll_fixture.dart';

void main() {
  final authHost = Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'];
  final firestoreHost = Platform.environment['FIRESTORE_EMULATOR_HOST'];
  final projectId =
      Platform.environment['GCLOUD_PROJECT'] ?? 'demo-board-game-local';
  final skipReason = authHost == null || firestoreHost == null
      ? 'requires Firebase Auth and Firestore Emulators'
      : false;

  test(
    'Flutter wire crosses Auth, HTTP, Authority and Firestore for VP0',
    () async {
      final hostToken = await _anonymousIdToken(authHost!);
      final guestToken = await _anonymousIdToken(authHost);
      final outsiderToken = await _anonymousIdToken(authHost);
      final store = FirstPlayableFirestoreRestStore(
        config: FirstPlayableFirestoreRestConfig.emulator(
          projectId: projectId,
          host: firestoreHost!,
        ),
      );
      final runtime = FirstPlayableAuthorityRuntime(
        identityVerifier: FirebaseAuthEmulatorIdentityVerifier(
          projectId: projectId,
          emulatorHost: authHost,
        ),
        store: store,
        rulesCatalogRepository: PinnedFirstPlayableRulesCatalogRepository(
          activeRulesVersion: syntheticRollCatalog().rulesVersion,
          catalogs: <RulesCatalog>[syntheticRollCatalog()],
        ),
        observability: BestEffortAuthorityObservability(_DiscardLogs()),
        roomEntryMaterialFactory: _roomEntryMaterial,
        startMaterialFactory: _startMaterial,
        now: () => DateTime.utc(2026, 8, 27, 5),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(runtime.handle);
      final baseUri = Uri.parse('http://127.0.0.1:${server.port}');
      final hostTransport = HttpAuthorityWireTransport(
        baseUri: baseUri,
        idTokenProvider: () async => hostToken,
      );
      final guestTransport = HttpAuthorityWireTransport(
        baseUri: baseUri,
        idTokenProvider: () async => guestToken,
      );
      final outsiderTransport = HttpAuthorityWireTransport(
        baseUri: baseUri,
        idTokenProvider: () async => outsiderToken,
      );
      addTearDown(() async {
        hostTransport.close(force: true);
        guestTransport.close(force: true);
        outsiderTransport.close(force: true);
        await server.close(force: true);
      });
      final host = WireAuthorityClient(hostTransport);
      final guest = WireAuthorityClient(guestTransport);
      final outsider = WireAuthorityClient(outsiderTransport);

      final buyGame = await _startGame(
        prefix: 'buy',
        roomCode: 'BUY001',
        host: host,
        guest: guest,
      );
      await expectLater(
        outsider.watchRoom('buy-room').first,
        throwsA(
          isA<AuthorityTransportException>().having(
            (error) => error.code,
            'code',
            'actorForbidden',
          ),
        ),
      );
      final buyRoll = await _rollToProperty(
        game: buyGame,
        host: host,
        guest: guest,
      );
      final buy = await buyRoll.actor.client.send(
        AuthorityCommandRequest.game(
          GameCommand(
            commandId: 'buy-command',
            schemaVersion: 1,
            expectedStateVersion: buyRoll.snapshot.stateVersion,
            clientInstanceId: '${buyRoll.actor.playerId}-client',
            gameId: buyGame.gameId,
            actorPlayerId: buyRoll.actor.playerId,
            type: GameCommandType.buyProperty,
            payload: <String, Object?>{
              'decisionId': buyRoll.decisionId,
              'propertyId': buyRoll.propertyId,
            },
          ),
        ),
      );
      expect(buy.status, AuthorityCommandStatus.accepted);
      expect(buy.snapshot?.snapshot['pendingDecision'], isNull);

      final auctionGame = await _startGame(
        prefix: 'auction',
        roomCode: 'AUC001',
        host: host,
        guest: guest,
      );
      final auctionRoll = await _rollToProperty(
        game: auctionGame,
        host: host,
        guest: guest,
      );
      final declineRequest = AuthorityCommandRequest.game(
        GameCommand(
          commandId: 'auction-decline',
          schemaVersion: 1,
          expectedStateVersion: auctionRoll.snapshot.stateVersion,
          clientInstanceId: '${auctionRoll.actor.playerId}-client',
          gameId: auctionGame.gameId,
          actorPlayerId: auctionRoll.actor.playerId,
          type: GameCommandType.declineProperty,
          payload: <String, Object?>{
            'decisionId': auctionRoll.decisionId,
            'propertyId': auctionRoll.propertyId,
          },
        ),
      );
      final declined = await auctionRoll.actor.client.send(declineRequest);
      expect(declined.status, AuthorityCommandStatus.accepted);
      final declinedSnapshot = declined.snapshot!;
      final auction =
          declinedSnapshot.snapshot['activeAuction']! as Map<String, Object?>;
      final auctionId = auction['auctionId']! as String;
      final bidderId = auction['currentBidderPlayerId']! as String;
      final bidder = auctionGame.participant(bidderId);
      final bid = await bidder.client.send(
        AuthorityCommandRequest.game(
          GameCommand(
            commandId: 'auction-bid',
            schemaVersion: 1,
            expectedStateVersion: declinedSnapshot.stateVersion,
            clientInstanceId: '$bidderId-client',
            gameId: auctionGame.gameId,
            actorPlayerId: bidderId,
            type: GameCommandType.placeBid,
            payload: <String, Object?>{'auctionId': auctionId, 'amount': 10},
          ),
        ),
      );
      expect(bid.status, AuthorityCommandStatus.accepted);
      expect(bid.snapshot?.snapshot['activeAuction'], isNotNull);

      final lostAckRetry = await auctionRoll.actor.client.send(declineRequest);
      expect(lostAckRetry.status, AuthorityCommandStatus.duplicate);
      final reconnect = await auctionRoll.actor.client.reconnect(
        AuthorityReconnectRequest(
          gameId: auctionGame.gameId,
          observedStateVersion: auctionRoll.snapshot.stateVersion,
          uncertainCommand: declineRequest.uncertainIdentity,
        ),
      );
      expect(reconnect.snapshot.stateVersion, bid.versionAfter);
      expect(
        reconnect.commandResolution?.action,
        CommandResolutionAction.useDurableResult,
      );
      expect(
        jsonEncode(reconnect.toWireJson()),
        isNot(
          anyOf(contains(hostToken), contains(guestToken), contains('uid')),
        ),
      );
    },
    skip: skipReason,
  );
}

Future<_StartedGame> _startGame({
  required String prefix,
  required String roomCode,
  required WireAuthorityClient host,
  required WireAuthorityClient guest,
}) async {
  final createRequest = AuthorityCommandRequest.room(
    RoomCommand(
      commandId: '$prefix-create',
      schemaVersion: 1,
      clientInstanceId: '$prefix-host-client',
      type: RoomCommandType.createRoom,
      payload: const <String, Object?>{
        'presetDraft': <String, Object?>{'presetId': 'express'},
      },
    ),
  );
  final created = await host.send(createRequest);
  expect(created.status, AuthorityCommandStatus.accepted);
  expect(
    (await host.send(createRequest)).status,
    AuthorityCommandStatus.duplicate,
  );
  expect(created.publicResult['roomCode'], roomCode);
  final roomId = created.publicResult['roomId']! as String;
  final hostPlayerId = created.publicResult['actorPlayerId']! as String;
  final hostContext = FirstPlayableAuthorityContext()
    ..applyCommandReply(createRequest, created);

  final joined = await guest.send(
    AuthorityCommandRequest.room(
      RoomCommand(
        commandId: '$prefix-join',
        schemaVersion: 1,
        clientInstanceId: '$prefix-guest-client',
        type: RoomCommandType.joinRoom,
        payload: <String, Object?>{'roomCode': roomCode},
      ),
    ),
  );
  expect(joined.status, AuthorityCommandStatus.accepted);
  final guestPlayerId = joined.publicResult['actorPlayerId']! as String;

  final hostReadyRequest = _roomCommand(
    commandId: '$prefix-ready-host',
    roomId: roomId,
    expectedVersion: joined.versionAfter,
    type: RoomCommandType.setReady,
    ready: true,
  );
  final hostReady = await host.send(hostReadyRequest);
  expect(hostReady.status, AuthorityCommandStatus.accepted);
  hostContext.applyCommandReply(hostReadyRequest, hostReady);
  final guestReady = await guest.send(
    _roomCommand(
      commandId: '$prefix-ready-guest',
      roomId: roomId,
      expectedVersion: hostReady.versionAfter,
      type: RoomCommandType.setReady,
      ready: true,
    ),
  );
  expect(guestReady.status, AuthorityCommandStatus.accepted);
  final hostSession = AuthorityClientSession(
    gateway: host,
    snapshots: host,
    pendingStore: _PendingStore(),
  );
  final hostBinding = SessionFirstPlayableAuthorityBinding(
    session: hostSession,
    requests: ConfirmedFirstPlayableRequestResolver(
      commands: FirstPlayableAuthorityCommands(
        clientInstanceId: '$prefix-host-binding',
        commandIds: _Ids(prefix),
      ),
      context: hostContext,
      createRoomPresetDraft: const <String, Object?>{'presetId': 'express'},
    ),
    roomSnapshots: host,
  );
  final startResult = await hostBinding.perform(
    FirstPlayableAuthorityAction.startGame,
  );
  expect(startResult.outcome, FirstPlayableAuthorityOutcome.accepted);
  final started = hostSession.state.reply!;
  expect(started.status, AuthorityCommandStatus.accepted);
  expect(started.versionBefore, guestReady.versionAfter);
  final gameId = hostContext.gameId;
  await hostSession.close();
  final snapshot = await host.watchGame(gameId).first;
  expect(snapshot.stateVersion, 0);
  return _StartedGame(
    gameId: gameId,
    snapshot: snapshot,
    host: _Participant(hostPlayerId, host),
    guest: _Participant(guestPlayerId, guest),
  );
}

Future<_RolledProperty> _rollToProperty({
  required _StartedGame game,
  required WireAuthorityClient host,
  required WireAuthorityClient guest,
}) async {
  final turn = game.snapshot.snapshot['turnState']! as Map<String, Object?>;
  final actor = game.participant(turn['currentPlayerId']! as String);
  final rolled = await actor.client.send(
    AuthorityCommandRequest.game(
      GameCommand(
        commandId: '${game.gameId}-roll',
        schemaVersion: 1,
        expectedStateVersion: game.snapshot.stateVersion,
        clientInstanceId: '${actor.playerId}-client',
        gameId: game.gameId,
        actorPlayerId: actor.playerId,
        type: GameCommandType.rollDice,
        payload: const <String, Object?>{},
      ),
    ),
  );
  expect(rolled.status, AuthorityCommandStatus.accepted);
  final snapshot = rolled.snapshot!;
  final pending = snapshot.snapshot['pendingDecision']! as Map<String, Object?>;
  expect(pending['kind'], 'propertyOffer');
  final payload = pending['payload']! as Map<String, Object?>;
  return _RolledProperty(
    actor: actor,
    snapshot: snapshot,
    decisionId: pending['decisionId']! as String,
    propertyId: payload['propertyId']! as String,
  );
}

AuthorityCommandRequest _roomCommand({
  required String commandId,
  required String roomId,
  required int expectedVersion,
  required RoomCommandType type,
  bool? ready,
}) => AuthorityCommandRequest.room(
  RoomCommand(
    commandId: commandId,
    schemaVersion: 1,
    expectedRoomVersion: expectedVersion,
    clientInstanceId: '$commandId-client',
    type: type,
    payload: <String, Object?>{
      'roomId': roomId,
      if (type == RoomCommandType.setReady) 'ready': ready,
    },
  ),
);

Future<FirstPlayableRoomEntryMaterial> _roomEntryMaterial(
  RoomCommand command,
  DateTime receivedAt,
) async {
  final prefix = command.commandId.startsWith('buy-') ? 'buy' : 'auction';
  final roomCode = prefix == 'buy' ? 'BUY001' : 'AUC001';
  final create = command.type == RoomCommandType.createRoom;
  return FirstPlayableRoomEntryMaterial(
    kind: create
        ? FirstPlayableRoomEntryKind.create
        : FirstPlayableRoomEntryKind.join,
    roomCode: roomCode,
    codeHash: sha256.convert(utf8.encode(roomCode)).toString(),
    playerId: '$prefix-${create ? 'host' : 'guest'}',
    roomId: create ? '$prefix-room' : null,
    expiresAt: create ? receivedAt.add(const Duration(hours: 1)) : null,
  );
}

Future<FirstPlayableStartMaterial> _startMaterial(RoomCommand command) async {
  final prefix = command.commandId.startsWith('buy-') ? 'buy' : 'auction';
  return FirstPlayableStartMaterial(
    gameId: '$prefix-game',
    seed: syntheticRollSeed,
  );
}

Future<String> _anonymousIdToken(String emulatorHost) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse(
        'http://$emulatorHost/identitytoolkit.googleapis.com/v1/'
        'accounts:signUp?key=fake-api-key',
      ),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode(const <String, Object?>{'returnSecureToken': true}),
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('firebaseAuthEmulatorSignInFailed');
    }
    final body = jsonDecode(await utf8.decoder.bind(response).join());
    if (body is! Map<String, Object?> || body['idToken'] is! String) {
      throw StateError('firebaseAuthEmulatorResponseInvalid');
    }
    return body['idToken']! as String;
  } finally {
    client.close(force: true);
  }
}

final class _StartedGame {
  const _StartedGame({
    required this.gameId,
    required this.snapshot,
    required this.host,
    required this.guest,
  });

  final String gameId;
  final AuthorityPublicSnapshot snapshot;
  final _Participant host;
  final _Participant guest;

  _Participant participant(String playerId) {
    if (host.playerId == playerId) return host;
    if (guest.playerId == playerId) return guest;
    throw StateError('unknownAuthorityPlayer');
  }
}

final class _Participant {
  const _Participant(this.playerId, this.client);

  final String playerId;
  final WireAuthorityClient client;
}

final class _RolledProperty {
  const _RolledProperty({
    required this.actor,
    required this.snapshot,
    required this.decisionId,
    required this.propertyId,
  });

  final _Participant actor;
  final AuthorityPublicSnapshot snapshot;
  final String decisionId;
  final String propertyId;
}

final class _DiscardLogs implements AuthorityLogSink {
  @override
  void write(Map<String, Object> fields) {}
}

final class _Ids implements AuthorityCommandIdSource {
  _Ids(this._prefix);

  final String _prefix;
  int _next = 0;

  @override
  String nextCommandId() => '$_prefix-binding-${++_next}';
}

final class _PendingStore implements PendingAuthorityCommandStore {
  AuthorityCommandRequest? _value;

  @override
  Future<void> clear(String commandId) async {
    if (_value?.commandId == commandId) _value = null;
  }

  @override
  Future<AuthorityCommandRequest?> load() async => _value;

  @override
  Future<void> save(AuthorityCommandRequest request) async {
    _value = request;
  }
}
