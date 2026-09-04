import 'package:board_game_core/game_core.dart';

import 'synthetic_roll_fixture.dart';

final DateTime syntheticTaxFreeParkingTime = DateTime.parse(
  '2026-08-25T05:30:00Z',
);

RulesCatalog syntheticTaxFreeParkingCatalog() {
  final source = syntheticRollCatalog();
  return RulesCatalog(
    rulesVersion: source.rulesVersion,
    boardDefinitionVersion: source.boardDefinitionVersion,
    economyVersion: source.economyVersion,
    deckCatalogVersion: source.deckCatalogVersion,
    presetCatalogVersion: source.presetCatalogVersion,
    ruleFlags: <String, bool>{...source.ruleFlags, 'freeParkingPot': true},
    boardDefinition: source.boardDefinition,
    economyCatalog: source.economyCatalog,
    deckCatalog: source.deckCatalog,
    presets: source.presets,
  );
}

PublicGameState syntheticTaxFreeParkingState({
  int stateVersion = 1,
  int cash = 500,
  int position = 31,
  int pot = 29,
}) {
  final catalog = syntheticTaxFreeParkingCatalog();
  return PublicGameState(
    header: GameStateHeader(
      schemaVersion: 1,
      stateVersion: stateVersion,
      rulesVersion: catalog.rulesVersion,
      rngVersion: canonicalRngVersion,
      rngCommitment: List<String>.filled(64, '0').join(),
      gameId: 'game-us019',
      roomId: 'room-us019',
      status: GameStatus.active,
    ),
    presetConfig: catalog.resolvePreset('express', 2).toJson(),
    roundState: const <String, Object?>{'round': 1},
    turnState: const <String, Object?>{
      'turnNumber': 1,
      'phase': 'resolvingLanding',
      'currentPlayerId': 'p1',
    },
    players: <PlayerState>[
      _player('p1', 0, cash, position),
      _player('p2', 1, 700, 0),
    ],
    seatControllers: <SeatControllerState>[
      for (final id in const <String>['p1', 'p2'])
        SeatControllerState(
          playerId: id,
          controller: SeatController.human,
          humanReclaimPending: false,
        ),
    ],
    board: <String, Object?>{
      'boardId': catalog.boardDefinition.boardId,
      'boardDefinitionVersion': catalog.boardDefinitionVersion,
    },
    ownership: const <String, Object?>{
      'byPropertyId': <String, Object?>{},
      'properties': <Object?>[],
    },
    bank: const <String, Object?>{'currencyUnit': 'synthetic-unit'},
    freeParkingPot: pot,
    deckPublicState: const <String, Object?>{},
    lastMutation: const <String, Object?>{'type': 'playerMoved'},
  );
}

PlayerState _player(String id, int seat, int cash, int position) => PlayerState(
  playerId: id,
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
