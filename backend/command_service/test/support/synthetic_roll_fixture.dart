import 'package:board_command_service/command_service.dart';
import 'package:board_game_core/game_core.dart';

final List<int> syntheticRollSeed = List<int>.generate(32, (index) => index);

AuthorityPrivateRngSnapshot syntheticRollPrivateState({
  String rngVersion = canonicalRngVersion,
}) => AuthorityPrivateRngSnapshot(
  rngVersion: rngVersion,
  seed: syntheticRollSeed,
  streamCounters: const <RngStream, int>{},
);

GameCommand syntheticRollCommand({
  String commandId = 'cmd-roll-1',
  int expectedStateVersion = 0,
  String actorPlayerId = 'p1',
  String clientInstanceId = 'client-1',
}) => GameCommand(
  commandId: commandId,
  schemaVersion: 1,
  expectedStateVersion: expectedStateVersion,
  clientInstanceId: clientInstanceId,
  gameId: 'game-vp0',
  actorPlayerId: actorPlayerId,
  type: GameCommandType.rollDice,
  payload: const <String, Object?>{},
);

PublicGameState syntheticRollState({
  int stateVersion = 0,
  String phase = 'awaitingRoll',
}) {
  final rng = CanonicalRng(seed: syntheticRollSeed);
  return PublicGameState(
    header: GameStateHeader(
      schemaVersion: 1,
      stateVersion: stateVersion,
      rulesVersion: 'synthetic-rules-vp0',
      rngVersion: canonicalRngVersion,
      rngCommitment: rng.commitmentHex,
      gameId: 'game-vp0',
      roomId: 'room-vp0',
      status: GameStatus.active,
    ),
    presetConfig: const <String, Object?>{
      'presetId': 'express',
      'mandatoryDecisionSeconds': 12,
    },
    roundState: const <String, Object?>{'round': 1},
    turnState: <String, Object?>{
      'turnNumber': 1,
      'phase': phase,
      'currentPlayerId': 'p1',
    },
    players: <PlayerState>[_player('p1', 0), _player('p2', 1)],
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
    ownership: const <String, Object?>{'properties': <Object?>[]},
    bank: const <String, Object?>{'currencyUnit': 'synthetic-unit'},
    freeParkingPot: 0,
    deckPublicState: const <String, Object?>{
      'cardsARemaining': 3,
      'cardsBRemaining': 3,
    },
    lastMutation: const <String, Object?>{
      'type': 'gameStarted',
      'commandId': 'cmd-start',
    },
  );
}

PlayerState _player(String playerId, int seat) => PlayerState(
  playerId: playerId,
  seat: seat,
  kind: PlayerKind.human,
  status: PlayerStatus.active,
  cash: 2000,
  position: 0,
  ownedPropertyIds: const <String>[],
  keepCardIds: const <String>[],
  inCucha: false,
  cuchaAttempts: 0,
  consecutiveDoubles: 0,
  connectivityStatus: ConnectivityStatus.online,
);

RulesCatalog syntheticRollCatalog() {
  const groupSizes = <int>[2, 3, 3, 3, 3, 3, 3, 2];
  final spaces = <BoardSpace>[BoardSpace(index: 0, type: BoardSpaceType.go)];
  final groups = <PropertyGroup>[];
  final properties = <String, PropertyEconomy>{};
  var streetIndex = 0;
  for (var groupIndex = 0; groupIndex < groupSizes.length; groupIndex += 1) {
    final ids = <String>[];
    for (var member = 0; member < groupSizes[groupIndex]; member += 1) {
      final id = 'street-${streetIndex.toString().padLeft(2, '0')}';
      ids.add(id);
      spaces.add(
        BoardSpace(
          index: streetIndex + 1,
          type: BoardSpaceType.street,
          propertyId: id,
          groupId: 'group-$groupIndex',
        ),
      );
      properties[id] = PropertyEconomy(
        propertyId: id,
        purchasePrice: 100 + streetIndex,
        baseRent: 10,
        completeGroupRent: 20,
        improvementRents: const <int>[30, 40, 50, 60, 70],
        buildCost: 50,
      );
      streetIndex += 1;
    }
    groups.add(
      PropertyGroup(
        groupId: 'group-$groupIndex',
        propertyIds: ids,
        starterEligibleExpress: ids.length == 3,
      ),
    );
  }
  for (var index = 0; index < 4; index += 1) {
    final id = 'transport-$index';
    spaces.add(
      BoardSpace(
        index: 23 + index,
        type: BoardSpaceType.transport,
        propertyId: id,
      ),
    );
    properties[id] = PropertyEconomy(
      propertyId: id,
      purchasePrice: 200,
      baseRent: 25,
      transportRentTable: const <int>[25, 50, 100, 200],
    );
  }
  for (var index = 0; index < 2; index += 1) {
    final id = 'utility-$index';
    spaces.add(
      BoardSpace(
        index: 27 + index,
        type: BoardSpaceType.utility,
        propertyId: id,
      ),
    );
    properties[id] = PropertyEconomy(
      propertyId: id,
      purchasePrice: 150,
      baseRent: 0,
      utilityMultiplierTable: const <int>[4, 10],
    );
  }
  const remaining = <BoardSpaceType>[
    BoardSpaceType.cardA,
    BoardSpaceType.cardB,
    BoardSpaceType.tax,
    BoardSpaceType.tax,
    BoardSpaceType.freeParking,
    BoardSpaceType.cucha,
    BoardSpaceType.goToCucha,
    BoardSpaceType.other,
    BoardSpaceType.other,
    BoardSpaceType.other,
    BoardSpaceType.other,
  ];
  var taxIndex = 0;
  for (var index = 0; index < remaining.length; index += 1) {
    final type = remaining[index];
    spaces.add(
      BoardSpace(
        index: 29 + index,
        type: type,
        ruleRef: type == BoardSpaceType.tax
            ? (taxIndex++ == 0 ? 'tax-a' : 'tax-b')
            : null,
      ),
    );
  }
  return RulesCatalog(
    rulesVersion: 'synthetic-rules-vp0',
    boardDefinitionVersion: 'synthetic-board-vp0',
    economyVersion: 'synthetic-economy-vp0',
    deckCatalogVersion: 'synthetic-decks-vp0',
    presetCatalogVersion: 'synthetic-presets-vp0',
    ruleFlags: const <String, bool>{'freeParkingPot': false},
    boardDefinition: BoardDefinition(
      boardId: 'synthetic-board',
      spaces: spaces,
      groups: groups,
    ),
    economyCatalog: EconomyCatalog(
      currencyUnit: 'synthetic-unit',
      salaryPassGo: 200,
      salaryExactGo: 200,
      cuchaExitCost: 50,
      mortgageRatioBps: 5000,
      liftMortgageInterestBps: 1000,
      improvementSellRatioBps: 5000,
      taxes: const <String, int>{'tax-a': 100, 'tax-b': 200},
      properties: properties,
    ),
    deckCatalog: DeckCatalog(
      cards: <DeckCard>[
        DeckCard(
          cardId: 'card-a',
          deckId: 'cards_a',
          effect: CardEffect(type: 'synthetic'),
        ),
        DeckCard(
          cardId: 'card-b',
          deckId: 'cards_b',
          effect: CardEffect(type: 'synthetic'),
        ),
      ],
    ),
    presets: <PresetDefinition>[
      PresetDefinition(
        presetId: 'express',
        status: PresetStatus.experimental,
        startingValue: 2000,
        starterPolicy: StarterPolicy.twoFromSameThreeGroupPaid,
        roundCap: 10,
        buildWithoutGroup: false,
        economyVersion: 'synthetic-economy-vp0',
        auctionPolicy: const <String, Object?>{'minimumIncrement': 10},
        reconnectPolicy: const <String, Object?>{'temporaryTakeover': true},
        mandatoryDecisionSeconds: 12,
        auctionBidSeconds: 6,
        auctionHardCapSeconds: 45,
        tradeResponseSeconds: 20,
        debtDecisionSeconds: 20,
        reconnectGraceSeconds: 20,
      ),
    ],
  );
}
