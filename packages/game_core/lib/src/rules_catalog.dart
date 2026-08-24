import 'canonical_rng.dart';
import 'domain_contracts.dart';

final class RulesCatalogViolation implements Exception {
  const RulesCatalogViolation(this.message);

  final String message;

  @override
  String toString() => 'RulesCatalogViolation: $message';
}

enum BoardSpaceType {
  go('go'),
  street('street'),
  transport('transport'),
  utility('utility'),
  cardA('cardA'),
  cardB('cardB'),
  tax('tax'),
  freeParking('freeParking'),
  cucha('cucha'),
  goToCucha('goToCucha'),
  other('other');

  const BoardSpaceType(this.wireValue);

  final String wireValue;

  bool get isProperty => this == street || this == transport || this == utility;
}

enum PresetStatus {
  stable('stable'),
  experimental('experimental');

  const PresetStatus(this.wireValue);

  final String wireValue;
}

enum StarterPolicy {
  nonePaid('nonePaid'),
  twoFromSameThreeGroupPaid('twoFromSameThreeGroupPaid'),
  oneRandomStreetPaid('oneRandomStreetPaid');

  const StarterPolicy(this.wireValue);

  final String wireValue;
}

final class BoardSpace {
  BoardSpace({
    required this.index,
    required this.type,
    this.propertyId,
    this.groupId,
    this.ruleRef,
  }) {
    if (index < 0 || index > 39) {
      throw const RulesCatalogViolation(
        'BoardSpace.index must be within 0..39',
      );
    }
    _optionalIdentifier(propertyId, 'propertyId');
    _optionalIdentifier(groupId, 'groupId');
    _optionalIdentifier(ruleRef, 'ruleRef');
    if (type.isProperty != (propertyId != null)) {
      throw const RulesCatalogViolation(
        'Only property spaces must define propertyId',
      );
    }
    if (type == BoardSpaceType.street && groupId == null) {
      throw const RulesCatalogViolation('A street must define groupId');
    }
    if (!type.isProperty && groupId != null) {
      throw const RulesCatalogViolation(
        'A non-property space cannot define groupId',
      );
    }
  }

  final int index;
  final BoardSpaceType type;
  final String? propertyId;
  final String? groupId;
  final String? ruleRef;

  Map<String, Object?> toJson() => <String, Object?>{
    'index': index,
    'type': type.wireValue,
    if (propertyId != null) 'propertyId': propertyId,
    if (groupId != null) 'groupId': groupId,
    if (ruleRef != null) 'ruleRef': ruleRef,
  };
}

final class PropertyGroup {
  PropertyGroup({
    required this.groupId,
    required List<String> propertyIds,
    required this.starterEligibleExpress,
  }) : propertyIds = _identifiers(propertyIds, 'propertyIds') {
    _identifier(groupId, 'groupId');
    if (propertyIds.isEmpty) {
      throw const RulesCatalogViolation(
        'A property group must contain properties',
      );
    }
  }

  final String groupId;
  final List<String> propertyIds;
  final bool starterEligibleExpress;

  Map<String, Object?> toJson() => <String, Object?>{
    'groupId': groupId,
    'propertyIds': propertyIds,
    'starterEligibleExpress': starterEligibleExpress,
  };
}

final class BoardDefinition {
  BoardDefinition({
    required this.boardId,
    required List<BoardSpace> spaces,
    required List<PropertyGroup> groups,
  }) : spaces = List.unmodifiable(spaces),
       groups = List.unmodifiable(groups) {
    _identifier(boardId, 'boardId');
    if (spaces.length != 40) {
      throw const RulesCatalogViolation(
        'BoardDefinition must contain exactly 40 spaces',
      );
    }
    final indexes = spaces.map((space) => space.index).toSet();
    if (indexes.length != 40 ||
        !List<int>.generate(40, (index) => index).every(indexes.contains)) {
      throw const RulesCatalogViolation(
        'Board indexes must be unique and contiguous from 0 through 39',
      );
    }
    final propertySpaces = spaces.where((space) => space.type.isProperty);
    _unique(
      propertySpaces.map((space) => space.propertyId!),
      'Board propertyId',
    );
    _unique(groups.map((group) => group.groupId), 'PropertyGroup.groupId');

    final streets = spaces
        .where((space) => space.type == BoardSpaceType.street)
        .toList(growable: false);
    if (streets.length != 22 ||
        spaces
                .where((space) => space.type == BoardSpaceType.transport)
                .length !=
            4 ||
        spaces.where((space) => space.type == BoardSpaceType.utility).length !=
            2) {
      throw const RulesCatalogViolation(
        'Board baseline requires 22 streets, 4 transports, and 2 utilities',
      );
    }
    final byPropertyId = <String, BoardSpace>{
      for (final space in propertySpaces) space.propertyId!: space,
    };
    for (final group in groups) {
      for (final propertyId in group.propertyIds) {
        final space = byPropertyId[propertyId];
        if (space == null || space.type != BoardSpaceType.street) {
          throw RulesCatalogViolation(
            'Group ${group.groupId} references a missing or non-street property',
          );
        }
        if (space.groupId != group.groupId) {
          throw RulesCatalogViolation(
            'Street $propertyId disagrees with group ${group.groupId}',
          );
        }
      }
    }
    for (final street in streets) {
      final matches = groups.where((group) => group.groupId == street.groupId);
      if (matches.length != 1 ||
          !matches.single.propertyIds.contains(street.propertyId)) {
        throw RulesCatalogViolation(
          'Street ${street.propertyId} must belong to exactly one group',
        );
      }
    }
    final groupSizes = groups.map((group) => group.propertyIds.length).toList()
      ..sort();
    const baselineGroupSizes = <int>[2, 2, 3, 3, 3, 3, 3, 3];
    if (!_sameList(groupSizes, baselineGroupSizes)) {
      throw const RulesCatalogViolation(
        'Street groups must match the structural 2/3/3/3/3/3/3/2 baseline',
      );
    }
  }

  final String boardId;
  final List<BoardSpace> spaces;
  final List<PropertyGroup> groups;

  Iterable<BoardSpace> get propertySpaces =>
      spaces.where((space) => space.type.isProperty);

  Map<String, Object?> toJson() => <String, Object?>{
    'boardId': boardId,
    'spaces': spaces.map((space) => space.toJson()).toList(growable: false),
    'groups': groups.map((group) => group.toJson()).toList(growable: false),
  };
}

final class PropertyEconomy {
  PropertyEconomy({
    required this.propertyId,
    required this.purchasePrice,
    required this.baseRent,
    this.completeGroupRent,
    List<int>? improvementRents,
    this.buildCost,
    List<int>? transportRentTable,
    List<int>? utilityMultiplierTable,
  }) : improvementRents = _optionalAmounts(
         improvementRents,
         'improvementRents',
       ),
       transportRentTable = _optionalAmounts(
         transportRentTable,
         'transportRentTable',
       ),
       utilityMultiplierTable = _optionalAmounts(
         utilityMultiplierTable,
         'utilityMultiplierTable',
       ) {
    _identifier(propertyId, 'propertyId');
    _nonNegative(purchasePrice, 'purchasePrice');
    _nonNegative(baseRent, 'baseRent');
    _optionalNonNegative(completeGroupRent, 'completeGroupRent');
    _optionalNonNegative(buildCost, 'buildCost');
    if (improvementRents != null && improvementRents.length != 5) {
      throw const RulesCatalogViolation(
        'improvementRents must contain levels 1 through 5',
      );
    }
  }

  final String propertyId;
  final int purchasePrice;
  final int baseRent;
  final int? completeGroupRent;
  final List<int>? improvementRents;
  final int? buildCost;
  final List<int>? transportRentTable;
  final List<int>? utilityMultiplierTable;

  Map<String, Object?> toJson() => <String, Object?>{
    'propertyId': propertyId,
    'purchasePrice': purchasePrice,
    'baseRent': baseRent,
    if (completeGroupRent != null) 'completeGroupRent': completeGroupRent,
    if (improvementRents != null) 'improvementRents': improvementRents,
    if (buildCost != null) 'buildCost': buildCost,
    if (transportRentTable != null) 'transportRentTable': transportRentTable,
    if (utilityMultiplierTable != null)
      'utilityMultiplierTable': utilityMultiplierTable,
  };
}

final class EconomyCatalog {
  EconomyCatalog({
    required this.currencyUnit,
    required this.salaryPassGo,
    required this.salaryExactGo,
    required this.cuchaExitCost,
    required this.mortgageRatioBps,
    required this.liftMortgageInterestBps,
    required this.improvementSellRatioBps,
    required Map<String, int> taxes,
    required Map<String, PropertyEconomy> properties,
  }) : taxes = Map.unmodifiable(Map<String, int>.from(taxes)),
       properties = Map.unmodifiable(
         Map<String, PropertyEconomy>.from(properties),
       ) {
    _identifier(currencyUnit, 'currencyUnit');
    _nonNegative(salaryPassGo, 'salaryPassGo');
    _nonNegative(salaryExactGo, 'salaryExactGo');
    _nonNegative(cuchaExitCost, 'cuchaExitCost');
    _basisPoints(mortgageRatioBps, 'mortgageRatioBps');
    _basisPoints(liftMortgageInterestBps, 'liftMortgageInterestBps');
    _basisPoints(improvementSellRatioBps, 'improvementSellRatioBps');
    for (final entry in taxes.entries) {
      _identifier(entry.key, 'taxes key');
      _nonNegative(entry.value, 'tax ${entry.key}');
    }
    for (final entry in properties.entries) {
      _identifier(entry.key, 'properties key');
      if (entry.key != entry.value.propertyId) {
        throw RulesCatalogViolation(
          'Economy key ${entry.key} does not match propertyId',
        );
      }
    }
  }

  final String currencyUnit;
  final int salaryPassGo;
  final int salaryExactGo;
  final int cuchaExitCost;
  final int mortgageRatioBps;
  final int liftMortgageInterestBps;
  final int improvementSellRatioBps;
  final Map<String, int> taxes;
  final Map<String, PropertyEconomy> properties;

  void validateAgainst(BoardDefinition board) {
    final boardIds = board.propertySpaces
        .map((space) => space.propertyId!)
        .toSet();
    if (!_sameSet(boardIds, properties.keys.toSet())) {
      throw const RulesCatalogViolation(
        'Board and Economy property references must be complete and exact',
      );
    }
    for (final space in board.propertySpaces) {
      final economy = properties[space.propertyId]!;
      switch (space.type) {
        case BoardSpaceType.street:
          if (economy.completeGroupRent == null ||
              economy.improvementRents?.length != 5 ||
              economy.buildCost == null ||
              economy.transportRentTable != null ||
              economy.utilityMultiplierTable != null) {
            throw RulesCatalogViolation(
              'Street ${space.propertyId} has an incompatible economy shape',
            );
          }
          break;
        case BoardSpaceType.transport:
          if (economy.transportRentTable == null ||
              economy.transportRentTable!.isEmpty ||
              economy.completeGroupRent != null ||
              economy.improvementRents != null ||
              economy.buildCost != null ||
              economy.utilityMultiplierTable != null) {
            throw RulesCatalogViolation(
              'Transport ${space.propertyId} has an incompatible economy shape',
            );
          }
          break;
        case BoardSpaceType.utility:
          if (economy.utilityMultiplierTable == null ||
              economy.utilityMultiplierTable!.isEmpty ||
              economy.completeGroupRent != null ||
              economy.improvementRents != null ||
              economy.buildCost != null ||
              economy.transportRentTable != null) {
            throw RulesCatalogViolation(
              'Utility ${space.propertyId} has an incompatible economy shape',
            );
          }
          break;
        default:
          throw const RulesCatalogViolation(
            'A non-property space reached economy validation',
          );
      }
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'currencyUnit': currencyUnit,
    'salaryPassGo': salaryPassGo,
    'salaryExactGo': salaryExactGo,
    'cuchaExitCost': cuchaExitCost,
    'mortgageRatioBps': mortgageRatioBps,
    'liftMortgageInterestBps': liftMortgageInterestBps,
    'improvementSellRatioBps': improvementSellRatioBps,
    'taxes': <String, Object?>{
      for (final key in _sorted(taxes.keys)) key: taxes[key],
    },
    'properties': <String, Object?>{
      for (final key in _sorted(properties.keys))
        key: properties[key]!.toJson(),
    },
  };
}

final class CardEffect {
  CardEffect({required this.type, Map<String, Object?> payload = const {}})
    : payload = _immutableJson(payload) {
    _identifier(type, 'effect.type');
  }

  final String type;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'payload': payload,
  };
}

final class DeckCard {
  DeckCard({required this.cardId, required this.deckId, required this.effect}) {
    _identifier(cardId, 'cardId');
    _identifier(deckId, 'deckId');
  }

  final String cardId;
  final String deckId;
  final CardEffect effect;

  Map<String, Object?> toJson() => <String, Object?>{
    'cardId': cardId,
    'deckId': deckId,
    'effect': effect.toJson(),
  };
}

final class DeckCatalog {
  DeckCatalog({required List<DeckCard> cards})
    : cards = List.unmodifiable(
        List<DeckCard>.from(cards)
          ..sort((left, right) => left.cardId.compareTo(right.cardId)),
      ) {
    if (cards.isEmpty) {
      throw const RulesCatalogViolation('DeckCatalog must contain cards');
    }
    _unique(cards.map((card) => card.cardId), 'cardId');
    if (cards.any(
      (card) => card.deckId != 'cards_a' && card.deckId != 'cards_b',
    )) {
      throw const RulesCatalogViolation(
        'Deck cards must reference cards_a or cards_b',
      );
    }
    if (!cards.any((card) => card.deckId == 'cards_a') ||
        !cards.any((card) => card.deckId == 'cards_b')) {
      throw const RulesCatalogViolation(
        'Synthetic or final catalog must include both logical decks',
      );
    }
  }

  final List<DeckCard> cards;

  Map<String, Object?> toJson() => <String, Object?>{
    'cards': cards.map((card) => card.toJson()).toList(growable: false),
  };
}

final class PresetDefinition {
  PresetDefinition({
    required this.presetId,
    required this.status,
    required this.startingValue,
    required this.starterPolicy,
    this.roundCap,
    required this.buildWithoutGroup,
    required this.economyVersion,
    required Map<String, Object?> auctionPolicy,
    required Map<String, Object?> reconnectPolicy,
    required this.mandatoryDecisionSeconds,
    required this.auctionBidSeconds,
    required this.auctionHardCapSeconds,
    required this.tradeResponseSeconds,
    required this.debtDecisionSeconds,
    required this.reconnectGraceSeconds,
  }) : auctionPolicy = _immutableJson(auctionPolicy),
       reconnectPolicy = _immutableJson(reconnectPolicy) {
    _identifier(presetId, 'presetId');
    _identifier(economyVersion, 'economyVersion');
    _nonNegative(startingValue, 'startingValue');
    if (roundCap != null && roundCap! <= 0) {
      throw const RulesCatalogViolation('roundCap must be positive when set');
    }
    for (final entry in <String, int>{
      'mandatoryDecisionSeconds': mandatoryDecisionSeconds,
      'auctionBidSeconds': auctionBidSeconds,
      'auctionHardCapSeconds': auctionHardCapSeconds,
      'tradeResponseSeconds': tradeResponseSeconds,
      'debtDecisionSeconds': debtDecisionSeconds,
      'reconnectGraceSeconds': reconnectGraceSeconds,
    }.entries) {
      if (entry.value <= 0) {
        throw RulesCatalogViolation('${entry.key} must be positive');
      }
    }
    if (auctionHardCapSeconds < auctionBidSeconds) {
      throw const RulesCatalogViolation(
        'auctionHardCapSeconds must cover auctionBidSeconds',
      );
    }
  }

  final String presetId;
  final PresetStatus status;
  final int startingValue;
  final StarterPolicy starterPolicy;
  final int? roundCap;
  final bool buildWithoutGroup;
  final String economyVersion;
  final Map<String, Object?> auctionPolicy;
  final Map<String, Object?> reconnectPolicy;
  final int mandatoryDecisionSeconds;
  final int auctionBidSeconds;
  final int auctionHardCapSeconds;
  final int tradeResponseSeconds;
  final int debtDecisionSeconds;
  final int reconnectGraceSeconds;

  Map<String, Object?> toJson() => <String, Object?>{
    'presetId': presetId,
    'status': status.wireValue,
    'startingValue': startingValue,
    'starterPolicy': starterPolicy.wireValue,
    if (roundCap != null) 'roundCap': roundCap,
    'buildWithoutGroup': buildWithoutGroup,
    'economyVersion': economyVersion,
    'auctionPolicy': auctionPolicy,
    'reconnectPolicy': reconnectPolicy,
    'mandatoryDecisionSeconds': mandatoryDecisionSeconds,
    'auctionBidSeconds': auctionBidSeconds,
    'auctionHardCapSeconds': auctionHardCapSeconds,
    'tradeResponseSeconds': tradeResponseSeconds,
    'debtDecisionSeconds': debtDecisionSeconds,
    'reconnectGraceSeconds': reconnectGraceSeconds,
  };
}

final class ResolvedPresetConfig {
  ResolvedPresetConfig._({
    required this.presetId,
    required this.presetCatalogVersion,
    required this.economyVersion,
    required this.startingValue,
    required this.starterPolicy,
    required this.roundCap,
    required this.buildWithoutGroup,
    required this.auctionPolicy,
    required this.reconnectPolicy,
    required this.mandatoryDecisionSeconds,
    required this.auctionBidSeconds,
    required this.auctionHardCapSeconds,
    required this.tradeResponseSeconds,
    required this.debtDecisionSeconds,
    required this.reconnectGraceSeconds,
  });

  factory ResolvedPresetConfig.freeze(
    PresetDefinition definition,
    String presetCatalogVersion,
  ) {
    _identifier(presetCatalogVersion, 'presetCatalogVersion');
    return ResolvedPresetConfig._(
      presetId: definition.presetId,
      presetCatalogVersion: presetCatalogVersion,
      economyVersion: definition.economyVersion,
      startingValue: definition.startingValue,
      starterPolicy: definition.starterPolicy,
      roundCap: definition.roundCap,
      buildWithoutGroup: definition.buildWithoutGroup,
      auctionPolicy: _immutableJson(definition.auctionPolicy),
      reconnectPolicy: _immutableJson(definition.reconnectPolicy),
      mandatoryDecisionSeconds: definition.mandatoryDecisionSeconds,
      auctionBidSeconds: definition.auctionBidSeconds,
      auctionHardCapSeconds: definition.auctionHardCapSeconds,
      tradeResponseSeconds: definition.tradeResponseSeconds,
      debtDecisionSeconds: definition.debtDecisionSeconds,
      reconnectGraceSeconds: definition.reconnectGraceSeconds,
    );
  }

  final String presetId;
  final String presetCatalogVersion;
  final String economyVersion;
  final int startingValue;
  final StarterPolicy starterPolicy;
  final int? roundCap;
  final bool buildWithoutGroup;
  final Map<String, Object?> auctionPolicy;
  final Map<String, Object?> reconnectPolicy;
  final int mandatoryDecisionSeconds;
  final int auctionBidSeconds;
  final int auctionHardCapSeconds;
  final int tradeResponseSeconds;
  final int debtDecisionSeconds;
  final int reconnectGraceSeconds;

  Map<String, Object?> toJson() => <String, Object?>{
    'presetId': presetId,
    'presetCatalogVersion': presetCatalogVersion,
    'economyVersion': economyVersion,
    'startingValue': startingValue,
    'starterPolicy': starterPolicy.wireValue,
    if (roundCap != null) 'roundCap': roundCap,
    'buildWithoutGroup': buildWithoutGroup,
    'auctionPolicy': auctionPolicy,
    'reconnectPolicy': reconnectPolicy,
    'mandatoryDecisionSeconds': mandatoryDecisionSeconds,
    'auctionBidSeconds': auctionBidSeconds,
    'auctionHardCapSeconds': auctionHardCapSeconds,
    'tradeResponseSeconds': tradeResponseSeconds,
    'debtDecisionSeconds': debtDecisionSeconds,
    'reconnectGraceSeconds': reconnectGraceSeconds,
  };

  String toCanonicalJson() => CanonicalDomainJson.encode(toJson());
}

final class RulesCatalog {
  RulesCatalog({
    required this.rulesVersion,
    required this.boardDefinitionVersion,
    required this.economyVersion,
    required this.deckCatalogVersion,
    required this.presetCatalogVersion,
    required Map<String, bool> ruleFlags,
    required this.boardDefinition,
    required this.economyCatalog,
    required this.deckCatalog,
    required List<PresetDefinition> presets,
  }) : ruleFlags = Map.unmodifiable(Map<String, bool>.from(ruleFlags)),
       presets = List.unmodifiable(presets) {
    for (final entry in <String, String>{
      'rulesVersion': rulesVersion,
      'boardDefinitionVersion': boardDefinitionVersion,
      'economyVersion': economyVersion,
      'deckCatalogVersion': deckCatalogVersion,
      'presetCatalogVersion': presetCatalogVersion,
    }.entries) {
      _identifier(entry.value, entry.key);
    }
    _unique(presets.map((preset) => preset.presetId), 'presetId');
    if (presets.isEmpty) {
      throw const RulesCatalogViolation('RulesCatalog requires presets');
    }
    economyCatalog.validateAgainst(boardDefinition);
    for (final key in ruleFlags.keys) {
      _identifier(key, 'ruleFlags key');
    }
    final taxRuleRefs = boardDefinition.spaces
        .where((space) => space.type == BoardSpaceType.tax)
        .map((space) => space.ruleRef)
        .toList(growable: false);
    if (taxRuleRefs.any((ruleRef) => ruleRef == null) ||
        !_sameSet(
          taxRuleRefs.cast<String>().toSet(),
          economyCatalog.taxes.keys.toSet(),
        )) {
      throw const RulesCatalogViolation(
        'Board tax ruleRefs and Economy taxes must be complete and exact',
      );
    }
    for (final preset in presets) {
      if (preset.economyVersion != economyVersion) {
        throw RulesCatalogViolation(
          'Preset ${preset.presetId} references another economy version',
        );
      }
      _validateStarterAffordability(preset);
    }
  }

  final String rulesVersion;
  final String boardDefinitionVersion;
  final String economyVersion;
  final String deckCatalogVersion;
  final String presetCatalogVersion;
  final Map<String, bool> ruleFlags;
  final BoardDefinition boardDefinition;
  final EconomyCatalog economyCatalog;
  final DeckCatalog deckCatalog;
  final List<PresetDefinition> presets;

  PresetDefinition preset(String presetId) {
    final matches = presets.where((preset) => preset.presetId == presetId);
    if (matches.isEmpty) {
      throw RulesCatalogViolation('Unknown presetId: $presetId');
    }
    return matches.single;
  }

  ResolvedPresetConfig resolvePreset(String presetId, int activeSeatCount) {
    final definition = preset(presetId);
    _validateCapacity(definition, activeSeatCount);
    return ResolvedPresetConfig.freeze(definition, presetCatalogVersion);
  }

  void _validateCapacity(PresetDefinition preset, int activeSeatCount) {
    if (activeSeatCount <= 0) {
      throw const RulesCatalogViolation('activeSeatCount must be positive');
    }
    final capacity = switch (preset.starterPolicy) {
      StarterPolicy.nonePaid => activeSeatCount,
      StarterPolicy.twoFromSameThreeGroupPaid =>
        boardDefinition.groups
            .where(
              (group) =>
                  group.propertyIds.length == 3 && group.starterEligibleExpress,
            )
            .length,
      StarterPolicy.oneRandomStreetPaid =>
        boardDefinition.spaces
            .where((space) => space.type == BoardSpaceType.street)
            .length,
    };
    if (capacity < activeSeatCount) {
      throw RulesCatalogViolation(
        'Preset ${preset.presetId} has insufficient unique starter assets',
      );
    }
  }

  void _validateStarterAffordability(PresetDefinition preset) {
    switch (preset.starterPolicy) {
      case StarterPolicy.nonePaid:
        return;
      case StarterPolicy.oneRandomStreetPaid:
        final streetIds = boardDefinition.spaces
            .where((space) => space.type == BoardSpaceType.street)
            .map((space) => space.propertyId!);
        if (streetIds.any(
          (id) =>
              economyCatalog.properties[id]!.purchasePrice >
              preset.startingValue,
        )) {
          throw RulesCatalogViolation(
            'Preset ${preset.presetId} cannot pay every eligible street',
          );
        }
        return;
      case StarterPolicy.twoFromSameThreeGroupPaid:
        final groups = boardDefinition.groups.where(
          (group) =>
              group.propertyIds.length == 3 && group.starterEligibleExpress,
        );
        if (groups.isEmpty) {
          throw RulesCatalogViolation(
            'Preset ${preset.presetId} has no eligible three-street groups',
          );
        }
        for (final group in groups) {
          final prices = group.propertyIds
              .map((id) => economyCatalog.properties[id]!.purchasePrice)
              .toList(growable: false);
          for (var excluded = 0; excluded < prices.length; excluded += 1) {
            final pairPrice = prices.indexed
                .where((entry) => entry.$1 != excluded)
                .fold<int>(0, (sum, entry) => sum + entry.$2);
            if (pairPrice > preset.startingValue) {
              throw RulesCatalogViolation(
                'Preset ${preset.presetId} cannot pay every eligible pair',
              );
            }
          }
        }
        return;
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'rulesVersion': rulesVersion,
    'boardDefinitionVersion': boardDefinitionVersion,
    'economyVersion': economyVersion,
    'deckCatalogVersion': deckCatalogVersion,
    'presetCatalogVersion': presetCatalogVersion,
    'ruleFlags': <String, Object?>{
      for (final key in _sorted(ruleFlags.keys)) key: ruleFlags[key],
    },
    'boardDefinition': boardDefinition.toJson(),
    'economyCatalog': economyCatalog.toJson(),
    'deckCatalog': deckCatalog.toJson(),
    'presets': presets.map((preset) => preset.toJson()).toList(growable: false),
  };

  String toCanonicalJson() => CanonicalDomainJson.encode(toJson());
}

final class StarterSeatAllocation {
  StarterSeatAllocation({
    required this.playerId,
    required List<String> propertyIds,
    required this.cash,
  }) : propertyIds = _identifiers(propertyIds, 'starter propertyIds') {
    _identifier(playerId, 'playerId');
    _nonNegative(cash, 'cash');
  }

  final String playerId;
  final List<String> propertyIds;
  final int cash;

  Map<String, Object?> toJson() => <String, Object?>{
    'playerId': playerId,
    'propertyIds': propertyIds,
    'cash': cash,
  };
}

final class StarterAllocationResult {
  const StarterAllocationResult({
    required this.allocations,
    required this.rngSuccessor,
    required this.candidatesConsumed,
  });

  final List<StarterSeatAllocation> allocations;
  final CanonicalRng rngSuccessor;
  final int candidatesConsumed;
}

StarterAllocationResult allocateStarterProperties({
  required RulesCatalog catalog,
  required ResolvedPresetConfig preset,
  required List<String> playerIdsInSeatOrder,
  required CanonicalRng rng,
}) {
  final playerIds = _identifiers(playerIdsInSeatOrder, 'playerIdsInSeatOrder');
  catalog._validateCapacity(
    _presetForCatalog(catalog, preset),
    playerIds.length,
  );
  var current = rng;
  var consumed = 0;
  final allocations = <StarterSeatAllocation>[];

  switch (preset.starterPolicy) {
    case StarterPolicy.nonePaid:
      for (final playerId in playerIds) {
        allocations.add(
          StarterSeatAllocation(
            playerId: playerId,
            propertyIds: const [],
            cash: preset.startingValue,
          ),
        );
      }
      break;
    case StarterPolicy.oneRandomStreetPaid:
      final streetIds = catalog.boardDefinition.spaces
          .where((space) => space.type == BoardSpaceType.street)
          .map((space) => space.propertyId!)
          .toList(growable: false);
      final shuffled = current.shuffle(RngStream.startingProperties, streetIds);
      current = shuffled.successor;
      consumed += shuffled.candidatesConsumed;
      for (var seat = 0; seat < playerIds.length; seat += 1) {
        final propertyId = shuffled.value[seat];
        final price =
            catalog.economyCatalog.properties[propertyId]!.purchasePrice;
        allocations.add(
          StarterSeatAllocation(
            playerId: playerIds[seat],
            propertyIds: <String>[propertyId],
            cash: preset.startingValue - price,
          ),
        );
      }
      break;
    case StarterPolicy.twoFromSameThreeGroupPaid:
      final groups = catalog.boardDefinition.groups
          .where(
            (group) =>
                group.propertyIds.length == 3 && group.starterEligibleExpress,
          )
          .toList(growable: false);
      final shuffled = current.shuffle(RngStream.startingProperties, groups);
      current = shuffled.successor;
      consumed += shuffled.candidatesConsumed;
      for (var seat = 0; seat < playerIds.length; seat += 1) {
        final group = shuffled.value[seat];
        final exclusion = current.nextInt(
          RngStream.startingProperties,
          group.propertyIds.length,
        );
        current = exclusion.successor;
        consumed += exclusion.candidatesConsumed;
        final selected = group.propertyIds.indexed
            .where((entry) => entry.$1 != exclusion.value)
            .map((entry) => entry.$2)
            .toList(growable: false);
        final price = selected.fold<int>(
          0,
          (sum, id) =>
              sum + catalog.economyCatalog.properties[id]!.purchasePrice,
        );
        allocations.add(
          StarterSeatAllocation(
            playerId: playerIds[seat],
            propertyIds: selected,
            cash: preset.startingValue - price,
          ),
        );
      }
      break;
  }

  return StarterAllocationResult(
    allocations: List.unmodifiable(allocations),
    rngSuccessor: current,
    candidatesConsumed: consumed,
  );
}

PresetDefinition _presetForCatalog(
  RulesCatalog catalog,
  ResolvedPresetConfig preset,
) {
  if (preset.presetCatalogVersion != catalog.presetCatalogVersion ||
      preset.economyVersion != catalog.economyVersion) {
    throw const RulesCatalogViolation(
      'Resolved preset versions do not match RulesCatalog',
    );
  }
  final definition = catalog.preset(preset.presetId);
  final expected = ResolvedPresetConfig.freeze(
    definition,
    catalog.presetCatalogVersion,
  );
  if (expected.toCanonicalJson() != preset.toCanonicalJson()) {
    throw const RulesCatalogViolation(
      'Resolved preset does not match the frozen catalog definition',
    );
  }
  return definition;
}

Map<String, Object?> _immutableJson(Map<String, Object?> value) =>
    Map.unmodifiable(_normalizeJson(value) as Map<String, Object?>);

Object? _normalizeJson(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is num) {
    throw const RulesCatalogViolation(
      'RulesCatalog numeric material must use integers only',
    );
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(_normalizeJson));
  }
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final key in keys) key: _normalizeJson(value[key]),
    });
  }
  throw RulesCatalogViolation(
    'Unsupported RulesCatalog JSON value: ${value.runtimeType}',
  );
}

List<String> _identifiers(List<String> values, String field) {
  for (final value in values) {
    _identifier(value, field);
  }
  _unique(values, field);
  return List.unmodifiable(values);
}

List<int>? _optionalAmounts(List<int>? values, String field) {
  if (values == null) {
    return null;
  }
  for (final value in values) {
    _nonNegative(value, field);
  }
  return List.unmodifiable(values);
}

void _identifier(String value, String field) {
  if (value.isEmpty) {
    throw RulesCatalogViolation('$field must not be empty');
  }
}

void _optionalIdentifier(String? value, String field) {
  if (value != null) {
    _identifier(value, field);
  }
}

void _nonNegative(int value, String field) {
  if (value < 0) {
    throw RulesCatalogViolation('$field must be non-negative');
  }
}

void _optionalNonNegative(int? value, String field) {
  if (value != null) {
    _nonNegative(value, field);
  }
}

void _basisPoints(int value, String field) {
  if (value < 0 || value > 10000) {
    throw RulesCatalogViolation('$field must be within 0..10000');
  }
}

void _unique(Iterable<Object> values, String field) {
  final materialized = values.toList(growable: false);
  if (materialized.toSet().length != materialized.length) {
    throw RulesCatalogViolation('$field contains duplicates');
  }
}

bool _sameList(List<int> left, List<int> right) =>
    left.length == right.length &&
    left.indexed.every((entry) => entry.$2 == right[entry.$1]);

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

List<String> _sorted(Iterable<String> values) => values.toList()..sort();
