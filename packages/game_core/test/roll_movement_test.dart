import 'dart:convert';

import 'package:board_game_core/game_core.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  final catalog = _catalog();
  final seed = List<int>.generate(32, (index) => index);
  final rng = CanonicalRng(seed: seed);

  RollMovementEvaluation evaluate({
    GameCommand? command,
    PublicGameState? state,
    CanonicalRng? random,
  }) => RollMovementEngine.evaluate(
    command: command ?? _command(),
    state: state ?? _state(rng: rng),
    catalog: catalog,
    rng: random ?? rng,
    transitionTime: DateTime.parse('2026-08-25T01:30:00Z'),
  );

  group('controlled VP0 Roll + movement', () {
    test('TV-23 prefix produces two D6 and a stable property boundary', () {
      final result = evaluate();

      expect(result, isA<RollMovementPlan>());
      final plan = result as RollMovementPlan;
      expect(<int>[plan.die1, plan.die2], <int>[6, 2]);
      expect(plan.total, 8);
      expect(plan.fromPosition, 0);
      expect(plan.toPosition, 8);
      expect(plan.propertyId, 'street-07');
      expect(plan.stateVersionBefore, 0);
      expect(plan.stateVersionAfter, 1);
      expect(plan.successorRng.counterFor(RngStream.dice), 2);
      expect(rng.counterFor(RngStream.dice), 0);

      final player = plan.stateAfter.players.singleWhere(
        (candidate) => candidate.playerId == 'p1',
      );
      expect(player.position, 8);
      expect(plan.stateAfter.turnState['phase'], 'awaitingPropertyDecision');
      expect(plan.stateAfter.turnState['landingPropertyId'], 'street-07');
      expect(plan.stateAfter.pendingDecision, <String, Object?>{
        'allowedPlayerIds': <Object?>['p1'],
        'createdAt': '2026-08-25T01:30:00.000Z',
        'deadlineAt': '2026-08-25T01:30:12.000Z',
        'decisionId': 'cmd-roll-1:propertyOffer',
        'kind': 'propertyOffer',
        'payload': <String, Object?>{
          'propertyId': 'street-07',
          'purchasePrice': 107,
        },
        'stateVersionCreated': 1,
        'timeoutPolicy': 'pass',
      });
      expect(plan.events.map((event) => event.type), <String>[
        'diceRolled',
        'playerMoved',
      ]);
    });

    test('public transition has a byte-stable SHA-256 golden', () {
      final plan = evaluate() as RollMovementPlan;
      final digest = sha256.convert(utf8.encode(plan.toCanonicalPublicJson()));

      expect(
        digest.toString(),
        '503260416287100b0c4c28709cabab1511cd4a9d248f671de9176935aa6eb721', // pragma: allowlist secret
      );
      expect(plan.toCanonicalPublicJson(), isNot(contains('streamCounters')));
      expect(plan.toCanonicalPublicJson(), isNot(contains('seed')));
      expect(
        plan.toCanonicalPublicJson(),
        isNot(contains('candidatesConsumed')),
      );
    });

    test('transaction retry reproduces public bytes and private successor', () {
      final first = evaluate() as RollMovementPlan;
      final retry = evaluate() as RollMovementPlan;

      expect(retry.toCanonicalPublicJson(), first.toCanonicalPublicJson());
      for (final stream in RngStream.values) {
        expect(
          retry.successorRng.counterFor(stream),
          first.successorRng.counterFor(stream),
        );
      }
      expect(rng.counterFor(RngStream.dice), 0);
    });

    test('64 deterministic seeds preserve movement and state invariants', () {
      var acceptedSeeds = 0;
      for (var seedIndex = 0; seedIndex < 64; seedIndex += 1) {
        final privateSeed = List<int>.generate(
          32,
          (index) => (seedIndex * 17 + index) & 0xff,
        );
        final initial = CanonicalRng(seed: privateSeed);
        final d1 = initial.nextInt(RngStream.dice, 6);
        final d2 = d1.successor.nextInt(RngStream.dice, 6);
        final total = d1.value + d2.value + 2;
        final source = 20 - total;
        final state = _state(rng: initial, p1Position: source);

        final first = evaluate(state: state, random: initial);
        final retry = evaluate(state: state, random: initial);
        if (d1.value == d2.value) {
          expect(
            first,
            isA<RollMovementRejection>(),
            reason: 'seed $seedIndex',
          );
          expect(
            (first as RollMovementRejection).errorCode,
            RollMovementErrorCode.unsupportedVp0Landing,
          );
          expect(retry.toCanonicalPublicJson(), first.toCanonicalPublicJson());
          expect(initial.counterFor(RngStream.dice), 0);
          continue;
        }
        expect(first, isA<RollMovementPlan>(), reason: 'seed $seedIndex');
        final plan = first as RollMovementPlan;
        acceptedSeeds += 1;
        expect(plan.die1, inInclusiveRange(1, 6));
        expect(plan.die2, inInclusiveRange(1, 6));
        expect(plan.toPosition, 20);
        expect(plan.propertyId, 'street-19');
        expect(plan.stateAfter.header.stateVersion, 1);
        expect(
          (retry as RollMovementPlan).toCanonicalPublicJson(),
          plan.toCanonicalPublicJson(),
        );
        expect(initial.counterFor(RngStream.dice), 0);
      }
      expect(acceptedSeeds, greaterThan(0));
    });
  });

  group('zero-effect rejection boundary', () {
    void expectRejected(
      RollMovementEvaluation result,
      RollMovementErrorCode code,
    ) {
      expect(result, isA<RollMovementRejection>());
      final rejection = result as RollMovementRejection;
      expect(rejection.errorCode, code);
      expect(rejection.stateVersionAfter, rejection.stateVersionBefore);
      expect(rejection.toPublicJson()['events'], isEmpty);
      expect(rng.counterFor(RngStream.dice), 0);
    }

    test('stale version rejects before RNG', () {
      expectRejected(
        evaluate(command: _command(expectedStateVersion: 1)),
        RollMovementErrorCode.staleVersion,
      );
    });

    test('non-turn and unknown actors reject before RNG', () {
      expectRejected(
        evaluate(command: _command(actorPlayerId: 'p2')),
        RollMovementErrorCode.notYourTurn,
      );
      expectRejected(
        evaluate(command: _command(actorPlayerId: 'ghost')),
        RollMovementErrorCode.actorNotInGame,
      );
    });

    test('invalid phase or open decision rejects before RNG', () {
      expectRejected(
        evaluate(
          state: _state(rng: rng, phase: 'awaitingPropertyDecision'),
        ),
        RollMovementErrorCode.invalidCommand,
      );
      expectRejected(
        evaluate(
          state: _state(
            rng: rng,
            pendingDecision: const <String, Object?>{'kind': 'cardChoice'},
          ),
        ),
        RollMovementErrorCode.decisionRequired,
      );
    });

    test('wrong command shape and game reject before RNG', () {
      expectRejected(
        evaluate(command: _command(type: GameCommandType.buyProperty)),
        RollMovementErrorCode.invalidCommand,
      );
      expectRejected(
        evaluate(command: _command(payload: const {'unexpected': 1})),
        RollMovementErrorCode.invalidCommand,
      );
      expectRejected(
        evaluate(command: _command(gameId: 'another-game')),
        RollMovementErrorCode.invalidCommand,
      );
    });

    test('RNG commitment mismatch rejects before draw', () {
      final other = CanonicalRng(seed: List<int>.filled(32, 9));
      expectRejected(
        evaluate(random: other),
        RollMovementErrorCode.rngCommitmentMismatch,
      );
      expect(other.counterFor(RngStream.dice), 0);
    });

    test('controlled fixture rejects owned, special and Salida landings', () {
      expectRejected(
        evaluate(
          state: _state(rng: rng, p1Owned: const ['street-07']),
        ),
        RollMovementErrorCode.unsupportedVp0Landing,
      );
      expectRejected(
        evaluate(state: _state(rng: rng, p1Position: 21)),
        RollMovementErrorCode.unsupportedVp0Landing,
      );
      expectRejected(
        evaluate(state: _state(rng: rng, p1Position: 35)),
        RollMovementErrorCode.unsupportedVp0Landing,
      );
    });

    test('controlled fixture rejects doubles and Cucha before expansion', () {
      final doublesRng = CanonicalRng(
        seed: seed,
        counters: const <RngStream, int>{RngStream.dice: 6},
      );
      final doublesState = _state(rng: doublesRng);
      final doubles = evaluate(state: doublesState, random: doublesRng);
      expect(doubles, isA<RollMovementRejection>());
      expect(
        (doubles as RollMovementRejection).errorCode,
        RollMovementErrorCode.unsupportedVp0Landing,
      );
      expect(doublesRng.counterFor(RngStream.dice), 6);

      expectRejected(
        evaluate(state: _state(rng: rng, p1InCucha: true)),
        RollMovementErrorCode.invalidCommand,
      );
      expectRejected(
        evaluate(state: _state(rng: rng, p1ConsecutiveDoubles: 1)),
        RollMovementErrorCode.invalidCommand,
      );
    });

    test('catalog and state version identities fail closed', () {
      expectRejected(
        evaluate(
          state: _state(rng: rng, rulesVersion: 'other-rules'),
        ),
        RollMovementErrorCode.invalidState,
      );
      expectRejected(
        evaluate(
          state: _state(rng: rng, boardId: 'other-board'),
        ),
        RollMovementErrorCode.invalidState,
      );
    });
  });
}

GameCommand _command({
  int expectedStateVersion = 0,
  String actorPlayerId = 'p1',
  String gameId = 'game-vp0',
  GameCommandType type = GameCommandType.rollDice,
  Map<String, Object?> payload = const <String, Object?>{},
}) => GameCommand(
  commandId: 'cmd-roll-1',
  schemaVersion: 1,
  expectedStateVersion: expectedStateVersion,
  clientInstanceId: 'client-1',
  gameId: gameId,
  actorPlayerId: actorPlayerId,
  type: type,
  payload: payload,
);

PublicGameState _state({
  required CanonicalRng rng,
  int p1Position = 0,
  List<String> p1Owned = const <String>[],
  bool p1InCucha = false,
  int p1ConsecutiveDoubles = 0,
  String phase = 'awaitingRoll',
  Map<String, Object?>? pendingDecision,
  String rulesVersion = 'synthetic-rules-vp0',
  String boardId = 'synthetic-board',
}) => PublicGameState(
  header: GameStateHeader(
    schemaVersion: 1,
    stateVersion: 0,
    rulesVersion: rulesVersion,
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
  players: <PlayerState>[
    _player(
      'p1',
      0,
      p1Position,
      p1Owned,
      inCucha: p1InCucha,
      consecutiveDoubles: p1ConsecutiveDoubles,
    ),
    _player('p2', 1, 0, const <String>[]),
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
  board: <String, Object?>{
    'boardId': boardId,
    'boardDefinitionVersion': 'synthetic-board-vp0',
  },
  ownership: const <String, Object?>{'properties': <Object?>[]},
  bank: const <String, Object?>{'currencyUnit': 'synthetic-unit'},
  freeParkingPot: 0,
  deckPublicState: const <String, Object?>{
    'cardsARemaining': 3,
    'cardsBRemaining': 3,
  },
  pendingDecision: pendingDecision,
  lastMutation: const <String, Object?>{
    'type': 'gameStarted',
    'commandId': 'cmd-start',
  },
);

PlayerState _player(
  String playerId,
  int seat,
  int position,
  List<String> ownedPropertyIds, {
  bool inCucha = false,
  int consecutiveDoubles = 0,
}) => PlayerState(
  playerId: playerId,
  seat: seat,
  kind: PlayerKind.human,
  status: PlayerStatus.active,
  cash: 2000,
  position: position,
  ownedPropertyIds: ownedPropertyIds,
  keepCardIds: const <String>[],
  inCucha: inCucha,
  cuchaAttempts: 0,
  consecutiveDoubles: consecutiveDoubles,
  connectivityStatus: ConnectivityStatus.online,
);

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
