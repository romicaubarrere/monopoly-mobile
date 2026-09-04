import 'package:board_game_core/game_core.dart';

import 'synthetic_roll_fixture.dart';

final DateTime syntheticBankruptcyTime = DateTime.parse('2026-08-25T04:29:00Z');
final DateTime syntheticBankruptcyDeadline = DateTime.parse(
  '2026-08-25T04:30:00Z',
);

RulesCatalog syntheticBankruptcyCatalog() => syntheticRollCatalog();

GameCommand syntheticBankruptcyCommand(
  GameCommandType type, {
  String commandId = 'cmd-bankruptcy-1',
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
    'debtCaseId': 'debt-1',
    'decisionId': 'debt-1:decision',
  },
);

PublicGameState syntheticBankruptcyState({
  int debtorCash = 7,
  int amountDue = 500,
  String creditorKind = 'player',
  bool includeThirdPlayer = false,
}) {
  final asset = PropertyState(
    propertyId: 'street-00',
    kind: PropertyKind.street,
    ownerPlayerId: 'p1',
    mortgaged: true,
    improvementLevel: 0,
  );
  final playerIds = <String>['p1', 'p2', if (includeThirdPlayer) 'p3'];
  return PublicGameState(
    header: GameStateHeader(
      schemaVersion: 1,
      stateVersion: 1,
      rulesVersion: 'synthetic-rules-vp0',
      rngVersion: canonicalRngVersion,
      rngCommitment: List<String>.filled(64, '0').join(),
      gameId: 'game-vp0',
      roomId: 'room-vp0',
      status: GameStatus.active,
    ),
    presetConfig: syntheticBankruptcyCatalog()
        .resolvePreset('express', playerIds.length)
        .toJson(),
    roundState: const <String, Object?>{'round': 1},
    turnState: const <String, Object?>{
      'turnNumber': 1,
      'phase': 'debtResolution',
      'currentPlayerId': 'p1',
    },
    players: <PlayerState>[
      _player(
        'p1',
        0,
        debtorCash,
        propertyIds: const <String>['street-00'],
        cards: const <String>['keep-a'],
      ),
      _player('p2', 1, 2000),
      if (includeThirdPlayer) _player('p3', 2, 2000),
    ],
    seatControllers: <SeatControllerState>[
      for (final entry in playerIds.indexed)
        SeatControllerState(
          playerId: entry.$2,
          controller: SeatController.human,
          humanReclaimPending: false,
        ),
    ],
    board: const <String, Object?>{
      'boardId': 'synthetic-board',
      'boardDefinitionVersion': 'synthetic-board-vp0',
    },
    ownership: <String, Object?>{
      'byPropertyId': const <String, Object?>{'street-00': 'p1'},
      'properties': <Object?>[asset.toJson()],
    },
    bank: const <String, Object?>{
      'currencyUnit': 'synthetic-unit',
      'keepCardIds': <Object?>[],
    },
    freeParkingPot: 0,
    deckPublicState: const <String, Object?>{},
    pendingDecision: const <String, Object?>{
      'decisionId': 'debt-1:decision',
      'kind': 'debtResolution',
      'allowedPlayerIds': <Object?>['p1'],
      'stateVersionCreated': 1,
      'createdAt': '2026-08-25T04:29:00.000Z',
      'deadlineAt': '2026-08-25T04:30:00.000Z',
      'timeoutPolicy': 'declareBankruptcy',
    },
    debtCase: <String, Object?>{
      'debtCaseId': 'debt-1',
      'debtorPlayerId': 'p1',
      'creditor': <String, Object?>{
        'kind': creditorKind,
        if (creditorKind == 'player') 'playerId': 'p2',
      },
      'amountDue': amountDue,
      'status': 'open',
    },
    lastMutation: const <String, Object?>{'type': 'debtOpened'},
  );
}

PlayerState _player(
  String playerId,
  int seat,
  int cash, {
  List<String> propertyIds = const <String>[],
  List<String> cards = const <String>[],
}) => PlayerState(
  playerId: playerId,
  seat: seat,
  kind: PlayerKind.human,
  status: PlayerStatus.active,
  cash: cash,
  position: 0,
  ownedPropertyIds: propertyIds,
  keepCardIds: cards,
  inCucha: false,
  cuchaAttempts: 0,
  consecutiveDoubles: 0,
  connectivityStatus: ConnectivityStatus.online,
);
