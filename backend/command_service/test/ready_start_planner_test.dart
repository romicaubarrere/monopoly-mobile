import 'dart:convert';
import 'dart:io';

import 'package:board_command_service/command_service.dart';
import 'package:board_game_contracts/game_contracts.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  final catalog = syntheticReadyStartCatalog();
  final command = RoomCommand(
    commandId: 'cmd-start-vp0',
    schemaVersion: 1,
    expectedRoomVersion: 12,
    clientInstanceId: 'client-host',
    type: RoomCommandType.startGame,
    payload: const <String, Object?>{'roomId': 'room-vp0'},
  );
  const members = <ReadyRoomMember>[
    ReadyRoomMember(
      uid: 'uid-host',
      playerId: 'player-host',
      kind: PlayerKind.human,
      ready: true,
    ),
    ReadyRoomMember(
      uid: 'uid-b',
      playerId: 'player-b',
      kind: PlayerKind.human,
      ready: true,
    ),
    ReadyRoomMember(
      uid: 'bot-c',
      playerId: 'player-bot',
      kind: PlayerKind.bot,
      ready: true,
      botPolicyId: 'balanced-v1',
    ),
  ];

  ReadyStartPlan plan() => ReadyStartPlanner.plan(
    command: command,
    authenticatedActorUid: 'uid-host',
    hostUid: 'uid-host',
    gameId: 'game-vp0',
    presetId: 'express',
    members: members,
    catalog: catalog,
    secureSeed: List<int>.generate(32, (index) => index),
  );

  test('VP0 StartGame retry materializes the same complete candidate', () {
    final first = plan();
    final retry = plan();

    expect(
      first.publicState.toCanonicalJson(),
      retry.publicState.toCanonicalJson(),
    );
    expect(
      first.privateState.streamCounters,
      retry.privateState.streamCounters,
    );
    expect(first.privateState.cardsAOrder, retry.privateState.cardsAOrder);
    expect(first.privateState.cardsBOrder, retry.privateState.cardsBOrder);
    expect(first.safeResultSummary, retry.safeResultSummary);
  });

  test('shared VP0 persistence fixture is produced by the Dart planner', () {
    final result = plan();
    final fixture = _fixture();
    final expected = fixture['expectedPlan']! as Map<String, Object?>;

    expect(result.gameId, expected['gameId']);
    expect(result.publicState.header.stateVersion, expected['stateVersion']);
    expect(result.publicState.header.rulesVersion, expected['rulesVersion']);
    expect(result.publicState.header.rngVersion, expected['rngVersion']);
    expect(result.publicState.presetConfig, expected['presetConfig']);
    expect(result.safeResultSummary['seatOrder'], expected['seatOrder']);
    expect(
      result.safeResultSummary['starterAllocation'],
      expected['starterAllocation'],
    );
    expect(<String, int>{
      for (final entry in result.privateState.streamCounters.entries)
        entry.key.label: entry.value,
    }, expected['streamCounters']);
    expect(<String, Object?>{
      'cardsAOrder': result.privateState.cardsAOrder,
      'cardsBOrder': result.privateState.cardsBOrder,
    }, expected['privateDeckState']);
  });

  test(
    'initial state freezes catalog, turn, seats, ownership, and controllers',
    () {
      final result = plan();
      final state = result.publicState;

      expect(state.header.stateVersion, 0);
      expect(state.header.rulesVersion, 'synthetic-rules-vp0');
      expect(state.presetConfig['presetId'], 'express');
      expect(state.players, hasLength(3));
      expect(state.players.map((player) => player.seat), <int>[0, 1, 2]);
      expect(state.turnState['currentPlayerId'], state.players.first.playerId);
      expect(
        state.seatControllers
            .singleWhere((controller) => controller.playerId == 'player-bot')
            .controller,
        SeatController.bot,
      );

      final propertyIds = state.players
          .expand((player) => player.ownedPropertyIds)
          .toList(growable: false);
      expect(propertyIds, hasLength(6));
      expect(propertyIds.toSet(), hasLength(6));
      for (final player in state.players) {
        final nominalPaid = player.ownedPropertyIds.fold<int>(
          0,
          (sum, id) =>
              sum + catalog.economyCatalog.properties[id]!.purchasePrice,
        );
        expect(player.cash, 2000 - nominalPaid);
      }
    },
  );

  test('public state never includes seed, counters, or future deck order', () {
    final result = plan();
    final publicJson = result.publicState.toCanonicalJson();

    expect(publicJson, isNot(contains('seed')));
    expect(publicJson, isNot(contains('streamCounters')));
    expect(publicJson, isNot(contains('cardsAOrder')));
    expect(publicJson, isNot(contains('cardsBOrder')));
    expect(result.privateState.seed, hasLength(32));
    expect(result.privateState.cardsAOrder, hasLength(3));
    expect(result.privateState.cardsBOrder, hasLength(3));
  });

  test('safe result and room mutation converge both clients', () {
    final result = plan();
    final commandResult = result.commandResult(
      DateTime.parse('2026-08-25T00:10:00Z'),
    );

    expect(result.roomMutation, <String, Object?>{
      'status': 'active',
      'gameId': 'game-vp0',
      'roomVersion': 13,
      'frozenRulesVersion': 'synthetic-rules-vp0',
      'frozenPresetConfig': result.publicState.presetConfig,
    });
    expect(commandResult.gameId, 'game-vp0');
    expect(commandResult.roomVersionAfter, 13);
    expect(result.safeResultSummary['stateVersion'], 0);
    expect(result.safeResultSummary['seatOrder'], hasLength(3));
  });

  test('host and ready guards fail before producing RNG material', () {
    expect(
      () => ReadyStartPlanner.plan(
        command: command,
        authenticatedActorUid: 'uid-b',
        hostUid: 'uid-host',
        gameId: 'game-rejected',
        presetId: 'express',
        members: members,
        catalog: catalog,
        secureSeed: List<int>.filled(32, 7),
      ),
      throwsA(
        isA<ReadyStartViolation>().having(
          (error) => error.code,
          'code',
          'notRoomHost',
        ),
      ),
    );
    expect(
      () => ReadyStartPlanner.plan(
        command: command,
        authenticatedActorUid: 'uid-host',
        hostUid: 'uid-host',
        gameId: 'game-rejected',
        presetId: 'express',
        members: const <ReadyRoomMember>[
          ReadyRoomMember(
            uid: 'uid-host',
            playerId: 'player-host',
            kind: PlayerKind.human,
            ready: true,
          ),
          ReadyRoomMember(
            uid: 'uid-b',
            playerId: 'player-b',
            kind: PlayerKind.human,
            ready: false,
          ),
        ],
        catalog: catalog,
        secureSeed: List<int>.filled(32, 7),
      ),
      throwsA(
        isA<ReadyStartViolation>().having(
          (error) => error.code,
          'code',
          'notAllPlayersReady',
        ),
      ),
    );
  });
}

Map<String, Object?> _fixture() {
  final decoded =
      jsonDecode(
            File('test/fixtures/ready_start_plans.json').readAsStringSync(),
          )
          as List<Object?>;
  return decoded.cast<Map<String, Object?>>().single;
}

RulesCatalog syntheticReadyStartCatalog() {
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
        for (var index = 0; index < 3; index += 1)
          DeckCard(
            cardId: 'card-a-$index',
            deckId: 'cards_a',
            effect: CardEffect(type: 'synthetic'),
          ),
        for (var index = 0; index < 3; index += 1)
          DeckCard(
            cardId: 'card-b-$index',
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
