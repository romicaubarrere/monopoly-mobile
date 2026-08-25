import 'dart:convert';

import 'package:board_game_core/game_core.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  final catalog = _catalog();

  BankruptcyEvaluation evaluate({
    required PublicGameState state,
    GameCommandType type = GameCommandType.declareBankruptcy,
    String creditorKind = 'player',
  }) => BankruptcyTransitionEngine.evaluate(
    command: _command(type),
    state: state,
    catalog: catalog,
  );

  test('exact cash pays the open debt and never declares bankruptcy', () {
    final plan = evaluate(
      state: _state(p1Cash: 100, amountDue: 100),
      type: GameCommandType.payDebt,
    ) as BankruptcyPlan;

    expect(plan.bankruptcyDeclared, isFalse);
    expect(_player(plan.stateAfter, 'p1').cash, 0);
    expect(_player(plan.stateAfter, 'p2').cash, 2100);
    expect(_player(plan.stateAfter, 'p1').status, PlayerStatus.active);
    expect(plan.stateAfter.debtCase, isNull);
    expect(plan.stateAfter.pendingDecision, isNull);
    expect(plan.stateVersionAfter, 2);
  });

  test('one unit short liquidates once, covers, and stops immediately', () {
    final plan = evaluate(
      state: _state(
        p1Cash: 99,
        amountDue: 100,
        assets: <PropertyState>[_property('street-00')],
      ),
    ) as BankruptcyPlan;

    expect(plan.bankruptcyDeclared, isFalse);
    expect(_player(plan.stateAfter, 'p1').cash, 49);
    expect(_propertyIn(plan.stateAfter, 'street-00').mortgaged, isTrue);
    final actions = plan.events.first.data['actions']! as List<Object?>;
    expect(actions, hasLength(1));
    expect((actions.single! as Map<String, Object?>)['type'], 'mortgage');
  });

  test('insufficient legal assets transfers everything to player creditor', () {
    final source = _state(
      p1Cash: 7,
      amountDue: 100,
      p1Cards: const <String>['keep-a'],
      assets: <PropertyState>[_property('street-00', mortgaged: true)],
    );
    final plan = evaluate(state: source) as BankruptcyPlan;

    expect(plan.bankruptcyDeclared, isTrue);
    expect(_player(plan.stateAfter, 'p1').status, PlayerStatus.bankrupt);
    expect(_player(plan.stateAfter, 'p1').cash, 0);
    expect(_player(plan.stateAfter, 'p2').cash, 2007);
    expect(_player(plan.stateAfter, 'p2').ownedPropertyIds, ['street-00']);
    expect(_player(plan.stateAfter, 'p2').keepCardIds, ['keep-a']);
    final property = _propertyIn(plan.stateAfter, 'street-00');
    expect(property.ownerPlayerId, 'p2');
    expect(property.mortgaged, isTrue);
    expect(plan.stateAfter.seatControllers.map((c) => c.playerId), ['p2']);
  });

  test('creditor-player branch conserves cash, properties, and keep cards', () {
    for (var cash = 0; cash < 64; cash += 1) {
      final source = _state(
        p1Cash: cash,
        amountDue: 500,
        p1Cards: const <String>['keep-a', 'keep-b'],
        assets: <PropertyState>[
          _property('street-00', mortgaged: true),
          _property(
            'transport-0',
            kind: PropertyKind.transport,
            mortgaged: true,
          ),
        ],
      );
      final beforeCash = source.players.fold<int>(
        0,
        (sum, player) => sum + player.cash,
      );
      final plan = evaluate(state: source) as BankruptcyPlan;
      final afterCash = plan.stateAfter.players.fold<int>(
        0,
        (sum, player) => sum + player.cash,
      );
      final owned = plan.stateAfter.players
          .expand((player) => player.ownedPropertyIds)
          .toList();
      final cards = plan.stateAfter.players
          .expand((player) => player.keepCardIds)
          .toList();

      expect(afterCash, beforeCash, reason: 'cash=$cash');
      expect(owned.toSet().length, owned.length, reason: 'cash=$cash');
      expect(owned.toSet(), {'street-00', 'transport-0'});
      expect(cards.toSet(), {'keep-a', 'keep-b'});
    }
  });

  test('bank creditor resets assets and queues canonical auctions', () {
    final plan = evaluate(
      state: _state(
        creditorKind: 'bank',
        includeThirdPlayer: true,
        amountDue: 500,
        p1Cards: const <String>['keep-a'],
        assets: <PropertyState>[
          _property('street-01', mortgaged: true),
          _property('street-00', mortgaged: true),
        ],
      ),
    ) as BankruptcyPlan;

    expect(plan.stateAfter.header.status, GameStatus.active);
    expect(plan.stateAfter.turnState['phase'], 'bankruptcyAuctions');
    expect(plan.stateAfter.bank['bankruptcyAuctionQueue'], [
      'street-00',
      'street-01',
    ]);
    expect(plan.stateAfter.bank['keepCardIds'], ['keep-a']);
    for (final id in <String>['street-00', 'street-01']) {
      expect(_propertyIn(plan.stateAfter, id).ownerPlayerId, isNull);
      expect(_propertyIn(plan.stateAfter, id).mortgaged, isFalse);
    }
  });

  test('bank creditor finishes Classic when one solvent player remains', () {
    final plan = evaluate(
      state: _state(
        creditorKind: 'bank',
        amountDue: 500,
        assets: <PropertyState>[_property('street-00', mortgaged: true)],
      ),
    ) as BankruptcyPlan;

    expect(plan.stateAfter.header.status, GameStatus.finished);
    expect(plan.stateAfter.result, <String, Object?>{
      'reason': 'lastSolventPlayer',
      'winnerPlayerId': 'p2',
    });
    expect(_player(plan.stateAfter, 'p2').status, PlayerStatus.finished);
    expect(plan.stateAfter.bank['bankruptcyAuctionQueue'], isNull);
    expect(plan.events.last.type, 'gameFinished');
  });

  test('liquidation uses rent-loss ratio then canonical property index', () {
    final plan = evaluate(
      state: _state(
        p1Cash: 99,
        amountDue: 100,
        assets: <PropertyState>[
          _property('street-00', level: 1),
          _property('street-01', level: 1),
        ],
      ),
    ) as BankruptcyPlan;
    final actions = plan.events.first.data['actions']! as List<Object?>;
    final first = actions.first! as Map<String, Object?>;

    expect(first['type'], 'sellImprovement');
    expect(first['propertyId'], 'street-00');
    expect(actions, hasLength(1));
  });

  test('same immutable input is byte-stable and source has zero mutation', () {
    final state = _state(
      amountDue: 500,
      assets: <PropertyState>[_property('street-00', mortgaged: true)],
    );
    final first = evaluate(state: state);
    final retry = evaluate(state: state);
    final digest = sha256.convert(utf8.encode(first.toCanonicalPublicJson()));

    expect(retry.toCanonicalPublicJson(), first.toCanonicalPublicJson());
    expect(digest.toString(), hasLength(64));
    expect(state.header.stateVersion, 1);
    expect(_player(state, 'p1').status, PlayerStatus.active);
    expect(state.debtCase, isNotNull);
  });

  test('stale and insufficient manual payment reject with zero effect', () {
    final state = _state(p1Cash: 99, amountDue: 100);
    final insufficient = evaluate(state: state, type: GameCommandType.payDebt);
    final stale = BankruptcyTransitionEngine.evaluate(
      command: _command(GameCommandType.declareBankruptcy, version: 0),
      state: state,
      catalog: catalog,
    );

    expect(
      (insufficient as BankruptcyRejection).errorCode,
      BankruptcyErrorCode.insufficientFunds,
    );
    expect(
      (stale as BankruptcyRejection).errorCode,
      BankruptcyErrorCode.staleVersion,
    );
    expect(insufficient.stateVersionAfter, 1);
    expect(stale.stateVersionAfter, 1);
  });
}

GameCommand _command(GameCommandType type, {int version = 1}) => GameCommand(
  commandId: 'cmd-bankruptcy-1',
  schemaVersion: 1,
  expectedStateVersion: version,
  clientInstanceId: 'client-1',
  gameId: 'game-vp0',
  actorPlayerId: 'p1',
  type: type,
  payload: const <String, Object?>{
    'debtCaseId': 'debt-1',
    'decisionId': 'debt-1:decision',
  },
);

PublicGameState _state({
  int p1Cash = 0,
  int amountDue = 100,
  String creditorKind = 'player',
  bool includeThirdPlayer = false,
  List<String> p1Cards = const <String>[],
  List<PropertyState> assets = const <PropertyState>[],
}) {
  final p1Assets = assets
      .where((asset) => asset.ownerPlayerId == 'p1')
      .toList();
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
    presetConfig: const <String, Object?>{'presetId': 'classic'},
    roundState: const <String, Object?>{'round': 1},
    turnState: const <String, Object?>{
      'turnNumber': 1,
      'phase': 'debtResolution',
      'currentPlayerId': 'p1',
    },
    players: <PlayerState>[
      _makePlayer(
        'p1',
        0,
        p1Cash,
        propertyIds: p1Assets.map((asset) => asset.propertyId).toList(),
        cards: p1Cards,
      ),
      _makePlayer('p2', 1, 2000),
      if (includeThirdPlayer) _makePlayer('p3', 2, 2000),
    ],
    seatControllers: <SeatControllerState>[
      for (final id in <String>['p1', 'p2', if (includeThirdPlayer) 'p3'])
        SeatControllerState(
          playerId: id,
          controller: SeatController.human,
          humanReclaimPending: false,
        ),
    ],
    board: const <String, Object?>{
      'boardId': 'synthetic-board',
      'boardDefinitionVersion': 'synthetic-board-vp0',
    },
    ownership: <String, Object?>{
      'byPropertyId': <String, Object?>{
        for (final asset in assets)
          if (asset.ownerPlayerId != null)
            asset.propertyId: asset.ownerPlayerId,
      },
      'properties': assets.map((asset) => asset.toJson()).toList(),
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
      'deadlineAt': '2026-08-25T04:30:00.000Z',
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

PlayerState _makePlayer(
  String id,
  int seat,
  int cash, {
  List<String> propertyIds = const <String>[],
  List<String> cards = const <String>[],
}) => PlayerState(
  playerId: id,
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

PropertyState _property(
  String id, {
  PropertyKind kind = PropertyKind.street,
  bool mortgaged = false,
  int level = 0,
}) => PropertyState(
  propertyId: id,
  kind: kind,
  ownerPlayerId: 'p1',
  mortgaged: mortgaged,
  improvementLevel: level,
);

PlayerState _player(PublicGameState state, String id) =>
    state.players.singleWhere((player) => player.playerId == id);

PropertyState _propertyIn(PublicGameState state, String id) {
  final raw = state.ownership['properties']! as List<Object?>;
  final value = raw.cast<Map<String, Object?>>().singleWhere(
    (item) => item['propertyId'] == id,
  );
  return PropertyState(
    propertyId: value['propertyId']! as String,
    kind: PropertyKind.values.singleWhere(
      (kind) => kind.wireValue == value['kind'],
    ),
    ownerPlayerId: value['ownerPlayerId'] as String?,
    mortgaged: value['mortgaged']! as bool,
    improvementLevel: value['improvementLevel']! as int,
  );
}

RulesCatalog _catalog() {
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
    ruleFlags: const <String, bool>{},
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
        presetId: 'classic',
        status: PresetStatus.stable,
        startingValue: 2000,
        starterPolicy: StarterPolicy.nonePaid,
        buildWithoutGroup: false,
        economyVersion: 'synthetic-economy-vp0',
        auctionPolicy: const <String, Object?>{'minimumIncrement': 10},
        reconnectPolicy: const <String, Object?>{},
        mandatoryDecisionSeconds: 12,
        auctionBidSeconds: 6,
        auctionHardCapSeconds: 45,
        tradeResponseSeconds: 12,
        debtDecisionSeconds: 12,
        reconnectGraceSeconds: 30,
      ),
    ],
  );
}
