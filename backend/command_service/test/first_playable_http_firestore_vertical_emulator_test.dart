import 'dart:convert';
import 'dart:io';

import 'package:board_backend_api/backend_api.dart';
import 'package:board_command_service/command_service.dart'
    hide ReconnectDisposition, UncertainCommandIdentity;
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
      final firestoreConfig = FirstPlayableFirestoreRestConfig.emulator(
        projectId: projectId,
        host: firestoreHost!,
      );
      final store = FirstPlayableFirestoreRestStore(config: firestoreConfig);
      final logs = _RecordingLogs();
      final dependencies = _ReplayDependencies();
      final runtime = FirstPlayableAuthorityRuntime(
        identityVerifier: FirebaseAuthEmulatorIdentityVerifier(
          projectId: projectId,
          emulatorHost: authHost,
        ),
        store: store,
        rulesCatalogRepository: dependencies,
        observability: BestEffortAuthorityObservability(logs),
        roomEntryMaterialFactory: _roomEntryMaterial,
        startMaterialFactory: dependencies.startMaterial,
        now: () => DateTime.utc(2026, 8, 27, 5),
      );
      await expectLater(
        FirstPlayableAuthorityServer.bind(runtime: runtime, host: '0.0.0.0'),
        throwsA(
          isA<FirstPlayableAuthorityServerViolation>().having(
            (error) => error.code,
            'code',
            'emulatorListenerMustBeNumericLoopback',
          ),
        ),
      );
      final server = await FirstPlayableAuthorityServer.bind(
        runtime: runtime,
        port: 0,
      );
      final baseUri = server.baseUri;
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
      final acceptedSnapshotSizes =
          <String, ({Object? measured, int expected})>{};
      final replayDependencyResults = <String, Map<String, Object?>>{};
      void recordAcceptedSnapshot(
        String label,
        AuthorityPublicSnapshot snapshot, {
        required int writes,
      }) {
        final event = logs.events.last;
        _expectGameCommandMetrics(event, writes: writes);
        expect(event['outcome'], 'success');
        expect(event['reason'], 'none');
        expect(event['schemaVersion'], snapshot.schemaVersion);
        expect(event['stateVersion'], snapshot.stateVersion);
        // Use the independent domain encoder on the actual HTTP public map,
        // not the store's AuthorityPublicSnapshot serialization path.
        final expected = utf8
            .encode(CanonicalDomainJson.encode(snapshot.snapshot))
            .length;
        expect(expected, greaterThan(0));
        acceptedSnapshotSizes[label] = (
          measured: event['snapshotBytes'],
          expected: expected,
        );
      }

      void recordStartedSnapshot(String label, _StartedGame game) {
        final event = game.startEvent;
        _expectRoomCommandMetrics(event, writes: 4, roomVersion: 5);
        expect(event['outcome'], 'success');
        expect(event['reason'], 'none');
        expect(game.snapshot.stateVersion, 0);
        final expected = utf8
            .encode(CanonicalDomainJson.encode(game.snapshot.snapshot))
            .length;
        expect(expected, greaterThan(0));
        acceptedSnapshotSizes[label] = (
          measured: event['snapshotBytes'],
          expected: expected,
        );
      }

      final buyGame = await _startGame(
        prefix: 'buy',
        roomCode: 'BUY001',
        host: host,
        guest: guest,
        logs: logs,
        firestoreConfig: firestoreConfig,
        dependencies: dependencies,
        replayDependencyResults: replayDependencyResults,
      );
      recordStartedSnapshot('buy StartGame', buyGame);
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
      recordAcceptedSnapshot('buy Roll', buyRoll.snapshot, writes: 3);
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
      recordAcceptedSnapshot('Buy', buy.snapshot!, writes: 2);

      final auctionGame = await _startGame(
        prefix: 'auction',
        roomCode: 'AUC001',
        host: host,
        guest: guest,
        logs: logs,
        firestoreConfig: firestoreConfig,
        dependencies: dependencies,
        replayDependencyResults: replayDependencyResults,
      );
      recordStartedSnapshot('auction StartGame', auctionGame);
      final auctionRoll = await _rollToProperty(
        game: auctionGame,
        host: host,
        guest: guest,
      );
      recordAcceptedSnapshot('auction Roll', auctionRoll.snapshot, writes: 3);
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
      recordAcceptedSnapshot('Decline', declinedSnapshot, writes: 2);
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
      recordAcceptedSnapshot('Bid', bid.snapshot!, writes: 2);

      final lostAckRetry = await auctionRoll.actor.client.send(declineRequest);
      expect(lostAckRetry.status, AuthorityCommandStatus.duplicate);
      _expectGameCommandMetrics(logs.events.last, writes: 0);
      expect(logs.events.last['snapshotBytes'], 0);
      final eventsBeforeRecovery = logs.events.length;
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
      expect(logs.events, hasLength(eventsBeforeRecovery + 1));
      final recoveryEvent = logs.events.last;
      _expectRecoveryMetrics(recoveryEvent, reads: 3);
      expect(recoveryEvent['outcome'], 'success');
      expect(recoveryEvent['reason'], 'none');
      expect(recoveryEvent['schemaVersion'], reconnect.snapshot.schemaVersion);
      expect(recoveryEvent['stateVersion'], bid.versionAfter);
      expect(
        recoveryEvent['snapshotBytes'],
        utf8.encode(reconnect.snapshot.toCanonicalJson()).length,
      );
      expect(recoveryEvent, hasLength(14));

      await expectLater(
        outsider.reconnect(
          AuthorityReconnectRequest(
            gameId: auctionGame.gameId,
            observedStateVersion: reconnect.snapshot.stateVersion,
          ),
        ),
        throwsA(
          isA<AuthorityTransportException>().having(
            (error) => error.code,
            'code',
            'actorForbidden',
          ),
        ),
      );
      expect(logs.events, hasLength(eventsBeforeRecovery + 2));
      final forbiddenEvent = logs.events.last;
      _expectRecoveryMetrics(forbiddenEvent, reads: 2);
      expect(forbiddenEvent['outcome'], 'internalFailure');
      expect(forbiddenEvent['reason'], 'internalError');
      expect(forbiddenEvent['snapshotBytes'], 0);
      expect(forbiddenEvent, isNot(contains('schemaVersion')));
      expect(forbiddenEvent, isNot(contains('stateVersion')));
      expect(forbiddenEvent, hasLength(12));
      final recoveryLogs = jsonEncode([recoveryEvent, forbiddenEvent]);
      for (final privateValue in [
        hostToken,
        guestToken,
        outsiderToken,
        'uid',
        'BUY001',
        'AUC001',
        auctionGame.gameId,
        declineRequest.commandId,
        declineRequest.inputHash,
        base64Encode(syntheticRollSeed),
      ]) {
        expect(recoveryLogs, isNot(contains(privateValue)));
      }

      // This new request is durably rejected, not just an invented receipt.
      // The fixed authority time is before the auction's pending deadline.
      final staleRequest = AuthorityCommandRequest.game(
        GameCommand(
          commandId: 'auction-stale-decline',
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
      final stale = await auctionRoll.actor.client.send(staleRequest);
      expect(stale.status, AuthorityCommandStatus.rejected);
      expect(stale.errorCode, 'staleVersion');
      expect(stale.versionAfter, bid.versionAfter);
      _expectGameCommandMetrics(logs.events.last, writes: 1);
      expect(logs.events.last['snapshotBytes'], 0);

      final otherMember =
          auctionRoll.actor.playerId == auctionGame.host.playerId
          ? auctionGame.guest
          : auctionGame.host;
      expect(otherMember.playerId != auctionRoll.actor.playerId, isTrue);
      final observedCollisions = <String, Map<String, Object?>>{};
      final actorBindingLogsStart = logs.events.length;
      for (final receiptCase in [
        (
          name: 'accepted',
          request: declineRequest,
          reply: declined,
          ownerDisposition: ReconnectDisposition.uncertainConfirmed,
        ),
        (
          name: 'rejected',
          request: staleRequest,
          reply: stale,
          ownerDisposition: ReconnectDisposition.uncertainRejected,
        ),
      ]) {
        // Read-only local admin evidence includes the private receipt and RNG
        // document; only their digests remain in memory, never test output.
        final before = await _authorityDocumentFingerprints(
          config: firestoreConfig,
          gameId: auctionGame.gameId,
          commandId: receiptCase.request.commandId,
          expectedReceiptStatus: receiptCase.name,
        );
        final eventsBeforeAttempt = logs.events.length;
        final zeroIdentity = UncertainCommandIdentity(
          commandId: receiptCase.request.commandId,
          inputHashVersion: 1,
          inputHash: List<String>.filled(64, '0').join(),
        );
        final wrongActor = await otherMember.client.reconnect(
          AuthorityReconnectRequest(
            gameId: auctionGame.gameId,
            observedStateVersion: reconnect.snapshot.stateVersion,
            uncertainCommand: zeroIdentity,
          ),
        );
        final afterWrongActor = await _authorityDocumentFingerprints(
          config: firestoreConfig,
          gameId: auctionGame.gameId,
          commandId: receiptCase.request.commandId,
          expectedReceiptStatus: receiptCase.name,
        );
        expect(
          afterWrongActor == before,
          isTrue,
          reason: 'other-member reconnect must not change durable documents',
        );
        expect(
          wrongActor.snapshot.toCanonicalJson() ==
              reconnect.snapshot.toCanonicalJson(),
          isTrue,
          reason:
              'other-member reconnect still returns the latest public state',
        );
        expect(logs.events, hasLength(eventsBeforeAttempt + 1));
        final wrongActorEvent = logs.events.last;
        _expectRecoveryMetrics(wrongActorEvent, reads: 3);
        expect(wrongActorEvent['outcome'], 'success');
        expect(wrongActorEvent['reason'], 'none');
        expect(wrongActorEvent['stateVersion'], bid.versionAfter);
        expect(
          wrongActorEvent['snapshotBytes'],
          utf8.encode(wrongActor.snapshot.toCanonicalJson()).length,
        );

        final owner = await auctionRoll.actor.client.reconnect(
          AuthorityReconnectRequest(
            gameId: auctionGame.gameId,
            observedStateVersion: reconnect.snapshot.stateVersion,
            uncertainCommand: receiptCase.request.uncertainIdentity,
          ),
        );
        expect(owner.disposition, receiptCase.ownerDisposition);
        expect(
          owner.commandResolution?.action,
          CommandResolutionAction.useDurableResult,
        );
        expect(
          CanonicalDomainJson.encode(owner.commandResolution!.publicResult!) ==
              CanonicalDomainJson.encode(receiptCase.reply.publicResult),
          isTrue,
          reason: 'the legitimate owner retains the exact durable result',
        );
        expect(
          owner.snapshot.toCanonicalJson() ==
              reconnect.snapshot.toCanonicalJson(),
          isTrue,
          reason:
              'owner recovery uses the current snapshot, not receipt history',
        );
        final afterOwner = await _authorityDocumentFingerprints(
          config: firestoreConfig,
          gameId: auctionGame.gameId,
          commandId: receiptCase.request.commandId,
          expectedReceiptStatus: receiptCase.name,
        );
        expect(
          afterOwner == before,
          isTrue,
          reason:
              'owner reconnect must not change public, private or receipt data',
        );
        expect(logs.events, hasLength(eventsBeforeAttempt + 2));
        final ownerEvent = logs.events.last;
        _expectRecoveryMetrics(ownerEvent, reads: 3);
        expect(ownerEvent['outcome'], 'success');
        expect(ownerEvent['reason'], 'none');
        expect(ownerEvent['stateVersion'], bid.versionAfter);
        expect(
          ownerEvent['snapshotBytes'],
          utf8.encode(owner.snapshot.toCanonicalJson()).length,
        );

        // Collect both cases before asserting, so the original sentinel defect
        // reports accepted AND rejected misclassification in one gate run.
        final resolution = wrongActor.commandResolution;
        observedCollisions[receiptCase.name] = <String, Object?>{
          'disposition': wrongActor.disposition.wireValue,
          'action': resolution?.action.wireValue,
          'errorCode': resolution?.errorCode,
          'resultAbsent': resolution?.publicResult == null,
          'identityPreserved':
              resolution?.identity.commandId == zeroIdentity.commandId &&
              resolution?.identity.inputHash == zeroIdentity.inputHash,
        };
      }
      final actorBindingLogs = jsonEncode(
        logs.events.skip(actorBindingLogsStart).toList(),
      );
      for (final privateValue in [
        hostToken,
        guestToken,
        outsiderToken,
        'uid',
        auctionGame.gameId,
        declineRequest.commandId,
        declineRequest.inputHash,
        staleRequest.commandId,
        staleRequest.inputHash,
        base64Encode(syntheticRollSeed),
      ]) {
        expect(
          actorBindingLogs.contains(privateValue),
          isFalse,
          reason: 'actor-binding diagnostics must not contain private material',
        );
      }
      expect(observedCollisions, <String, Map<String, Object?>>{
        for (final status in ['accepted', 'rejected'])
          status: <String, Object?>{
            'disposition': 'semanticCollision',
            'action': 'failClosed',
            'errorCode': 'commandIdCollision',
            'resultAbsent': true,
            'identityPreserved': true,
          },
      });
      // Defer only the new byte comparisons so a RED run still exercises all
      // accepted commands, lost-ACK/rejected controls and actor-binding checks.
      expect(
        <String, Object?>{
          for (final entry in acceptedSnapshotSizes.entries)
            entry.key: entry.value.measured,
        },
        <String, int>{
          for (final entry in acceptedSnapshotSizes.entries)
            entry.key: entry.value.expected,
        },
      );
      // Collect every dependency fault before asserting the new behavior so a
      // RED run still exercises the existing #105–107 controls in both games.
      expect(replayDependencyResults, <String, Map<String, Object?>>{
        for (final prefix in ['buy', 'auction'])
          for (final fault in ['material', 'catalog', 'both'])
            '$prefix/$fault': <String, Object?>{
              'status': 'duplicate',
              'sameResult': true,
              'sameVersions': true,
              'reads': 3,
              'writes': 0,
              'snapshotBytes': 0,
              'outcome': 'duplicate',
              'reason': 'duplicateCommand',
            },
      });
    },
    skip: skipReason,
  );
}

void _expectRoomCommandMetrics(
  Map<String, Object> event, {
  required int writes,
  required int roomVersion,
}) {
  expect(event['operation'], 'roomCommand');
  expect(event['retryCount'], 0);
  expect(event['conflictCount'], 0);
  expect(event['firestoreReadCount'], 3);
  expect(event['firestoreWriteCount'], writes);
  expect(event['bytesRead'], greaterThan(0));
  expect(event['bytesWritten'], greaterThan(0));
  expect(event['coldStart'], isFalse);
  expect(event['schemaVersion'], 1);
  // The envelope remains a room command even though its gauge sizes a game.
  expect(event['stateVersion'], roomVersion);
  expect(event, hasLength(14));
}

void _expectGameCommandMetrics(
  Map<String, Object> event, {
  required int writes,
}) {
  expect(event['operation'], 'gameCommand');
  expect(event['retryCount'], 0);
  expect(event['conflictCount'], 0);
  expect(event['firestoreReadCount'], 3);
  expect(event['firestoreWriteCount'], writes);
  expect(event['bytesRead'], greaterThan(0));
  expect(event['bytesWritten'], greaterThan(0));
  expect(event['coldStart'], isFalse);
  expect(event.keys.toSet(), <String>{
    'operation',
    'outcome',
    'reason',
    'latencyMs',
    'retryCount',
    'conflictCount',
    'firestoreReadCount',
    'firestoreWriteCount',
    'bytesRead',
    'bytesWritten',
    'snapshotBytes',
    'coldStart',
    'schemaVersion',
    'stateVersion',
  });
}

Future<({String publicGame, String privateGame, String receipt})>
_authorityDocumentFingerprints({
  required FirstPlayableFirestoreRestConfig config,
  required String gameId,
  required String commandId,
  required String expectedReceiptStatus,
  bool roomCommand = false,
}) async {
  if (!config.isEmulator ||
      config.projectId != 'demo-board-game-local' ||
      !const ['127.0.0.1', '::1'].contains(config.endpoint.host)) {
    throw StateError('privateEvidenceRequiresNumericLoopbackDemoEmulator');
  }
  final client = HttpClient();
  Future<String> readFingerprint(
    String document, {
    bool receipt = false,
  }) async {
    final request = await client.getUrl(
      config.endpoint.replace(
        path:
            '/v1/projects/${config.projectId}/databases/'
            '${config.databaseId}/documents/$document',
      ),
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw StateError('durableEvidenceDocumentUnavailable');
    }
    late Map<String, Object?> documentJson;
    try {
      final decoded = jsonDecode(await utf8.decoder.bind(response).join());
      if (decoded is! Map<String, Object?>) {
        throw StateError('invalidDurableEvidenceDocument');
      }
      documentJson = decoded;
    } on Object {
      throw StateError('invalidDurableEvidenceDocument');
    }
    if (receipt) {
      final fields = documentJson['fields'];
      final status = fields is Map<String, Object?> ? fields['status'] : null;
      final value = status is Map<String, Object?>
          ? status['stringValue']
          : null;
      expect(
        value == expectedReceiptStatus,
        isTrue,
        reason: 'the accepted or rejected receipt must already be persisted',
      );
    }
    try {
      return sha256
          .convert(utf8.encode(CanonicalDomainJson.encode(documentJson)))
          .toString();
    } on Object {
      throw StateError('durableEvidenceFingerprintUnavailable');
    }
  }

  try {
    return (
      publicGame: await readFingerprint('games/$gameId'),
      privateGame: await readFingerprint('gameSecrets/$gameId'),
      receipt: await readFingerprint(
        roomCommand
            ? 'roomCommands/$commandId'
            : 'games/$gameId/commands/$commandId',
        receipt: true,
      ),
    );
  } finally {
    client.close(force: true);
  }
}

void _expectRecoveryMetrics(Map<String, Object> event, {required int reads}) {
  expect(event['operation'], 'recovery');
  expect(event['retryCount'], 0);
  expect(event['conflictCount'], 0);
  expect(event['firestoreReadCount'], reads);
  expect(event['firestoreWriteCount'], 0);
  // The scripted peer separately proves byte-exact transfer totals. This real
  // emulator gate proves the runtime publishes measured, nonzero payload I/O.
  expect(event['bytesRead'], greaterThan(0));
  expect(event['bytesWritten'], greaterThan(0));
  expect(event['coldStart'], isFalse);
}

Future<_StartedGame> _startGame({
  required String prefix,
  required String roomCode,
  required WireAuthorityClient host,
  required WireAuthorityClient guest,
  required _RecordingLogs logs,
  required FirstPlayableFirestoreRestConfig firestoreConfig,
  required _ReplayDependencies dependencies,
  required Map<String, Map<String, Object?>> replayDependencyResults,
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
  expect(logs.events.last['snapshotBytes'], 0);
  expect(
    (await host.send(createRequest)).status,
    AuthorityCommandStatus.duplicate,
  );
  expect(logs.events.last['snapshotBytes'], 0);
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
  expect(logs.events.last['snapshotBytes'], 0);
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
  expect(logs.events.last['snapshotBytes'], 0);
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
  expect(logs.events.last['snapshotBytes'], 0);
  final pendingStore = _PendingStore();
  final hostSession = AuthorityClientSession(
    gateway: host,
    snapshots: host,
    pendingStore: pendingStore,
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
  expect(started.versionAfter, 5);
  final startEvent = logs.events.last;
  final startRequest = pendingStore.lastSavedRequest!;
  expect(startRequest.commandId, started.commandId);
  expect(startRequest.asRoomCommand.type, RoomCommandType.startGame);
  expect(await pendingStore.load(), isNull);
  final gameId = hostContext.gameId;
  await hostSession.close();
  final guestRoom = await guest.watchRoom(roomId).first;
  expect(guestRoom.gameId, gameId);
  expect(guestRoom.roomVersion, started.versionAfter);
  final snapshot = await host.watchGame(gameId).first;
  expect(snapshot.stateVersion, 0);
  final guestSnapshot = await guest.watchGame(gameId).first;
  expect(
    guestSnapshot.toCanonicalJson() == snapshot.toCanonicalJson(),
    isTrue,
    reason: 'both members observe the same committed initial public game',
  );
  final beforeReplay = await _authorityDocumentFingerprints(
    config: firestoreConfig,
    gameId: gameId,
    commandId: startRequest.commandId,
    expectedReceiptStatus: 'accepted',
    roomCommand: true,
  );
  final eventsBeforeReplay = logs.events.length;
  final replay = await host.send(startRequest);
  expect(replay.status, AuthorityCommandStatus.duplicate);
  expect(replay.publicResult['gameId'], gameId);
  expect(replay.versionBefore, started.versionBefore);
  expect(replay.versionAfter, started.versionAfter);
  expect(
    CanonicalDomainJson.encode(replay.publicResult) ==
        CanonicalDomainJson.encode(started.publicResult),
    isTrue,
    reason: 'replay keeps the original game and starter allocation result',
  );
  expect(logs.events, hasLength(eventsBeforeReplay + 1));
  final replayEvent = logs.events.last;
  _expectRoomCommandMetrics(replayEvent, writes: 0, roomVersion: 5);
  expect(replayEvent['outcome'], 'duplicate');
  expect(replayEvent['reason'], 'duplicateCommand');
  expect(replayEvent['snapshotBytes'], 0);
  final afterReplay = await _authorityDocumentFingerprints(
    config: firestoreConfig,
    gameId: gameId,
    commandId: startRequest.commandId,
    expectedReceiptStatus: 'accepted',
    roomCommand: true,
  );
  expect(
    afterReplay == beforeReplay,
    isTrue,
    reason: 'replay must preserve public game, private RNG and durable receipt',
  );
  final replayedRoom = await guest.watchRoom(roomId).first;
  final replayedSnapshot = await guest.watchGame(gameId).first;
  expect(replayedRoom.toCanonicalJson() == guestRoom.toCanonicalJson(), isTrue);
  expect(
    replayedSnapshot.toCanonicalJson() == snapshot.toCanonicalJson(),
    isTrue,
  );
  for (final fault in ['material', 'catalog', 'both']) {
    final beforeFault = await _authorityDocumentFingerprints(
      config: firestoreConfig,
      gameId: gameId,
      commandId: startRequest.commandId,
      expectedReceiptStatus: 'accepted',
      roomCommand: true,
    );
    final eventsBeforeFault = logs.events.length;
    AuthorityCommandReply? faultReplay;
    String? transportError;
    dependencies.failMaterial = fault != 'catalog';
    dependencies.failRoomCatalog = fault != 'material';
    try {
      faultReplay = await host.send(startRequest);
    } on AuthorityTransportException catch (error) {
      transportError = error.code;
    } finally {
      dependencies.failMaterial = false;
      dependencies.failRoomCatalog = false;
    }
    expect(logs.events, hasLength(eventsBeforeFault + 1));
    final event = logs.events.last;
    replayDependencyResults['$prefix/$fault'] = <String, Object?>{
      'status': faultReplay?.status.name ?? 'transport:$transportError',
      'sameResult':
          faultReplay != null &&
          CanonicalDomainJson.encode(faultReplay.publicResult) ==
              CanonicalDomainJson.encode(started.publicResult),
      'sameVersions':
          faultReplay?.versionBefore == started.versionBefore &&
          faultReplay?.versionAfter == started.versionAfter,
      'reads': event['firestoreReadCount'],
      'writes': event['firestoreWriteCount'],
      'snapshotBytes': event['snapshotBytes'],
      'outcome': event['outcome'],
      'reason': event['reason'],
    };
    final afterFault = await _authorityDocumentFingerprints(
      config: firestoreConfig,
      gameId: gameId,
      commandId: startRequest.commandId,
      expectedReceiptStatus: 'accepted',
      roomCommand: true,
    );
    expect(
      afterFault == beforeFault,
      isTrue,
      reason: 'dependency faults must not mutate public, RNG or receipt data',
    );
    final roomAfterFault = await guest.watchRoom(roomId).first;
    final gameAfterFault = await guest.watchGame(gameId).first;
    expect(
      roomAfterFault.toCanonicalJson() == guestRoom.toCanonicalJson(),
      isTrue,
    );
    expect(
      gameAfterFault.toCanonicalJson() == snapshot.toCanonicalJson(),
      isTrue,
    );
  }
  return _StartedGame(
    gameId: gameId,
    snapshot: snapshot,
    startEvent: startEvent,
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

// Faults are test-only and enabled after the genuine StartGame commit. The
// runtime still uses its real executor, REST store, Auth and HTTP transports.
final class _ReplayDependencies implements FirstPlayableRulesCatalogRepository {
  final _catalogs = PinnedFirstPlayableRulesCatalogRepository(
    activeRulesVersion: syntheticRollCatalog().rulesVersion,
    catalogs: <RulesCatalog>[syntheticRollCatalog()],
  );
  bool failMaterial = false;
  bool failRoomCatalog = false;

  Future<FirstPlayableStartMaterial> startMaterial(RoomCommand command) async {
    if (failMaterial) throw StateError('syntheticStartMaterialUnavailable');
    return _startMaterial(command);
  }

  @override
  RulesCatalog catalogForNewRoom({required String presetId}) =>
      _catalogs.catalogForNewRoom(presetId: presetId);

  @override
  RulesCatalog catalogForRoom({
    required String rulesVersion,
    required String presetId,
  }) {
    if (failRoomCatalog) {
      throw const FirstPlayableRulesCatalogRepositoryViolation(
        'rulesCatalogUnavailable',
      );
    }
    return _catalogs.catalogForRoom(
      rulesVersion: rulesVersion,
      presetId: presetId,
    );
  }

  @override
  RulesCatalog catalogForGame(PublicGameState state) =>
      _catalogs.catalogForGame(state);
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
    required this.startEvent,
    required this.host,
    required this.guest,
  });

  final String gameId;
  final AuthorityPublicSnapshot snapshot;
  final Map<String, Object> startEvent;
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

final class _RecordingLogs implements AuthorityLogSink {
  final events = <Map<String, Object>>[];

  @override
  void write(Map<String, Object> fields) => events.add(fields);
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
  AuthorityCommandRequest? lastSavedRequest;

  @override
  Future<void> clear(String commandId) async {
    if (_value?.commandId == commandId) _value = null;
  }

  @override
  Future<AuthorityCommandRequest?> load() async => _value;

  @override
  Future<void> save(AuthorityCommandRequest request) async {
    _value = request;
    lastSavedRequest = request;
  }
}
