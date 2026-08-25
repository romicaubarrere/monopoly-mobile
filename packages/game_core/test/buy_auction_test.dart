import 'dart:convert';

import 'package:board_game_core/game_core.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  final catalog = _catalog();
  final transitionTime = DateTime.parse('2026-08-25T02:30:00Z');

  BuyAuctionEvaluation evaluate({
    required GameCommand command,
    required PublicGameState state,
    DateTime? at,
  }) => BuyAuctionEngine.evaluate(
    command: command,
    state: state,
    catalog: catalog,
    transitionTime: at ?? transitionTime,
  );

  group('controlled property offer', () {
    test('Buy atomically charges exact price and transfers ownership', () {
      final result = evaluate(
        command: _offerCommand(GameCommandType.buyProperty),
        state: _offerState(),
      );

      expect(result, isA<BuyAuctionPlan>());
      final plan = result as BuyAuctionPlan;
      expect(plan.stateVersionBefore, 1);
      expect(plan.stateVersionAfter, 2);
      final buyer = _playerIn(plan.stateAfter, 'p1');
      expect(buyer.cash, 1893);
      expect(buyer.ownedPropertyIds, <String>['street-07']);
      expect(plan.stateAfter.ownership['byPropertyId'], <String, Object?>{
        'street-07': 'p1',
      });
      expect(plan.stateAfter.pendingDecision, isNull);
      expect(plan.stateAfter.activeAuction, isNull);
      expect(plan.stateAfter.turnState['phase'], 'turnResolved');
      expect(plan.events.single.type, 'propertyPurchased');
    });

    test('Buy retry is byte-identical and does not mutate source state', () {
      final state = _offerState();
      final command = _offerCommand(GameCommandType.buyProperty);
      final first = evaluate(command: command, state: state);
      final retry = evaluate(command: command, state: state);

      expect(retry.toCanonicalPublicJson(), first.toCanonicalPublicJson());
      expect(_playerIn(state, 'p1').cash, 2000);
      expect(_playerIn(state, 'p1').ownedPropertyIds, isEmpty);
      expect(state.header.stateVersion, 1);
    });

    test('Buy public plan has a byte-stable golden', () {
      final plan = evaluate(
        command: _offerCommand(GameCommandType.buyProperty),
        state: _offerState(),
      );
      final digest = sha256.convert(utf8.encode(plan.toCanonicalPublicJson()));

      expect(
        digest.toString(),
        'd3a6f7422927db4f353cfb6e105b7834847bc0c024d554c7f4ddbed5feed3be3', // pragma: allowlist secret
      );
    });

    test('insufficient funds and stale version are zero-effect rejections', () {
      final poor = _offerState(p1Cash: 100);
      _expectRejected(
        evaluate(
          command: _offerCommand(GameCommandType.buyProperty),
          state: poor,
        ),
        BuyAuctionErrorCode.insufficientFunds,
      );
      expect(_playerIn(poor, 'p1').cash, 100);
      expect(_playerIn(poor, 'p1').ownedPropertyIds, isEmpty);

      _expectRejected(
        evaluate(
          command: _offerCommand(
            GameCommandType.buyProperty,
            expectedStateVersion: 0,
          ),
          state: _offerState(),
        ),
        BuyAuctionErrorCode.staleVersion,
      );
    });

    test('closed, wrong-actor and malformed offers fail closed', () {
      _expectRejected(
        evaluate(
          command: _offerCommand(GameCommandType.buyProperty),
          state: _offerState(phase: 'turnResolved'),
        ),
        BuyAuctionErrorCode.decisionClosed,
      );
      _expectRejected(
        evaluate(
          command: _offerCommand(
            GameCommandType.buyProperty,
            actorPlayerId: 'p2',
          ),
          state: _offerState(),
        ),
        BuyAuctionErrorCode.decisionClosed,
      );
      _expectRejected(
        evaluate(
          command: _command(
            type: GameCommandType.buyProperty,
            payload: const <String, Object?>{'propertyId': 'street-07'},
          ),
          state: _offerState(),
        ),
        BuyAuctionErrorCode.invalidCommand,
      );
    });
  });

  group('controlled auction', () {
    BuyAuctionPlan decline() => evaluate(
      command: _offerCommand(GameCommandType.declineProperty),
      state: _offerState(),
    ) as BuyAuctionPlan;

    test('Decline opens deterministic auction including the decliner', () {
      final plan = decline();

      expect(plan.stateAfter.header.stateVersion, 2);
      expect(plan.stateAfter.turnState['phase'], 'auction');
      expect(plan.stateAfter.activeAuction, <String, Object?>{
        'auctionId': 'cmd-1:auction',
        'currentBid': 0,
        'currentBidderPlayerId': 'p1',
        'eligiblePlayerIds': <Object?>['p1', 'p2'],
        'hardDeadlineAt': '2026-08-25T02:30:45.000Z',
        'minimumIncrement': 10,
        'passedPlayerIds': <Object?>[],
        'propertyId': 'street-07',
        'startedAt': '2026-08-25T02:30:00.000Z',
      });
      expect(
        plan.stateAfter.pendingDecision!['deadlineAt'],
        '2026-08-25T02:30:06.000Z',
      );
      expect(plan.events.map((event) => event.type), <String>[
        'propertyDeclined',
        'auctionStarted',
      ]);
    });

    test('bid rotates to next challenger and enforces increment and cash', () {
      final auction = decline().stateAfter;
      final bid = evaluate(
        command: _auctionCommand(
          GameCommandType.placeBid,
          actorPlayerId: 'p1',
          expectedStateVersion: 2,
          payload: const <String, Object?>{
            'auctionId': 'cmd-1:auction',
            'amount': 10,
          },
        ),
        state: auction,
        at: DateTime.parse('2026-08-25T02:30:02Z'),
      ) as BuyAuctionPlan;

      expect(bid.stateAfter.activeAuction!['currentBid'], 10);
      expect(bid.stateAfter.activeAuction!['leaderPlayerId'], 'p1');
      expect(bid.stateAfter.activeAuction!['currentBidderPlayerId'], 'p2');
      expect(bid.stateAfter.pendingDecision!['allowedPlayerIds'], <Object?>[
        'p2',
      ]);

      _expectRejected(
        evaluate(
          command: _auctionCommand(
            GameCommandType.placeBid,
            actorPlayerId: 'p2',
            expectedStateVersion: 3,
            payload: const <String, Object?>{
              'auctionId': 'cmd-1:auction',
              'amount': 19,
            },
          ),
          state: bid.stateAfter,
        ),
        BuyAuctionErrorCode.invalidBid,
      );
      _expectRejected(
        evaluate(
          command: _auctionCommand(
            GameCommandType.placeBid,
            actorPlayerId: 'p2',
            expectedStateVersion: 3,
            payload: const <String, Object?>{
              'auctionId': 'cmd-1:auction',
              'amount': 2001,
            },
          ),
          state: bid.stateAfter,
        ),
        BuyAuctionErrorCode.invalidBid,
      );
    });

    test('leader wins atomically when every challenger passes', () {
      final auction = decline().stateAfter;
      final bid = evaluate(
        command: _auctionCommand(
          GameCommandType.placeBid,
          actorPlayerId: 'p1',
          expectedStateVersion: 2,
          payload: const <String, Object?>{
            'auctionId': 'cmd-1:auction',
            'amount': 40,
          },
        ),
        state: auction,
      ) as BuyAuctionPlan;
      final won = evaluate(
        command: _auctionCommand(
          GameCommandType.passAuction,
          actorPlayerId: 'p2',
          expectedStateVersion: 3,
          payload: const <String, Object?>{'auctionId': 'cmd-1:auction'},
        ),
        state: bid.stateAfter,
      ) as BuyAuctionPlan;

      expect(won.stateAfter.activeAuction, isNull);
      expect(won.stateAfter.pendingDecision, isNull);
      expect(_playerIn(won.stateAfter, 'p1').cash, 1960);
      expect(_playerIn(won.stateAfter, 'p1').ownedPropertyIds, <String>[
        'street-07',
      ]);
      expect(won.events.last.type, 'auctionWon');
      expect(won.events.last.data, containsPair('winningBid', 40));
    });

    test('all players passing ends explicitly without a winner', () {
      final auction = decline().stateAfter;
      final firstPass = evaluate(
        command: _auctionCommand(
          GameCommandType.passAuction,
          actorPlayerId: 'p1',
          expectedStateVersion: 2,
          payload: const <String, Object?>{'auctionId': 'cmd-1:auction'},
        ),
        state: auction,
      ) as BuyAuctionPlan;
      expect(
        firstPass.stateAfter.activeAuction!['currentBidderPlayerId'],
        'p2',
      );

      final secondPass = evaluate(
        command: _auctionCommand(
          GameCommandType.passAuction,
          actorPlayerId: 'p2',
          expectedStateVersion: 3,
          payload: const <String, Object?>{'auctionId': 'cmd-1:auction'},
        ),
        state: firstPass.stateAfter,
      ) as BuyAuctionPlan;
      expect(secondPass.stateAfter.activeAuction, isNull);
      expect(secondPass.stateAfter.pendingDecision, isNull);
      expect(secondPass.events.last.type, 'auctionEndedWithoutWinner');
      expect(_playerIn(secondPass.stateAfter, 'p1').cash, 2000);
      expect(_playerIn(secondPass.stateAfter, 'p2').cash, 2000);
      expect(secondPass.stateAfter.ownership['byPropertyId'], isNull);
    });

    test('passed bidder cannot re-enter and non-current bidder cannot act', () {
      final auction = decline().stateAfter;
      _expectRejected(
        evaluate(
          command: _auctionCommand(
            GameCommandType.placeBid,
            actorPlayerId: 'p2',
            expectedStateVersion: 2,
            payload: const <String, Object?>{
              'auctionId': 'cmd-1:auction',
              'amount': 10,
            },
          ),
          state: auction,
        ),
        BuyAuctionErrorCode.decisionClosed,
      );

      final passed = evaluate(
        command: _auctionCommand(
          GameCommandType.passAuction,
          actorPlayerId: 'p1',
          expectedStateVersion: 2,
          payload: const <String, Object?>{'auctionId': 'cmd-1:auction'},
        ),
        state: auction,
      ) as BuyAuctionPlan;
      _expectRejected(
        evaluate(
          command: _auctionCommand(
            GameCommandType.placeBid,
            actorPlayerId: 'p1',
            expectedStateVersion: 3,
            payload: const <String, Object?>{
              'auctionId': 'cmd-1:auction',
              'amount': 10,
            },
          ),
          state: passed.stateAfter,
        ),
        BuyAuctionErrorCode.decisionClosed,
      );
    });

    test('auction retry reproduces exact state and event bytes', () {
      final auction = decline().stateAfter;
      final command = _auctionCommand(
        GameCommandType.placeBid,
        actorPlayerId: 'p1',
        expectedStateVersion: 2,
        payload: const <String, Object?>{
          'auctionId': 'cmd-1:auction',
          'amount': 10,
        },
      );
      final first = evaluate(command: command, state: auction);
      final retry = evaluate(command: command, state: auction);

      expect(retry.toCanonicalPublicJson(), first.toCanonicalPublicJson());
      expect(auction.activeAuction!['currentBid'], 0);
    });
  });
}

void _expectRejected(
  BuyAuctionEvaluation evaluation,
  BuyAuctionErrorCode errorCode,
) {
  expect(evaluation, isA<BuyAuctionRejection>());
  final rejection = evaluation as BuyAuctionRejection;
  expect(rejection.errorCode, errorCode);
  expect(rejection.stateVersionAfter, rejection.stateVersionBefore);
  expect(rejection.toPublicJson()['events'], isEmpty);
}

PlayerState _playerIn(PublicGameState state, String playerId) =>
    state.players.singleWhere((player) => player.playerId == playerId);

GameCommand _offerCommand(
  GameCommandType type, {
  int expectedStateVersion = 1,
  String actorPlayerId = 'p1',
}) => _command(
  type: type,
  expectedStateVersion: expectedStateVersion,
  actorPlayerId: actorPlayerId,
  payload: const <String, Object?>{
    'decisionId': 'cmd-roll-1:propertyOffer',
    'propertyId': 'street-07',
  },
);

GameCommand _auctionCommand(
  GameCommandType type, {
  required int expectedStateVersion,
  required String actorPlayerId,
  required Map<String, Object?> payload,
}) => _command(
  type: type,
  expectedStateVersion: expectedStateVersion,
  actorPlayerId: actorPlayerId,
  payload: payload,
);

GameCommand _command({
  required GameCommandType type,
  int expectedStateVersion = 1,
  String actorPlayerId = 'p1',
  required Map<String, Object?> payload,
}) => GameCommand(
  commandId: 'cmd-1',
  schemaVersion: 1,
  expectedStateVersion: expectedStateVersion,
  clientInstanceId: 'client-1',
  gameId: 'game-vp0',
  actorPlayerId: actorPlayerId,
  type: type,
  payload: payload,
);

PublicGameState _offerState({
  int p1Cash = 2000,
  String phase = 'awaitingPropertyDecision',
}) => PublicGameState(
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
  presetConfig: const <String, Object?>{
    'presetId': 'express',
    'auctionPolicy': <String, Object?>{'minimumIncrement': 10},
    'mandatoryDecisionSeconds': 12,
    'auctionBidSeconds': 6,
    'auctionHardCapSeconds': 45,
  },
  roundState: const <String, Object?>{'round': 1},
  turnState: <String, Object?>{
    'turnNumber': 1,
    'phase': phase,
    'currentPlayerId': 'p1',
    'landingPropertyId': 'street-07',
  },
  players: <PlayerState>[_player('p1', 0, p1Cash), _player('p2', 1, 2000)],
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
  pendingDecision: <String, Object?>{
    'decisionId': 'cmd-roll-1:propertyOffer',
    'kind': 'propertyOffer',
    'allowedPlayerIds': <Object?>['p1'],
    'stateVersionCreated': 1,
    'createdAt': '2026-08-25T02:29:48.000Z',
    'deadlineAt': '2026-08-25T02:30:00.000Z',
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

PlayerState _player(String playerId, int seat, int cash) => PlayerState(
  playerId: playerId,
  seat: seat,
  kind: PlayerKind.human,
  status: PlayerStatus.active,
  cash: cash,
  position: playerId == 'p1' ? 8 : 0,
  ownedPropertyIds: const <String>[],
  keepCardIds: const <String>[],
  inCucha: false,
  cuchaAttempts: 0,
  consecutiveDoubles: 0,
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
