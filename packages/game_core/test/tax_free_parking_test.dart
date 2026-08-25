import 'dart:convert';

import 'package:board_game_core/game_core.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  final catalog = _catalog();

  TaxFreeParkingEvaluation evaluate({
    PublicGameState? state,
    RulesCatalog? rules,
    int expectedStateVersion = 1,
    String playerId = 'p1',
    String operationId = 'landing-1',
  }) => TaxFreeParkingEngine.evaluate(
    operationId: operationId,
    expectedStateVersion: expectedStateVersion,
    playerId: playerId,
    state: state ?? _state(),
    catalog: rules ?? catalog,
    transitionTime: DateTime.parse('2026-08-25T05:30:00Z'),
  );

  group('US-019 tax to Free Parking pot', () {
    test('TAX-POT-01 uses the configured synthetic amount exactly once', () {
      final source = _state(cash: 500, position: 31, pot: 29);
      final plan = evaluate(state: source) as TaxFreeParkingPlan;

      expect(plan.kind, LandingEconomyKind.taxPaid);
      expect(plan.amount, 137);
      expect(_player(plan.stateAfter).cash, 363);
      expect(plan.stateAfter.freeParkingPot, 166);
      expect(plan.stateVersionBefore, 1);
      expect(plan.stateVersionAfter, 2);
      expect(plan.events.single.type, 'taxPaid');
      expect(plan.events.single.data['ruleRef'], 'synthetic-tax-a');
      expect(plan.stateAfter.turnState['phase'], 'turnResolved');
      expect(plan.stateAfter.header.rngCommitment, source.header.rngCommitment);
    });

    test('TAX-POT-04 opens the canonical DebtCase without partial debit', () {
      final source = _state(cash: 136, position: 31, pot: 29);
      final plan = evaluate(state: source) as TaxFreeParkingPlan;

      expect(plan.kind, LandingEconomyKind.taxDebtOpened);
      expect(_player(plan.stateAfter).cash, 136);
      expect(plan.stateAfter.freeParkingPot, 29);
      expect(plan.stateAfter.turnState['phase'], 'debtResolution');
      expect(plan.stateAfter.debtCase, <String, Object?>{
        'amountDue': 137,
        'creditor': const <String, Object?>{'kind': 'bank'},
        'debtCaseId': 'landing-1:debt',
        'debtorPlayerId': 'p1',
        'purpose': 'taxToFreeParkingPot',
        'ruleRef': 'synthetic-tax-a',
        'status': 'open',
      });
      expect(plan.stateAfter.pendingDecision, <String, Object?>{
        'allowedPlayerIds': const <Object?>['p1'],
        'createdAt': '2026-08-25T05:30:00.000Z',
        'deadlineAt': '2026-08-25T05:30:20.000Z',
        'decisionId': 'landing-1:debt:decision',
        'kind': 'debtResolution',
        'stateVersionCreated': 2,
        'timeoutPolicy': 'declareBankruptcy',
      });
      expect(plan.events.single.type, 'taxDebtOpened');
      expect(plan.stateAfter.players.any((player) => player.cash < 0), isFalse);
    });

    test('configured ruleRef selects the second synthetic tax amount', () {
      final plan = evaluate(
        state: _state(cash: 500, position: 32, pot: 7),
      ) as TaxFreeParkingPlan;

      expect(plan.amount, 263);
      expect(_player(plan.stateAfter).cash, 237);
      expect(plan.stateAfter.freeParkingPot, 270);
      expect(plan.events.single.data['ruleRef'], 'synthetic-tax-b');
    });

    test('POT-INV-01 conserves player cash plus pot across 64 states', () {
      for (var value = 0; value < 64; value += 1) {
        final source = _state(cash: 137 + value, position: 31, pot: value);
        final before = _economyTotal(source);
        final plan = evaluate(state: source) as TaxFreeParkingPlan;

        expect(_economyTotal(plan.stateAfter), before, reason: 'value=$value');
        expect(plan.stateAfter.freeParkingPot, value + 137);
        expect(_player(plan.stateAfter).cash, value);
      }
    });
  });

  group('US-019 Free Parking collection', () {
    test('FREE-POT-01 transfers the whole pot and resets it atomically', () {
      final source = _state(cash: 500, position: 33, pot: 263);
      final plan = evaluate(state: source) as TaxFreeParkingPlan;

      expect(plan.kind, LandingEconomyKind.freeParkingCollected);
      expect(plan.amount, 263);
      expect(_player(plan.stateAfter).cash, 763);
      expect(plan.stateAfter.freeParkingPot, 0);
      expect(_economyTotal(plan.stateAfter), _economyTotal(source));
      expect(plan.events.single.data, <String, Object?>{
        'amount': 263,
        'playerId': 'p1',
        'potAfter': 0,
        'potBefore': 263,
      });
    });

    test(
      'FREE-POT-02 accepts a zero pot as a deterministic no-delta effect',
      () {
        final source = _state(cash: 500, position: 33);
        final plan = evaluate(state: source) as TaxFreeParkingPlan;

        expect(plan.amount, 0);
        expect(_player(plan.stateAfter).cash, 500);
        expect(plan.stateAfter.freeParkingPot, 0);
        expect(plan.stateVersionAfter, 2);
        expect(plan.events.single.type, 'freeParkingCollected');
      },
    );

    test('64 pot sizes conserve value and never alter the RNG commitment', () {
      for (var pot = 0; pot < 64; pot += 1) {
        final source = _state(cash: 500, position: 33, pot: pot);
        final plan = evaluate(state: source) as TaxFreeParkingPlan;

        expect(_economyTotal(plan.stateAfter), _economyTotal(source));
        expect(_player(plan.stateAfter).cash, 500 + pot);
        expect(plan.stateAfter.freeParkingPot, 0);
        expect(
          plan.stateAfter.header.rngCommitment,
          source.header.rngCommitment,
        );
      }
    });
  });

  group('deterministic and zero-effect boundaries', () {
    test('same immutable input is byte-stable with a serialization golden', () {
      final source = _state(cash: 500, position: 33, pot: 263);
      final first = evaluate(state: source) as TaxFreeParkingPlan;
      final retry = evaluate(state: source) as TaxFreeParkingPlan;
      final digest = sha256.convert(utf8.encode(first.toCanonicalPublicJson()));

      expect(retry.toCanonicalPublicJson(), first.toCanonicalPublicJson());
      expect(
        digest.toString(),
        '6140b301c91702473d2e8173585042833b498dbb767a120962d295cc3a148894', // pragma: allowlist secret
      );
      expect(source.header.stateVersion, 1);
      expect(_player(source).cash, 500);
      expect(source.freeParkingPot, 263);
    });

    test('stale, wrong-player and open-decision attempts have zero effect', () {
      final source = _state(position: 33, pot: 263);
      final stale = evaluate(state: source, expectedStateVersion: 0);
      final wrongPlayer = evaluate(state: source, playerId: 'p2');
      final decision = evaluate(
        state: _state(
          position: 33,
          pot: 263,
          pendingDecision: const <String, Object?>{'kind': 'other'},
        ),
      );

      _expectRejected(stale, TaxFreeParkingErrorCode.staleVersion);
      _expectRejected(wrongPlayer, TaxFreeParkingErrorCode.notCurrentPlayer);
      _expectRejected(decision, TaxFreeParkingErrorCode.decisionRequired);
      expect(_player(source).cash, 500);
      expect(source.freeParkingPot, 263);
    });

    test('non-US-019 landing and disabled rule fail closed', () {
      final unsupported = evaluate(state: _state(position: 1));
      final disabled = evaluate(
        state: _state(position: 33),
        rules: _catalog(freeParkingPot: false),
      );
      final malformedTiming = evaluate(
        state: _state(cash: 1, position: 31, debtDecisionSeconds: 0),
      );

      _expectRejected(unsupported, TaxFreeParkingErrorCode.unsupportedLanding);
      _expectRejected(disabled, TaxFreeParkingErrorCode.invalidState);
      _expectRejected(malformedTiming, TaxFreeParkingErrorCode.invalidState);
    });
  });
}

void _expectRejected(
  TaxFreeParkingEvaluation result,
  TaxFreeParkingErrorCode code,
) {
  expect(result, isA<TaxFreeParkingRejection>());
  final rejection = result as TaxFreeParkingRejection;
  expect(rejection.errorCode, code);
  expect(rejection.stateVersionAfter, rejection.stateVersionBefore);
  expect(rejection.toPublicJson()['events'], isEmpty);
}

int _economyTotal(PublicGameState state) =>
    state.freeParkingPot +
    state.players.fold<int>(0, (sum, player) => sum + player.cash);

PlayerState _player(PublicGameState state) =>
    state.players.singleWhere((player) => player.playerId == 'p1');

PublicGameState _state({
  int cash = 500,
  int position = 31,
  int pot = 0,
  int debtDecisionSeconds = 20,
  Map<String, Object?>? pendingDecision,
}) => PublicGameState(
  header: GameStateHeader(
    schemaVersion: 1,
    stateVersion: 1,
    rulesVersion: 'synthetic-rules-us019',
    rngVersion: canonicalRngVersion,
    rngCommitment: List<String>.filled(64, '0').join(),
    gameId: 'game-us019',
    roomId: 'room-us019',
    status: GameStatus.active,
  ),
  presetConfig: <String, Object?>{
    'presetId': 'classic',
    'debtDecisionSeconds': debtDecisionSeconds,
  },
  roundState: const <String, Object?>{'round': 1},
  turnState: const <String, Object?>{
    'turnNumber': 1,
    'phase': 'resolvingLanding',
    'currentPlayerId': 'p1',
  },
  players: <PlayerState>[
    _makePlayer('p1', 0, cash, position),
    _makePlayer('p2', 1, 700, 0),
  ],
  seatControllers: <SeatControllerState>[
    for (final id in const <String>['p1', 'p2'])
      SeatControllerState(
        playerId: id,
        controller: SeatController.human,
        humanReclaimPending: false,
      ),
  ],
  board: const <String, Object?>{
    'boardId': 'synthetic-board-us019',
    'boardDefinitionVersion': 'synthetic-board-us019-v1',
  },
  ownership: const <String, Object?>{
    'byPropertyId': <String, Object?>{},
    'properties': <Object?>[],
  },
  bank: const <String, Object?>{'currencyUnit': 'synthetic-unit'},
  freeParkingPot: pot,
  deckPublicState: const <String, Object?>{},
  pendingDecision: pendingDecision,
  lastMutation: const <String, Object?>{'type': 'playerMoved'},
);

PlayerState _makePlayer(String id, int seat, int cash, int position) =>
    PlayerState(
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

RulesCatalog _catalog({bool freeParkingPot = true}) {
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
            ? (taxIndex++ == 0 ? 'synthetic-tax-a' : 'synthetic-tax-b')
            : null,
      ),
    );
  }
  return RulesCatalog(
    rulesVersion: 'synthetic-rules-us019',
    boardDefinitionVersion: 'synthetic-board-us019-v1',
    economyVersion: 'synthetic-economy-us019-v1',
    deckCatalogVersion: 'synthetic-decks-us019-v1',
    presetCatalogVersion: 'synthetic-presets-us019-v1',
    ruleFlags: <String, bool>{'freeParkingPot': freeParkingPot},
    boardDefinition: BoardDefinition(
      boardId: 'synthetic-board-us019',
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
      taxes: const <String, int>{
        'synthetic-tax-a': 137,
        'synthetic-tax-b': 263,
      },
      properties: properties,
    ),
    deckCatalog: DeckCatalog(
      cards: <DeckCard>[
        DeckCard(
          cardId: 'synthetic-card-a',
          deckId: 'cards_a',
          effect: CardEffect(type: 'synthetic'),
        ),
        DeckCard(
          cardId: 'synthetic-card-b',
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
        economyVersion: 'synthetic-economy-us019-v1',
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
