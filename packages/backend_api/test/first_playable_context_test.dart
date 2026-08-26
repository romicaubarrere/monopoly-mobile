import 'package:board_backend_api/backend_api.dart';
import 'package:board_game_contracts/game_contracts.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  test('CreateRoom ACK establishes authority-owned actor membership', () {
    final context = FirstPlayableAuthorityContext();
    final request = _roomEntryRequest(
      commandId: 'cmd-create-1',
      type: RoomCommandType.createRoom,
    );

    expect(
      () => context.actorPlayerId,
      throwsA(_violation('confirmedActorUnavailable')),
    );

    context.applyCommandReply(
      request,
      AuthorityCommandReply(
        commandId: request.commandId,
        status: AuthorityCommandStatus.accepted,
        versionBefore: 0,
        versionAfter: 1,
        publicResult: const <String, Object?>{
          'roomId': 'room-1',
          'roomVersion': 1,
          'actorPlayerId': 'player-authority-1',
        },
      ),
    );

    expect(context.actorPlayerId, 'player-authority-1');
    expect(context.roomId, 'room-1');
    expect(context.roomVersion, 1);
  });

  test('room entry fails closed without authority-owned actor membership', () {
    final context = FirstPlayableAuthorityContext();
    final request = _roomEntryRequest(
      commandId: 'cmd-join-1',
      type: RoomCommandType.joinRoom,
    );

    expect(
      () => context.applyCommandReply(
        request,
        AuthorityCommandReply(
          commandId: request.commandId,
          status: AuthorityCommandStatus.accepted,
          versionBefore: 3,
          versionAfter: 4,
          publicResult: const <String, Object?>{
            'roomId': 'room-1',
            'roomVersion': 4,
          },
        ),
      ),
      throwsA(_violation('missingAuthorityActorPlayerId')),
    );
  });

  test('later room ACK cannot replace confirmed actor membership', () {
    final context = _confirmedContext();
    final request = _roomRequest(
      commandId: 'cmd-ready-membership',
      type: RoomCommandType.setReady,
      expectedVersion: 4,
    );

    expect(
      () => context.applyCommandReply(
        request,
        AuthorityCommandReply(
          commandId: request.commandId,
          status: AuthorityCommandStatus.accepted,
          versionBefore: 4,
          versionAfter: 5,
          publicResult: const <String, Object?>{
            'roomId': 'room-1',
            'roomVersion': 5,
            'actorPlayerId': 'player-2',
          },
        ),
      ),
      throwsA(_violation('actorPlayerIdMismatch')),
    );
  });

  test('room ACK supplies the next confirmed room version', () {
    final context = _confirmedContext();
    final request = _roomRequest(
      commandId: 'cmd-ready-1',
      type: RoomCommandType.setReady,
      expectedVersion: 4,
    );

    context.applyCommandReply(
      request,
      AuthorityCommandReply(
        commandId: request.commandId,
        status: AuthorityCommandStatus.accepted,
        versionBefore: 4,
        versionAfter: 5,
        publicResult: const <String, Object?>{
          'roomId': 'room-1',
          'roomVersion': 5,
        },
      ),
    );

    expect(context.roomId, 'room-1');
    expect(context.roomVersion, 5);
  });

  test('StartGame summary supplies game id and initial state version', () {
    final context = _confirmedContext();
    final request = _roomRequest(
      commandId: 'cmd-start-1',
      type: RoomCommandType.startGame,
      expectedVersion: 5,
    );

    context.applyCommandReply(
      request,
      AuthorityCommandReply(
        commandId: request.commandId,
        status: AuthorityCommandStatus.accepted,
        versionBefore: 5,
        versionAfter: 6,
        publicResult: const <String, Object?>{
          'roomId': 'room-1',
          'roomVersion': 6,
          'gameId': 'game-1',
          'stateVersion': 0,
        },
      ),
    );

    expect(context.gameId, 'game-1');
    expect(context.stateVersion, 0);
  });

  test('public replacement supplies property and auction identifiers', () {
    final context = _confirmedContext();

    context.replacePublicSnapshot(_snapshot(1, propertyOffer: true));
    expect(context.propertyDecisionId, 'decision-1');
    expect(context.propertyId, 'property-7');
    expect(
      () => context.auctionId,
      throwsA(_violation('confirmedAuctionUnavailable')),
    );

    context.replacePublicSnapshot(_snapshot(2, auction: true));
    expect(context.auctionId, 'auction-1');
    expect(
      () => context.propertyDecisionId,
      throwsA(_violation('confirmedPropertyDecisionUnavailable')),
    );
  });

  test('game ACK clears consumed decision and advances exact version', () {
    final context = _confirmedContext();
    context.replacePublicSnapshot(_snapshot(1, propertyOffer: true));
    final request = AuthorityCommandRequest.game(
      GameCommand(
        commandId: 'cmd-decline-1',
        schemaVersion: 1,
        expectedStateVersion: 1,
        clientInstanceId: 'client-1',
        gameId: 'game-1',
        actorPlayerId: 'player-1',
        type: GameCommandType.declineProperty,
        payload: const <String, Object?>{
          'decisionId': 'decision-1',
          'propertyId': 'property-7',
        },
      ),
    );

    context.applyCommandReply(
      request,
      AuthorityCommandReply(
        commandId: request.commandId,
        status: AuthorityCommandStatus.accepted,
        versionBefore: 1,
        versionAfter: 2,
        publicResult: const <String, Object?>{'stateVersionAfter': 2},
      ),
    );

    expect(context.stateVersion, 2);
    expect(
      () => context.propertyDecisionId,
      throwsA(_violation('confirmedPropertyDecisionUnavailable')),
    );
    expect(
      () => context.auctionId,
      throwsA(_violation('confirmedAuctionUnavailable')),
    );
  });

  test('stale snapshots cannot roll confirmed context backward', () {
    final context = _confirmedContext();
    context.replacePublicSnapshot(_snapshot(3, auction: true));
    context.replacePublicSnapshot(_snapshot(2, propertyOffer: true));

    expect(context.stateVersion, 3);
    expect(context.auctionId, 'auction-1');
  });

  test('mismatched room and game material fails closed', () {
    final context = _confirmedContext();
    context.replacePublicSnapshot(_snapshot(1));

    expect(
      () => context.replacePublicSnapshot(
        AuthorityPublicSnapshot(<String, Object?>{
          ..._snapshot(2).snapshot,
          'gameId': 'game-2',
        }),
      ),
      throwsA(_violation('snapshotGameMismatch')),
    );
  });

  test('different snapshot content at one version fails closed', () {
    final context = _confirmedContext();
    context.replacePublicSnapshot(_snapshot(2));

    expect(
      () => context.replacePublicSnapshot(_snapshot(2, auction: true)),
      throwsA(_violation('snapshotVersionCollision')),
    );
  });
}

FirstPlayableAuthorityContext _confirmedContext() {
  final context = FirstPlayableAuthorityContext();
  final request = _roomEntryRequest(
    commandId: 'cmd-confirm-membership',
    type: RoomCommandType.createRoom,
  );
  context.applyCommandReply(
    request,
    AuthorityCommandReply(
      commandId: request.commandId,
      status: AuthorityCommandStatus.accepted,
      versionBefore: 0,
      versionAfter: 1,
      publicResult: const <String, Object?>{
        'roomId': 'room-1',
        'roomVersion': 1,
        'actorPlayerId': 'player-1',
      },
    ),
  );
  return context;
}

AuthorityCommandRequest _roomRequest({
  required String commandId,
  required RoomCommandType type,
  required int expectedVersion,
}) => AuthorityCommandRequest.room(
  RoomCommand(
    commandId: commandId,
    schemaVersion: 1,
    expectedRoomVersion: expectedVersion,
    clientInstanceId: 'client-1',
    type: type,
    payload: <String, Object?>{
      'roomId': 'room-1',
      if (type == RoomCommandType.setReady) 'ready': true,
    },
  ),
);

AuthorityCommandRequest _roomEntryRequest({
  required String commandId,
  required RoomCommandType type,
}) => AuthorityCommandRequest.room(
  RoomCommand(
    commandId: commandId,
    schemaVersion: 1,
    clientInstanceId: 'client-1',
    type: type,
    payload: type == RoomCommandType.createRoom
        ? const <String, Object?>{
            'presetDraft': <String, Object?>{'presetId': 'synthetic-vp0'},
          }
        : const <String, Object?>{'roomCode': 'ABC123'},
  ),
);

AuthorityPublicSnapshot _snapshot(
  int version, {
  bool propertyOffer = false,
  bool auction = false,
}) => AuthorityPublicSnapshot(<String, Object?>{
  'schemaVersion': 1,
  'stateVersion': version,
  'rulesVersion': 'synthetic-rules-vp0',
  'rngVersion': 'hmac_sha256_counter_v1',
  'rngCommitment': List<String>.filled(64, '0').join(),
  'gameId': 'game-1',
  'roomId': 'room-1',
  'status': 'active',
  if (propertyOffer)
    'pendingDecision': const <String, Object?>{
      'decisionId': 'decision-1',
      'kind': 'propertyOffer',
      'payload': <String, Object?>{'propertyId': 'property-7'},
    },
  if (auction)
    'activeAuction': const <String, Object?>{
      'auctionId': 'auction-1',
      'propertyId': 'property-7',
    },
});

Matcher _violation(String code) => isA<ClientAuthorityContractViolation>()
    .having((error) => error.code, 'code', code);
