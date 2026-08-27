import 'package:board_game_core/game_core.dart';

import 'synthetic_roll_fixture.dart';

final DateTime syntheticBuyAuctionTime = DateTime.parse('2026-08-25T02:30:00Z');

RulesCatalog syntheticBuyAuctionCatalog() => syntheticRollCatalog();

GameCommand syntheticOfferCommand(
  GameCommandType type, {
  String commandId = 'cmd-offer-1',
  int expectedStateVersion = 1,
  String actorPlayerId = 'p1',
  String clientInstanceId = 'client-1',
}) => GameCommand(
  commandId: commandId,
  schemaVersion: 1,
  expectedStateVersion: expectedStateVersion,
  clientInstanceId: clientInstanceId,
  gameId: 'game-vp0',
  actorPlayerId: actorPlayerId,
  type: type,
  payload: const <String, Object?>{
    'decisionId': 'cmd-roll-1:propertyOffer',
    'propertyId': 'street-07',
  },
);

GameCommand syntheticAuctionCommand(
  GameCommandType type, {
  required String commandId,
  required int expectedStateVersion,
  required String actorPlayerId,
  required Map<String, Object?> payload,
  String clientInstanceId = 'client-1',
}) => GameCommand(
  commandId: commandId,
  schemaVersion: 1,
  expectedStateVersion: expectedStateVersion,
  clientInstanceId: clientInstanceId,
  gameId: 'game-vp0',
  actorPlayerId: actorPlayerId,
  type: type,
  payload: payload,
);

PublicGameState syntheticPropertyOfferState({int p1Cash = 2000}) {
  final rng = CanonicalRng(seed: syntheticRollSeed);
  return PublicGameState(
    header: GameStateHeader(
      schemaVersion: 1,
      stateVersion: 1,
      rulesVersion: 'synthetic-rules-vp0',
      rngVersion: canonicalRngVersion,
      rngCommitment: rng.commitmentHex,
      gameId: 'game-vp0',
      roomId: 'room-vp0',
      status: GameStatus.active,
    ),
    presetConfig: syntheticBuyAuctionCatalog()
        .resolvePreset('express', 2)
        .toJson(),
    roundState: const <String, Object?>{'round': 1},
    turnState: const <String, Object?>{
      'turnNumber': 1,
      'phase': 'awaitingPropertyDecision',
      'currentPlayerId': 'p1',
      'landingPropertyId': 'street-07',
    },
    players: <PlayerState>[
      _player('p1', 0, p1Cash, position: 8),
      _player('p2', 1, 2000),
    ],
    seatControllers: <SeatControllerState>[
      SeatControllerState(
        playerId: 'p1',
        controller: SeatController.human,
        humanReclaimPending: false,
      ),
      SeatControllerState(
        playerId: 'p2',
        controller: SeatController.human,
        humanReclaimPending: false,
      ),
    ],
    board: const <String, Object?>{
      'boardId': 'synthetic-board',
      'boardDefinitionVersion': 'synthetic-board-vp0',
    },
    ownership: const <String, Object?>{},
    bank: const <String, Object?>{'currencyUnit': 'synthetic-unit'},
    freeParkingPot: 0,
    deckPublicState: const <String, Object?>{},
    pendingDecision: const <String, Object?>{
      'decisionId': 'cmd-roll-1:propertyOffer',
      'kind': 'propertyOffer',
      'allowedPlayerIds': <Object?>['p1'],
      'stateVersionCreated': 1,
      'createdAt': '2026-08-25T02:29:48.000Z',
      'deadlineAt': '2026-08-25T02:30:12.000Z',
      'timeoutPolicy': 'pass',
      'payload': <String, Object?>{
        'propertyId': 'street-07',
        'purchasePrice': 107,
      },
    },
    lastMutation: const <String, Object?>{
      'type': 'rollMovement',
      'commandId': 'cmd-roll-1',
    },
  );
}

PlayerState _player(String playerId, int seat, int cash, {int position = 0}) =>
    PlayerState(
      playerId: playerId,
      seat: seat,
      kind: PlayerKind.human,
      status: PlayerStatus.active,
      cash: cash,
      position: position,
      ownedPropertyIds: const <String>[],
      keepCardIds: const <String>[],
      inCucha: false,
      cuchaAttempts: 0,
      consecutiveDoubles: 0,
      connectivityStatus: ConnectivityStatus.online,
    );
