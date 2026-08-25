import 'domain_contracts.dart';
import 'rules_catalog.dart';

enum BankruptcyErrorCode {
  invalidCommand('invalidCommand'),
  staleVersion('staleVersion'),
  actorNotInGame('actorNotInGame'),
  decisionClosed('decisionClosed'),
  invalidState('invalidState'),
  insufficientFunds('insufficientFunds'),
  bankruptcyNotAllowed('bankruptcyNotAllowed');

  const BankruptcyErrorCode(this.wireValue);
  final String wireValue;
}

sealed class BankruptcyEvaluation {
  const BankruptcyEvaluation({
    required this.commandId,
    required this.stateVersionBefore,
  });
  final String commandId;
  final int stateVersionBefore;
  bool get accepted;
  int get stateVersionAfter;
  Map<String, Object?> toPublicJson();
  String toCanonicalPublicJson() => CanonicalDomainJson.encode(toPublicJson());
}

final class BankruptcyRejection extends BankruptcyEvaluation {
  const BankruptcyRejection({
    required super.commandId,
    required super.stateVersionBefore,
    required this.errorCode,
  });
  final BankruptcyErrorCode errorCode;
  @override
  bool get accepted => false;
  @override
  int get stateVersionAfter => stateVersionBefore;
  @override
  Map<String, Object?> toPublicJson() => <String, Object?>{
    'commandId': commandId,
    'status': 'rejected',
    'stateVersionBefore': stateVersionBefore,
    'stateVersionAfter': stateVersionAfter,
    'errorCode': errorCode.wireValue,
    'events': const <Object?>[],
  };
}

final class BankruptcyPlan extends BankruptcyEvaluation {
  BankruptcyPlan({
    required super.commandId,
    required super.stateVersionBefore,
    required this.stateAfter,
    required List<GameDomainEvent> events,
    required this.bankruptcyDeclared,
  }) : events = List.unmodifiable(events);
  final PublicGameState stateAfter;
  final List<GameDomainEvent> events;
  final bool bankruptcyDeclared;
  @override
  bool get accepted => true;
  @override
  int get stateVersionAfter => stateVersionBefore + 1;
  @override
  Map<String, Object?> toPublicJson() => <String, Object?>{
    'commandId': commandId,
    'status': 'accepted',
    'stateVersionBefore': stateVersionBefore,
    'stateVersionAfter': stateVersionAfter,
    'bankruptcyDeclared': bankruptcyDeclared,
    'events': events.map((event) => event.toJson()).toList(growable: false),
    'state': stateAfter.toJson(),
  };
}

/// Pure, deterministic debt-resolution and bankruptcy semantics.
///
/// Authority owns authentication, duplicate lookup, transactions and durable
/// retries. An accepted evaluation is therefore one atomic state+result plan.
abstract final class BankruptcyTransitionEngine {
  static BankruptcyEvaluation evaluate({
    required GameCommand command,
    required PublicGameState state,
    required RulesCatalog catalog,
  }) {
    final version = state.header.stateVersion;
    BankruptcyRejection reject(BankruptcyErrorCode code) => BankruptcyRejection(
      commandId: command.commandId,
      stateVersionBefore: version,
      errorCode: code,
    );
    if (command.gameId != state.header.gameId ||
        (command.type != GameCommandType.payDebt &&
            command.type != GameCommandType.declareBankruptcy)) {
      return reject(BankruptcyErrorCode.invalidCommand);
    }
    if (command.expectedStateVersion != version) {
      return reject(BankruptcyErrorCode.staleVersion);
    }
    if (!_catalogMatches(state, catalog)) {
      return reject(BankruptcyErrorCode.invalidState);
    }
    final debtor = _activePlayer(state, command.actorPlayerId);
    if (debtor == null) return reject(BankruptcyErrorCode.actorNotInGame);
    final context = _DebtContext.tryParse(state, command, debtor.playerId);
    if (context == null) return reject(BankruptcyErrorCode.decisionClosed);
    if (!_validCreditor(state, context) || !_validOwnership(state, catalog)) {
      return reject(BankruptcyErrorCode.invalidState);
    }

    if (command.type == GameCommandType.payDebt) {
      if (debtor.cash < context.amountDue) {
        return reject(BankruptcyErrorCode.insufficientFunds);
      }
      return _coveredPlan(
        command: command,
        state: state,
        context: context,
        debtorCashAfterLiquidation: debtor.cash,
        assets: _assets(state),
        actions: const <_LiquidationAction>[],
      );
    }

    final liquidation = _autoLiquidate(
      state: state,
      catalog: catalog,
      debtor: debtor,
      amountDue: context.amountDue,
    );
    if (debtor.cash + liquidation.cashRecovered >= context.amountDue) {
      return _coveredPlan(
        command: command,
        state: state,
        context: context,
        debtorCashAfterLiquidation: debtor.cash + liquidation.cashRecovered,
        assets: liquidation.assets,
        actions: liquidation.actions,
      );
    }
    if (liquidation.hasRemainingLegalValue) {
      return reject(BankruptcyErrorCode.bankruptcyNotAllowed);
    }
    return _bankruptcyPlan(
      command: command,
      state: state,
      context: context,
      debtorCash: debtor.cash + liquidation.cashRecovered,
      assets: liquidation.assets,
      actions: liquidation.actions,
    );
  }
}

BankruptcyPlan _coveredPlan({
  required GameCommand command,
  required PublicGameState state,
  required _DebtContext context,
  required int debtorCashAfterLiquidation,
  required List<PropertyState> assets,
  required List<_LiquidationAction> actions,
}) {
  final players = _settlePlayers(
    state.players,
    debtorId: context.debtorPlayerId,
    creditorPlayerId: context.creditorPlayerId,
    debtorCashAfter: debtorCashAfterLiquidation - context.amountDue,
    creditorCredit: context.amountDue,
  );
  final events = <GameDomainEvent>[
    if (actions.isNotEmpty) _liquidationEvent(context, actions),
    GameDomainEvent(
      type: 'debtPaid',
      data: <String, Object?>{
        'debtCaseId': context.debtCaseId,
        'debtorPlayerId': context.debtorPlayerId,
        'creditorKind': context.creditorKind,
        if (context.creditorPlayerId != null)
          'creditorPlayerId': context.creditorPlayerId,
        'amount': context.amountDue,
      },
    ),
  ];
  return BankruptcyPlan(
    commandId: command.commandId,
    stateVersionBefore: state.header.stateVersion,
    stateAfter: _copyState(
      state,
      command: command,
      players: players,
      ownership: _ownershipWithAssets(state.ownership, assets),
      turnState: <String, Object?>{...state.turnState, 'phase': 'turnResolved'},
    ),
    events: events,
    bankruptcyDeclared: false,
  );
}

BankruptcyPlan _bankruptcyPlan({
  required GameCommand command,
  required PublicGameState state,
  required _DebtContext context,
  required int debtorCash,
  required List<PropertyState> assets,
  required List<_LiquidationAction> actions,
}) {
  final debtorAssets = assets
      .where((asset) => asset.ownerPlayerId == context.debtorPlayerId)
      .toList(growable: false);
  final transferredToPlayer = context.creditorPlayerId != null;
  final propertyIds = debtorAssets.map((asset) => asset.propertyId).toList()
    ..sort();
  final debtor = state.players.singleWhere(
    (player) => player.playerId == context.debtorPlayerId,
  );
  var resultingAssets = assets;
  if (transferredToPlayer) {
    resultingAssets = <PropertyState>[
      for (final asset in assets)
        if (asset.ownerPlayerId == context.debtorPlayerId)
          PropertyState(
            propertyId: asset.propertyId,
            kind: asset.kind,
            ownerPlayerId: context.creditorPlayerId,
            mortgaged: asset.mortgaged,
            improvementLevel: 0,
          )
        else
          asset,
    ];
  } else {
    resultingAssets = <PropertyState>[
      for (final asset in assets)
        if (asset.ownerPlayerId == context.debtorPlayerId)
          PropertyState(
            propertyId: asset.propertyId,
            kind: asset.kind,
            mortgaged: false,
            improvementLevel: 0,
          )
        else
          asset,
    ];
  }
  final players = <PlayerState>[
    for (final player in state.players)
      if (player.playerId == context.debtorPlayerId)
        _copyPlayer(
          player,
          status: PlayerStatus.bankrupt,
          cash: 0,
          ownedPropertyIds: const <String>[],
          keepCardIds: const <String>[],
        )
      else if (player.playerId == context.creditorPlayerId)
        _copyPlayer(
          player,
          cash: player.cash + debtorCash,
          ownedPropertyIds: <String>[...player.ownedPropertyIds, ...propertyIds]
            ..sort(),
          keepCardIds: <String>[...player.keepCardIds, ...debtor.keepCardIds]
            ..sort(),
        )
      else
        player,
  ];
  final solvent = players
      .where((player) => player.status == PlayerStatus.active)
      .toList();
  final finished = solvent.length == 1;
  final finalPlayers = finished
      ? <PlayerState>[
          for (final player in players)
            if (player.playerId == solvent.single.playerId)
              _copyPlayer(player, status: PlayerStatus.finished)
            else
              player,
        ]
      : players;
  final bank = <String, Object?>{...state.bank};
  if (!transferredToPlayer) {
    final bankCards = _stringList(state.bank['keepCardIds']);
    bank['keepCardIds'] = <Object?>{
      ...bankCards,
      ...debtor.keepCardIds,
    }.toList()..sort();
    if (!finished && propertyIds.isNotEmpty) {
      bank['bankruptcyAuctionQueue'] = propertyIds;
    } else {
      bank.remove('bankruptcyAuctionQueue');
    }
  }
  final events = <GameDomainEvent>[
    if (actions.isNotEmpty) _liquidationEvent(context, actions),
    GameDomainEvent(
      type: 'bankruptcyDeclared',
      data: <String, Object?>{
        'debtCaseId': context.debtCaseId,
        'debtorPlayerId': context.debtorPlayerId,
        'creditorKind': context.creditorKind,
        if (context.creditorPlayerId != null)
          'creditorPlayerId': context.creditorPlayerId,
        'cashTransferred': debtorCash,
        'propertyIds': propertyIds,
        'keepCardIds': debtor.keepCardIds,
      },
    ),
    if (!transferredToPlayer && !finished && propertyIds.isNotEmpty)
      GameDomainEvent(
        type: 'bankruptcyAuctionsQueued',
        data: <String, Object?>{'propertyIds': propertyIds},
      ),
    if (finished)
      GameDomainEvent(
        type: 'gameFinished',
        data: <String, Object?>{'winnerPlayerId': solvent.single.playerId},
      ),
  ];
  return BankruptcyPlan(
    commandId: command.commandId,
    stateVersionBefore: state.header.stateVersion,
    stateAfter: _copyState(
      state,
      command: command,
      players: finalPlayers,
      seatControllers: state.seatControllers
          .where((controller) => controller.playerId != context.debtorPlayerId)
          .toList(growable: false),
      ownership: _ownershipWithAssets(state.ownership, resultingAssets),
      bank: bank,
      status: finished ? GameStatus.finished : GameStatus.active,
      result: finished
          ? <String, Object?>{
              'reason': 'lastSolventPlayer',
              'winnerPlayerId': solvent.single.playerId,
            }
          : null,
      turnState: <String, Object?>{
        ...state.turnState,
        'phase': finished
            ? 'gameFinished'
            : (!transferredToPlayer && propertyIds.isNotEmpty
                  ? 'bankruptcyAuctions'
                  : 'turnResolved'),
      },
    ),
    events: events,
    bankruptcyDeclared: true,
  );
}

_AutoLiquidation _autoLiquidate({
  required PublicGameState state,
  required RulesCatalog catalog,
  required PlayerState debtor,
  required int amountDue,
}) {
  final assets = _assets(state).toList();
  final actions = <_LiquidationAction>[];
  var recovered = 0;
  bool covered() => debtor.cash + recovered >= amountDue;

  void mortgageEligible({required bool outsideCompleteGroupsOnly}) {
    final ordered =
        assets.where((asset) {
          if (asset.ownerPlayerId != debtor.playerId || asset.mortgaged) {
            return false;
          }
          if (!_groupHasNoImprovements(asset, assets, catalog)) {
            return false;
          }
          final inComplete = _isInCompleteGroup(asset, debtor, catalog);
          return !outsideCompleteGroupsOnly || !inComplete;
        }).toList()..sort(
          (a, b) => _propertyIndex(
            a.propertyId,
            catalog,
          ).compareTo(_propertyIndex(b.propertyId, catalog)),
        );
    for (final asset in ordered) {
      if (covered()) break;
      final amount = _basisPoints(
        catalog.economyCatalog.properties[asset.propertyId]!.purchasePrice,
        catalog.economyCatalog.mortgageRatioBps,
      );
      final index = assets.indexWhere(
        (item) => item.propertyId == asset.propertyId,
      );
      assets[index] = PropertyState(
        propertyId: asset.propertyId,
        kind: asset.kind,
        ownerPlayerId: asset.ownerPlayerId,
        mortgaged: true,
        improvementLevel: 0,
      );
      recovered += amount;
      actions.add(_LiquidationAction('mortgage', asset.propertyId, amount));
    }
  }

  mortgageEligible(outsideCompleteGroupsOnly: true);
  while (!covered()) {
    final candidates = assets
        .where(
          (asset) =>
              asset.ownerPlayerId == debtor.playerId &&
              asset.improvementLevel > 0,
        )
        .toList();
    if (candidates.isEmpty) break;
    candidates.sort((left, right) {
      final leftValue = _improvementValue(left, catalog);
      final rightValue = _improvementValue(right, catalog);
      final ratio =
          leftValue.rentLoss * rightValue.cashRecovered -
          rightValue.rentLoss * leftValue.cashRecovered;
      if (ratio != 0) return ratio;
      return _propertyIndex(
        left.propertyId,
        catalog,
      ).compareTo(_propertyIndex(right.propertyId, catalog));
    });
    final asset = candidates.first;
    final value = _improvementValue(asset, catalog);
    final index = assets.indexWhere(
      (item) => item.propertyId == asset.propertyId,
    );
    assets[index] = PropertyState(
      propertyId: asset.propertyId,
      kind: asset.kind,
      ownerPlayerId: asset.ownerPlayerId,
      mortgaged: false,
      improvementLevel: asset.improvementLevel - 1,
    );
    recovered += value.cashRecovered;
    actions.add(
      _LiquidationAction(
        'sellImprovement',
        asset.propertyId,
        value.cashRecovered,
      ),
    );
  }
  if (!covered()) mortgageEligible(outsideCompleteGroupsOnly: false);
  final hasRemaining = assets.any(
    (asset) =>
        asset.ownerPlayerId == debtor.playerId &&
        (asset.improvementLevel > 0 || !asset.mortgaged),
  );
  return _AutoLiquidation(assets, actions, recovered, hasRemaining);
}

_ImprovementValue _improvementValue(PropertyState asset, RulesCatalog catalog) {
  final economy = catalog.economyCatalog.properties[asset.propertyId]!;
  final rents = economy.improvementRents!;
  final currentRent = rents[asset.improvementLevel - 1];
  final previousRent = asset.improvementLevel == 1
      ? (economy.completeGroupRent ?? economy.baseRent)
      : rents[asset.improvementLevel - 2];
  return _ImprovementValue(
    currentRent - previousRent,
    _basisPoints(
      economy.buildCost!,
      catalog.economyCatalog.improvementSellRatioBps,
    ),
  );
}

bool _isInCompleteGroup(
  PropertyState asset,
  PlayerState owner,
  RulesCatalog catalog,
) {
  for (final group in catalog.boardDefinition.groups) {
    if (group.propertyIds.contains(asset.propertyId)) {
      return owner.ownedPropertyIds.toSet().containsAll(group.propertyIds);
    }
  }
  return false;
}

bool _groupHasNoImprovements(
  PropertyState asset,
  List<PropertyState> assets,
  RulesCatalog catalog,
) {
  for (final group in catalog.boardDefinition.groups) {
    if (group.propertyIds.contains(asset.propertyId)) {
      return assets
          .where((item) => group.propertyIds.contains(item.propertyId))
          .every((item) => item.improvementLevel == 0);
    }
  }
  return asset.improvementLevel == 0;
}

int _propertyIndex(String propertyId, RulesCatalog catalog) => catalog
    .boardDefinition
    .spaces
    .singleWhere((space) => space.propertyId == propertyId)
    .index;

int _basisPoints(int amount, int bps) => amount * bps ~/ 10000;

GameDomainEvent _liquidationEvent(
  _DebtContext context,
  List<_LiquidationAction> actions,
) => GameDomainEvent(
  type: 'autoLiquidationApplied',
  data: <String, Object?>{
    'debtCaseId': context.debtCaseId,
    'actions': actions.map((action) => action.toJson()).toList(growable: false),
    'cashRecovered': actions.fold<int>(
      0,
      (sum, action) => sum + action.cashRecovered,
    ),
  },
);

bool _catalogMatches(PublicGameState state, RulesCatalog catalog) =>
    state.header.status == GameStatus.active &&
    state.header.rulesVersion == catalog.rulesVersion &&
    state.board['boardId'] == catalog.boardDefinition.boardId &&
    state.board['boardDefinitionVersion'] == catalog.boardDefinitionVersion;

PlayerState? _activePlayer(PublicGameState state, String playerId) {
  for (final player in state.players) {
    if (player.playerId == playerId && player.status == PlayerStatus.active) {
      return player;
    }
  }
  return null;
}

bool _validCreditor(PublicGameState state, _DebtContext context) =>
    context.creditorKind == 'bank' ||
    (context.creditorPlayerId != context.debtorPlayerId &&
        _activePlayer(state, context.creditorPlayerId!) != null);

bool _validOwnership(PublicGameState state, RulesCatalog catalog) {
  try {
    final assets = _assets(state);
    final assetIds = assets.map((asset) => asset.propertyId).toList();
    if (assetIds.toSet().length != assetIds.length) {
      return false;
    }
    final playerIds = state.players.map((player) => player.playerId).toSet();
    if (assets.any(
      (asset) =>
          asset.ownerPlayerId != null &&
          !playerIds.contains(asset.ownerPlayerId),
    )) {
      return false;
    }
    final byId = <String, String>{
      for (final asset in assets)
        if (asset.ownerPlayerId != null) asset.propertyId: asset.ownerPlayerId!,
    };
    final raw = state.ownership['byPropertyId'];
    if (raw is! Map<String, Object?> || raw.length != byId.length) {
      return false;
    }
    for (final entry in byId.entries) {
      if (raw[entry.key] != entry.value ||
          !catalog.economyCatalog.properties.containsKey(entry.key)) {
        return false;
      }
    }
    for (final player in state.players) {
      final ids = byId.entries
          .where((entry) => entry.value == player.playerId)
          .map((entry) => entry.key)
          .toSet();
      if (ids.length != player.ownedPropertyIds.length ||
          !ids.containsAll(player.ownedPropertyIds)) {
        return false;
      }
    }
    final playerCards = state.players
        .expand((player) => player.keepCardIds)
        .toList(growable: false);
    final bankCards = _stringList(state.bank['keepCardIds']);
    final allCards = <String>[...playerCards, ...bankCards];
    if (allCards.toSet().length != allCards.length) {
      return false;
    }
    return true;
  } on Object {
    return false;
  }
}

List<PropertyState> _assets(PublicGameState state) {
  final raw = state.ownership['properties'];
  if (raw is! List<Object?>) {
    throw const DomainContractViolation('ownership.properties missing');
  }
  return raw
      .map((value) {
        if (value is! Map<String, Object?>) {
          throw const DomainContractViolation('invalid property state');
        }
        return PropertyState(
          propertyId: value['propertyId']! as String,
          kind: PropertyKind.values.singleWhere(
            (kind) => kind.wireValue == value['kind'],
          ),
          ownerPlayerId: value['ownerPlayerId'] as String?,
          mortgaged: value['mortgaged']! as bool,
          improvementLevel: value['improvementLevel']! as int,
        );
      })
      .toList(growable: false);
}

Map<String, Object?> _ownershipWithAssets(
  Map<String, Object?> ownership,
  List<PropertyState> assets,
) => <String, Object?>{
  ...ownership,
  'byPropertyId': <String, Object?>{
    for (final asset in assets)
      if (asset.ownerPlayerId != null) asset.propertyId: asset.ownerPlayerId,
  },
  'properties': assets.map((asset) => asset.toJson()).toList(growable: false),
};

List<PlayerState> _settlePlayers(
  List<PlayerState> players, {
  required String debtorId,
  required String? creditorPlayerId,
  required int debtorCashAfter,
  required int creditorCredit,
}) => <PlayerState>[
  for (final player in players)
    if (player.playerId == debtorId)
      _copyPlayer(player, cash: debtorCashAfter)
    else if (player.playerId == creditorPlayerId)
      _copyPlayer(player, cash: player.cash + creditorCredit)
    else
      player,
];

PlayerState _copyPlayer(
  PlayerState player, {
  PlayerStatus? status,
  int? cash,
  List<String>? ownedPropertyIds,
  List<String>? keepCardIds,
}) => PlayerState(
  playerId: player.playerId,
  seat: player.seat,
  kind: player.kind,
  status: status ?? player.status,
  cash: cash ?? player.cash,
  position: player.position,
  ownedPropertyIds: ownedPropertyIds ?? player.ownedPropertyIds,
  keepCardIds: keepCardIds ?? player.keepCardIds,
  inCucha: player.inCucha,
  cuchaAttempts: player.cuchaAttempts,
  consecutiveDoubles: player.consecutiveDoubles,
  connectivityStatus: player.connectivityStatus,
);

PublicGameState _copyState(
  PublicGameState state, {
  required GameCommand command,
  required List<PlayerState> players,
  required Map<String, Object?> ownership,
  required Map<String, Object?> turnState,
  List<SeatControllerState>? seatControllers,
  Map<String, Object?>? bank,
  GameStatus? status,
  Map<String, Object?>? result,
}) => PublicGameState(
  header: GameStateHeader(
    schemaVersion: state.header.schemaVersion,
    stateVersion: state.header.stateVersion + 1,
    rulesVersion: state.header.rulesVersion,
    rngVersion: state.header.rngVersion,
    rngCommitment: state.header.rngCommitment,
    gameId: state.header.gameId,
    roomId: state.header.roomId,
    status: status ?? state.header.status,
  ),
  presetConfig: state.presetConfig,
  roundState: state.roundState,
  turnState: turnState,
  players: players,
  seatControllers: seatControllers ?? state.seatControllers,
  board: state.board,
  ownership: ownership,
  bank: bank ?? state.bank,
  freeParkingPot: state.freeParkingPot,
  deckPublicState: state.deckPublicState,
  activeAuction: state.activeAuction,
  result: result,
  lastMutation: <String, Object?>{
    'type': 'bankruptcyTransition',
    'commandId': command.commandId,
    'actorPlayerId': command.actorPlayerId,
  },
);

List<String> _stringList(Object? raw) => raw is List<Object?>
    ? raw.whereType<String>().toList(growable: false)
    : const <String>[];

final class _DebtContext {
  const _DebtContext(
    this.debtCaseId,
    this.debtorPlayerId,
    this.creditorKind,
    this.creditorPlayerId,
    this.amountDue,
  );
  final String debtCaseId;
  final String debtorPlayerId;
  final String creditorKind;
  final String? creditorPlayerId;
  final int amountDue;

  static _DebtContext? tryParse(
    PublicGameState state,
    GameCommand command,
    String actorId,
  ) {
    final debt = state.debtCase;
    final decision = state.pendingDecision;
    if (debt == null ||
        decision == null ||
        state.activeAuction != null ||
        state.activeTrade != null ||
        debt['status'] != 'open' ||
        debt['debtorPlayerId'] != actorId ||
        decision['kind'] != 'debtResolution' ||
        decision['stateVersionCreated'] != state.header.stateVersion ||
        decision['allowedPlayerIds'] is! List<Object?> ||
        !(decision['allowedPlayerIds'] as List<Object?>).contains(actorId)) {
      return null;
    }
    final debtCaseId = debt['debtCaseId'];
    final decisionId = decision['decisionId'];
    final amount = debt['amountDue'];
    final creditor = debt['creditor'];
    if (debtCaseId is! String ||
        decisionId is! String ||
        amount is! int ||
        amount <= 0 ||
        creditor is! Map<String, Object?> ||
        command.payload.length != 2 ||
        command.payload['debtCaseId'] != debtCaseId ||
        command.payload['decisionId'] != decisionId) {
      return null;
    }
    final kind = creditor['kind'];
    final playerId = creditor['playerId'];
    if (kind != 'bank' && kind != 'player') {
      return null;
    }
    if (kind == 'player' && playerId is! String) {
      return null;
    }
    if (kind == 'bank' && playerId != null) {
      return null;
    }
    return _DebtContext(
      debtCaseId,
      actorId,
      kind! as String,
      playerId as String?,
      amount,
    );
  }
}

final class _AutoLiquidation {
  const _AutoLiquidation(
    this.assets,
    this.actions,
    this.cashRecovered,
    this.hasRemainingLegalValue,
  );
  final List<PropertyState> assets;
  final List<_LiquidationAction> actions;
  final int cashRecovered;
  final bool hasRemainingLegalValue;
}

final class _LiquidationAction {
  const _LiquidationAction(this.type, this.propertyId, this.cashRecovered);
  final String type;
  final String propertyId;
  final int cashRecovered;
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'propertyId': propertyId,
    'cashRecovered': cashRecovered,
  };
}

final class _ImprovementValue {
  const _ImprovementValue(this.rentLoss, this.cashRecovered);
  final int rentLoss;
  final int cashRecovered;
}
