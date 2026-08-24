import 'dart:convert';

import 'package:board_game_core/game_core.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  group('RulesCatalog validation and serialization', () {
    test('resolves a byte-stable frozen preset golden', () {
      final resolved = _syntheticCatalog().resolvePreset('express', 4);

      expect(
        resolved.toCanonicalJson(),
        '{"auctionBidSeconds":6,"auctionHardCapSeconds":45,"auctionPolicy":{"minimumIncrement":10},"buildWithoutGroup":false,"debtDecisionSeconds":20,"economyVersion":"synthetic-economy-v1","mandatoryDecisionSeconds":12,"presetCatalogVersion":"synthetic-presets-v1","presetId":"express","reconnectGraceSeconds":20,"reconnectPolicy":{"temporaryTakeover":true},"roundCap":10,"starterPolicy":"twoFromSameThreeGroupPaid","startingValue":2000,"tradeResponseSeconds":20}',
      );
    });

    test('catalog bytes ignore source map insertion order', () {
      final first = _syntheticCatalog();
      final second = _syntheticCatalog(reverseMaps: true);

      expect(first.toCanonicalJson(), second.toCanonicalJson());
      expect(first.toCanonicalJson(), isNot(contains('seed')));
      expect(first.toCanonicalJson(), isNot(contains('streamCounters')));
      expect(first.toCanonicalJson(), isNot(contains('futureDeckOrder')));
    });

    test('full synthetic bundle matches its canonical byte KAT', () {
      final bytes = utf8.encode(_syntheticCatalog().toCanonicalJson());

      expect(
        sha256.convert(bytes).toString(),
        // Public SHA-256 KAT for the explicitly synthetic bundle bytes.
        '613a297c045c0f0f78d29f3478d7f03dd2d91cc35ee4f850e86a863d95563e68', // pragma: allowlist secret
      );
    });

    test('requires the exact 40/22/4/2 structural board baseline', () {
      final fixture = _boardParts();

      expect(
        () => BoardDefinition(
          boardId: 'invalid',
          spaces: fixture.spaces.sublist(0, 39),
          groups: fixture.groups,
        ),
        throwsA(isA<RulesCatalogViolation>()),
      );
      expect(
        () => BoardDefinition(
          boardId: 'invalid',
          spaces: <BoardSpace>[
            ...fixture.spaces.take(39),
            BoardSpace(index: 38, type: BoardSpaceType.other),
          ],
          groups: fixture.groups,
        ),
        throwsA(isA<RulesCatalogViolation>()),
      );
    });

    test('fails closed when Board and Economy references diverge', () {
      expect(
        () => _syntheticCatalog(dropEconomyPropertyId: 'street-00'),
        throwsA(isA<RulesCatalogViolation>()),
      );
    });

    test('rejects floating policy values and invalid timer bounds', () {
      expect(
        () => _preset(
          presetId: 'invalid-json',
          starterPolicy: StarterPolicy.nonePaid,
          auctionPolicy: const {'minimumIncrement': 1.5},
        ),
        throwsA(isA<RulesCatalogViolation>()),
      );
      expect(
        () => _preset(
          presetId: 'invalid-timer',
          starterPolicy: StarterPolicy.nonePaid,
          auctionBidSeconds: 10,
          auctionHardCapSeconds: 9,
        ),
        throwsA(isA<RulesCatalogViolation>()),
      );
      expect(
        () => _preset(
          presetId: 'invalid-cap',
          starterPolicy: StarterPolicy.nonePaid,
          roundCap: 0,
        ),
        throwsA(isA<RulesCatalogViolation>()),
      );
    });

    test('validates every starter candidate without price filtering', () {
      expect(
        () => _syntheticCatalog(
          purchasePriceOverrides: const {'street-02': 2100},
        ),
        throwsA(isA<RulesCatalogViolation>()),
      );
    });

    test('validates unique starter capacity at resolve time', () {
      final catalog = _syntheticCatalog();

      expect(
        () => catalog.resolvePreset('express', 7),
        throwsA(isA<RulesCatalogViolation>()),
      );
      expect(catalog.resolvePreset('express', 6).presetId, 'express');
    });
  });

  group('starter allocation properties', () {
    test('Express is deterministic, unique, same-group, and exactly paid', () {
      final catalog = _syntheticCatalog();
      final preset = catalog.resolvePreset('express', 4);
      const players = <String>['p0', 'p1', 'p2', 'p3'];

      for (var sample = 0; sample < 64; sample += 1) {
        final seed = List<int>.generate(32, (index) => (sample + index) & 0xff);
        final first = allocateStarterProperties(
          catalog: catalog,
          preset: preset,
          playerIdsInSeatOrder: players,
          rng: CanonicalRng(seed: seed),
        );
        final retry = allocateStarterProperties(
          catalog: catalog,
          preset: preset,
          playerIdsInSeatOrder: players,
          rng: CanonicalRng(seed: seed),
        );

        expect(_allocationJson(first), _allocationJson(retry));
        expect(
          first.rngSuccessor.counterFor(RngStream.startingProperties),
          retry.rngSuccessor.counterFor(RngStream.startingProperties),
        );
        final allPropertyIds = first.allocations
            .expand((allocation) => allocation.propertyIds)
            .toList(growable: false);
        expect(allPropertyIds.toSet().length, allPropertyIds.length);
        for (final allocation in first.allocations) {
          expect(allocation.propertyIds, hasLength(2));
          final groupIds = allocation.propertyIds
              .map(
                (id) => catalog.boardDefinition.spaces
                    .singleWhere((space) => space.propertyId == id)
                    .groupId,
              )
              .toSet();
          expect(groupIds, hasLength(1));
          final paid = allocation.propertyIds.fold<int>(
            0,
            (sum, id) =>
                sum + catalog.economyCatalog.properties[id]!.purchasePrice,
          );
          expect(allocation.cash, preset.startingValue - paid);
        }
      }
    });

    test('Rápida assigns one street per seat without replacement', () {
      final catalog = _syntheticCatalog();
      final preset = catalog.resolvePreset('quick', 4);
      final result = allocateStarterProperties(
        catalog: catalog,
        preset: preset,
        playerIdsInSeatOrder: const ['p0', 'p1', 'p2', 'p3'],
        rng: CanonicalRng(seed: List<int>.generate(32, (index) => index)),
      );

      final ids = result.allocations
          .expand((allocation) => allocation.propertyIds)
          .toList(growable: false);
      expect(ids, hasLength(4));
      expect(ids.toSet(), hasLength(4));
      expect(
        ids.every(
          (id) =>
              catalog.boardDefinition.spaces
                  .singleWhere((space) => space.propertyId == id)
                  .type ==
              BoardSpaceType.street,
        ),
        isTrue,
      );
    });

    test('Clásica consumes no starting-properties RNG', () {
      final catalog = _syntheticCatalog();
      final preset = catalog.resolvePreset('classic', 2);
      final result = allocateStarterProperties(
        catalog: catalog,
        preset: preset,
        playerIdsInSeatOrder: const ['p0', 'p1'],
        rng: CanonicalRng(seed: List<int>.filled(32, 7)),
      );

      expect(result.candidatesConsumed, 0);
      expect(result.rngSuccessor.counterFor(RngStream.startingProperties), 0);
      expect(
        result.allocations.every(
          (allocation) =>
              allocation.propertyIds.isEmpty && allocation.cash == 1500,
        ),
        isTrue,
      );
    });

    test('rejects a resolved preset from another catalog version', () {
      final first = _syntheticCatalog();
      final second = _syntheticCatalog(presetCatalogVersion: 'other-v1');
      final resolved = first.resolvePreset('classic', 2);

      expect(
        () => allocateStarterProperties(
          catalog: second,
          preset: resolved,
          playerIdsInSeatOrder: const ['p0', 'p1'],
          rng: CanonicalRng(seed: List<int>.filled(32, 8)),
        ),
        throwsA(isA<RulesCatalogViolation>()),
      );
    });
  });
}

String _allocationJson(StarterAllocationResult result) =>
    CanonicalDomainJson.encode(<String, Object?>{
      'allocations': result.allocations
          .map((allocation) => allocation.toJson())
          .toList(growable: false),
      'counter': result.rngSuccessor.counterFor(RngStream.startingProperties),
    });

RulesCatalog _syntheticCatalog({
  bool reverseMaps = false,
  String? dropEconomyPropertyId,
  Map<String, int> purchasePriceOverrides = const {},
  String presetCatalogVersion = 'synthetic-presets-v1',
}) {
  final board = _boardParts();
  final entries = <MapEntry<String, PropertyEconomy>>[];
  for (var index = 0; index < 22; index += 1) {
    final id = _streetId(index);
    entries.add(
      MapEntry(
        id,
        PropertyEconomy(
          propertyId: id,
          purchasePrice: purchasePriceOverrides[id] ?? 100 + index * 10,
          baseRent: 10 + index,
          completeGroupRent: 20 + index,
          improvementRents: <int>[
            30,
            40,
            50,
            60,
            70,
          ].map((rent) => rent + index).toList(growable: false),
          buildCost: 50 + index,
        ),
      ),
    );
  }
  for (var index = 0; index < 4; index += 1) {
    final id = 'transport-$index';
    entries.add(
      MapEntry(
        id,
        PropertyEconomy(
          propertyId: id,
          purchasePrice: 200,
          baseRent: 25,
          transportRentTable: const [25, 50, 100, 200],
        ),
      ),
    );
  }
  for (var index = 0; index < 2; index += 1) {
    final id = 'utility-$index';
    entries.add(
      MapEntry(
        id,
        PropertyEconomy(
          propertyId: id,
          purchasePrice: 150,
          baseRent: 0,
          utilityMultiplierTable: const [4, 10],
        ),
      ),
    );
  }
  if (dropEconomyPropertyId != null) {
    entries.removeWhere((entry) => entry.key == dropEconomyPropertyId);
  }
  if (reverseMaps) {
    entries.setAll(0, entries.reversed.toList(growable: false));
  }
  final properties = <String, PropertyEconomy>{
    for (final entry in entries) entry.key: entry.value,
  };
  final taxes = reverseMaps
      ? <String, int>{'luxury': 200, 'income': 100}
      : <String, int>{'income': 100, 'luxury': 200};
  final flags = reverseMaps
      ? <String, bool>{'freeParkingPot': true, 'salaryExactGo': true}
      : <String, bool>{'salaryExactGo': true, 'freeParkingPot': true};

  return RulesCatalog(
    rulesVersion: 'synthetic-rules-v1',
    boardDefinitionVersion: 'synthetic-board-v1',
    economyVersion: 'synthetic-economy-v1',
    deckCatalogVersion: 'synthetic-decks-v1',
    presetCatalogVersion: presetCatalogVersion,
    ruleFlags: flags,
    boardDefinition: BoardDefinition(
      boardId: 'synthetic-board',
      spaces: board.spaces,
      groups: board.groups,
    ),
    economyCatalog: EconomyCatalog(
      currencyUnit: 'synthetic-peso',
      salaryPassGo: 200,
      salaryExactGo: 250,
      cuchaExitCost: 50,
      mortgageRatioBps: 5000,
      liftMortgageInterestBps: 1000,
      improvementSellRatioBps: 5000,
      taxes: taxes,
      properties: properties,
    ),
    deckCatalog: DeckCatalog(
      cards: <DeckCard>[
        DeckCard(
          cardId: 'card-a-00',
          deckId: 'cards_a',
          effect: CardEffect(type: 'credit', payload: const {'amount': 10}),
        ),
        DeckCard(
          cardId: 'card-b-00',
          deckId: 'cards_b',
          effect: CardEffect(type: 'move', payload: const {'spaceIndex': 0}),
        ),
      ],
    ),
    presets: <PresetDefinition>[
      _preset(
        presetId: 'classic',
        status: PresetStatus.stable,
        startingValue: 1500,
        starterPolicy: StarterPolicy.nonePaid,
        roundCap: null,
        mandatoryDecisionSeconds: 60,
        auctionBidSeconds: 20,
        auctionHardCapSeconds: 180,
        tradeResponseSeconds: 120,
        debtDecisionSeconds: 120,
        reconnectGraceSeconds: 120,
      ),
      _preset(
        presetId: 'express',
        starterPolicy: StarterPolicy.twoFromSameThreeGroupPaid,
        startingValue: 2000,
        roundCap: 10,
        mandatoryDecisionSeconds: 12,
        auctionBidSeconds: 6,
        auctionHardCapSeconds: 45,
        tradeResponseSeconds: 20,
        debtDecisionSeconds: 20,
        reconnectGraceSeconds: 20,
      ),
      _preset(
        presetId: 'quick',
        starterPolicy: StarterPolicy.oneRandomStreetPaid,
        startingValue: 1500,
        roundCap: 15,
        mandatoryDecisionSeconds: 20,
        auctionBidSeconds: 10,
        auctionHardCapSeconds: 75,
        tradeResponseSeconds: 45,
        debtDecisionSeconds: 45,
        reconnectGraceSeconds: 45,
      ),
    ],
  );
}

PresetDefinition _preset({
  required String presetId,
  PresetStatus status = PresetStatus.experimental,
  int startingValue = 1500,
  required StarterPolicy starterPolicy,
  int? roundCap = 10,
  bool buildWithoutGroup = false,
  Map<String, Object?> auctionPolicy = const {'minimumIncrement': 10},
  Map<String, Object?> reconnectPolicy = const {'temporaryTakeover': true},
  int mandatoryDecisionSeconds = 12,
  int auctionBidSeconds = 6,
  int auctionHardCapSeconds = 45,
  int tradeResponseSeconds = 20,
  int debtDecisionSeconds = 20,
  int reconnectGraceSeconds = 20,
}) => PresetDefinition(
  presetId: presetId,
  status: status,
  startingValue: startingValue,
  starterPolicy: starterPolicy,
  roundCap: roundCap,
  buildWithoutGroup: buildWithoutGroup,
  economyVersion: 'synthetic-economy-v1',
  auctionPolicy: auctionPolicy,
  reconnectPolicy: reconnectPolicy,
  mandatoryDecisionSeconds: mandatoryDecisionSeconds,
  auctionBidSeconds: auctionBidSeconds,
  auctionHardCapSeconds: auctionHardCapSeconds,
  tradeResponseSeconds: tradeResponseSeconds,
  debtDecisionSeconds: debtDecisionSeconds,
  reconnectGraceSeconds: reconnectGraceSeconds,
);

({List<BoardSpace> spaces, List<PropertyGroup> groups}) _boardParts() {
  const groupSizes = <int>[2, 3, 3, 3, 3, 3, 3, 2];
  final spaces = <BoardSpace>[BoardSpace(index: 0, type: BoardSpaceType.go)];
  final groups = <PropertyGroup>[];
  var streetIndex = 0;
  for (var groupIndex = 0; groupIndex < groupSizes.length; groupIndex += 1) {
    final ids = <String>[];
    for (var member = 0; member < groupSizes[groupIndex]; member += 1) {
      final id = _streetId(streetIndex);
      ids.add(id);
      spaces.add(
        BoardSpace(
          index: streetIndex + 1,
          type: BoardSpaceType.street,
          propertyId: id,
          groupId: 'group-$groupIndex',
        ),
      );
      streetIndex += 1;
    }
    groups.add(
      PropertyGroup(
        groupId: 'group-$groupIndex',
        propertyIds: ids,
        starterEligibleExpress: groupSizes[groupIndex] == 3,
      ),
    );
  }
  for (var index = 0; index < 4; index += 1) {
    spaces.add(
      BoardSpace(
        index: 23 + index,
        type: BoardSpaceType.transport,
        propertyId: 'transport-$index',
      ),
    );
  }
  for (var index = 0; index < 2; index += 1) {
    spaces.add(
      BoardSpace(
        index: 27 + index,
        type: BoardSpaceType.utility,
        propertyId: 'utility-$index',
      ),
    );
  }
  const remainingTypes = <BoardSpaceType>[
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
  for (var index = 0; index < remainingTypes.length; index += 1) {
    final type = remainingTypes[index];
    spaces.add(
      BoardSpace(
        index: 29 + index,
        type: type,
        ruleRef: type == BoardSpaceType.tax
            ? (taxIndex++ == 0 ? 'income' : 'luxury')
            : null,
      ),
    );
  }
  return (spaces: spaces, groups: groups);
}

String _streetId(int index) => 'street-${index.toString().padLeft(2, '0')}';
