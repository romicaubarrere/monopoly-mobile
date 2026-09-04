import 'domain_contracts.dart';
import 'rules_catalog.dart';

enum BuyAuctionErrorCode {
  invalidCommand('invalidCommand'),
  staleVersion('staleVersion'),
  actorNotInGame('actorNotInGame'),
  notAllowed('notAllowed'),
  invalidState('invalidState'),
  decisionClosed('decisionClosed'),
  insufficientFunds('insufficientFunds'),
  invalidBid('invalidBid');

  const BuyAuctionErrorCode(this.wireValue);

  final String wireValue;
}

sealed class BuyAuctionEvaluation {
  const BuyAuctionEvaluation({
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

final class BuyAuctionRejection extends BuyAuctionEvaluation {
  const BuyAuctionRejection({
    required super.commandId,
    required super.stateVersionBefore,
    required this.errorCode,
  });

  final BuyAuctionErrorCode errorCode;

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

final class BuyAuctionPlan extends BuyAuctionEvaluation {
  BuyAuctionPlan({
    required super.commandId,
    required super.stateVersionBefore,
    required this.stateAfter,
    required List<GameDomainEvent> events,
  }) : events = List.unmodifiable(events);

  final PublicGameState stateAfter;
  final List<GameDomainEvent> events;

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
    'events': events.map((event) => event.toJson()).toList(growable: false),
    'state': stateAfter.toJson(),
  };
}

/// Pure Engine semantics for the controlled Buy/Decline + Auction VP0 slice.
///
/// Authority owns membership authentication, duplicate-result lookup,
/// concurrency and persistence. Consequently an accepted result is an atomic
/// plan: cash, ownership, decision and auction changes must be committed with
/// its operation result or not committed at all.
abstract final class BuyAuctionEngine {
  static BuyAuctionEvaluation evaluate({
    required GameCommand command,
    required PublicGameState state,
    required RulesCatalog catalog,
    required DateTime transitionTime,
  }) {
    final version = state.header.stateVersion;
    BuyAuctionRejection reject(BuyAuctionErrorCode code) => BuyAuctionRejection(
      commandId: command.commandId,
      stateVersionBefore: version,
      errorCode: code,
    );

    if (command.gameId != state.header.gameId ||
        !_supportedType(command.type)) {
      return reject(BuyAuctionErrorCode.invalidCommand);
    }
    if (command.expectedStateVersion != version) {
      return reject(BuyAuctionErrorCode.staleVersion);
    }
    if (!_catalogMatches(state, catalog)) {
      return reject(BuyAuctionErrorCode.invalidState);
    }
    final actor = _activePlayer(state, command.actorPlayerId);
    if (actor == null) {
      return reject(BuyAuctionErrorCode.actorNotInGame);
    }

    return switch (command.type) {
      GameCommandType.buyProperty => _buy(
        command: command,
        state: state,
        catalog: catalog,
        actor: actor,
        reject: reject,
      ),
      GameCommandType.declineProperty => _decline(
        command: command,
        state: state,
        catalog: catalog,
        actor: actor,
        transitionTime: transitionTime,
        reject: reject,
      ),
      GameCommandType.placeBid => _bid(
        command: command,
        state: state,
        actor: actor,
        transitionTime: transitionTime,
        reject: reject,
      ),
      GameCommandType.passAuction => _pass(
        command: command,
        state: state,
        actor: actor,
        transitionTime: transitionTime,
        reject: reject,
      ),
      _ => reject(BuyAuctionErrorCode.invalidCommand),
    };
  }

  static BuyAuctionEvaluation _buy({
    required GameCommand command,
    required PublicGameState state,
    required RulesCatalog catalog,
    required PlayerState actor,
    required BuyAuctionRejection Function(BuyAuctionErrorCode) reject,
  }) {
    final offer = _propertyOffer(state, command, actor.playerId);
    if (offer == null) {
      return reject(BuyAuctionErrorCode.decisionClosed);
    }
    if (command.payload.length != 2 ||
        command.payload['decisionId'] != offer.decisionId ||
        command.payload['propertyId'] != offer.propertyId) {
      return reject(BuyAuctionErrorCode.invalidCommand);
    }
    final economy = catalog.economyCatalog.properties[offer.propertyId];
    if (economy == null ||
        economy.purchasePrice != offer.purchasePrice ||
        _isOwned(state, offer.propertyId)) {
      return reject(BuyAuctionErrorCode.invalidState);
    }
    if (actor.cash < offer.purchasePrice) {
      return reject(BuyAuctionErrorCode.insufficientFunds);
    }

    final outcome = GameDomainEvent(
      type: 'propertyPurchased',
      data: <String, Object?>{
        'playerId': actor.playerId,
        'propertyId': offer.propertyId,
        'price': offer.purchasePrice,
      },
    );
    final stateAfter = _copyState(
      state,
      command: command,
      players: _awardProperty(
        state.players,
        actor.playerId,
        offer.propertyId,
        offer.purchasePrice,
      ),
      ownership: _ownershipAfterAward(
        state.ownership,
        offer.propertyId,
        actor.playerId,
      ),
      turnState: _turnAfterDecision(state.turnState),
      pendingDecision: const _NullableMap.clear(),
      outcome: outcome.toJson(),
    );
    return BuyAuctionPlan(
      commandId: command.commandId,
      stateVersionBefore: state.header.stateVersion,
      stateAfter: stateAfter,
      events: <GameDomainEvent>[outcome],
    );
  }

  static BuyAuctionEvaluation _decline({
    required GameCommand command,
    required PublicGameState state,
    required RulesCatalog catalog,
    required PlayerState actor,
    required DateTime transitionTime,
    required BuyAuctionRejection Function(BuyAuctionErrorCode) reject,
  }) {
    final offer = _propertyOffer(state, command, actor.playerId);
    if (offer == null) {
      return reject(BuyAuctionErrorCode.decisionClosed);
    }
    if (command.payload.length != 2 ||
        command.payload['decisionId'] != offer.decisionId ||
        command.payload['propertyId'] != offer.propertyId) {
      return reject(BuyAuctionErrorCode.invalidCommand);
    }
    if (_isOwned(state, offer.propertyId)) {
      return reject(BuyAuctionErrorCode.invalidState);
    }
    final auctionPolicy = state.presetConfig['auctionPolicy'];
    final minimumIncrement = auctionPolicy is Map<String, Object?>
        ? auctionPolicy['minimumIncrement']
        : null;
    final bidSeconds = state.presetConfig['auctionBidSeconds'];
    final hardCapSeconds = state.presetConfig['auctionHardCapSeconds'];
    if (minimumIncrement is! int ||
        minimumIncrement <= 0 ||
        bidSeconds is! int ||
        bidSeconds <= 0 ||
        hardCapSeconds is! int ||
        hardCapSeconds < bidSeconds ||
        catalog.economyCatalog.properties[offer.propertyId] == null) {
      return reject(BuyAuctionErrorCode.invalidState);
    }
    final eligible =
        state.players
            .where((player) => player.status == PlayerStatus.active)
            .toList(growable: false)
          ..sort((left, right) => left.seat.compareTo(right.seat));
    if (eligible.isEmpty) {
      return reject(BuyAuctionErrorCode.invalidState);
    }
    final ordered = _cyclicFrom(eligible, actor.playerId);
    final now = transitionTime.toUtc();
    final hardDeadline = now.add(Duration(seconds: hardCapSeconds));
    final auctionId = '${command.commandId}:auction';
    final firstBidderId = ordered.first.playerId;
    final activeAuction = <String, Object?>{
      'auctionId': auctionId,
      'propertyId': offer.propertyId,
      'minimumIncrement': minimumIncrement,
      'currentBid': 0,
      'currentBidderPlayerId': firstBidderId,
      'eligiblePlayerIds': <Object?>[
        for (final player in ordered) player.playerId,
      ],
      'passedPlayerIds': const <Object?>[],
      'startedAt': now.toIso8601String(),
      'hardDeadlineAt': hardDeadline.toIso8601String(),
    };
    final stateAfter = _copyState(
      state,
      command: command,
      turnState: <String, Object?>{
        ...state.turnState,
        'phase': 'auction',
        'landingPropertyId': offer.propertyId,
      },
      pendingDecision: _NullableMap.value(
        _auctionDecision(
          auctionId: auctionId,
          propertyId: offer.propertyId,
          bidderPlayerId: firstBidderId,
          stateVersionCreated: state.header.stateVersion + 1,
          createdAt: now,
          deadlineAt: _turnDeadline(
            now: now,
            bidSeconds: bidSeconds,
            hardDeadline: hardDeadline,
          ),
        ),
      ),
      activeAuction: _NullableMap.value(activeAuction),
    );
    return BuyAuctionPlan(
      commandId: command.commandId,
      stateVersionBefore: state.header.stateVersion,
      stateAfter: stateAfter,
      events: <GameDomainEvent>[
        GameDomainEvent(
          type: 'propertyDeclined',
          data: <String, Object?>{
            'playerId': actor.playerId,
            'propertyId': offer.propertyId,
          },
        ),
        GameDomainEvent(
          type: 'auctionStarted',
          data: <String, Object?>{
            'auctionId': auctionId,
            'propertyId': offer.propertyId,
            'eligiblePlayerIds': <Object?>[
              for (final player in ordered) player.playerId,
            ],
          },
        ),
      ],
    );
  }

  static BuyAuctionEvaluation _bid({
    required GameCommand command,
    required PublicGameState state,
    required PlayerState actor,
    required DateTime transitionTime,
    required BuyAuctionRejection Function(BuyAuctionErrorCode) reject,
  }) {
    final auction = _auctionState(state, command, actor.playerId);
    if (auction == null) {
      return reject(BuyAuctionErrorCode.decisionClosed);
    }
    final amount = command.payload['amount'];
    if (command.payload.length != 2 ||
        command.payload['auctionId'] != auction.auctionId ||
        amount is! int) {
      return reject(BuyAuctionErrorCode.invalidCommand);
    }
    if (amount < auction.currentBid + auction.minimumIncrement ||
        amount > actor.cash) {
      return reject(BuyAuctionErrorCode.invalidBid);
    }

    final events = <GameDomainEvent>[
      GameDomainEvent(
        type: 'auctionBidPlaced',
        data: <String, Object?>{
          'auctionId': auction.auctionId,
          'playerId': actor.playerId,
          'amount': amount,
        },
      ),
    ];
    final next = _nextChallenger(auction, actor.playerId);
    if (next == null) {
      return _awardAuction(
        command: command,
        state: state,
        auction: auction,
        winnerPlayerId: actor.playerId,
        winningBid: amount,
        events: events,
      );
    }
    return _continueAuction(
      command: command,
      state: state,
      auction: auction,
      currentBid: amount,
      leaderPlayerId: actor.playerId,
      nextBidderPlayerId: next,
      transitionTime: transitionTime,
      events: events,
    );
  }

  static BuyAuctionEvaluation _pass({
    required GameCommand command,
    required PublicGameState state,
    required PlayerState actor,
    required DateTime transitionTime,
    required BuyAuctionRejection Function(BuyAuctionErrorCode) reject,
  }) {
    final auction = _auctionState(state, command, actor.playerId);
    if (auction == null) {
      return reject(BuyAuctionErrorCode.decisionClosed);
    }
    if (command.payload.length != 1 ||
        command.payload['auctionId'] != auction.auctionId) {
      return reject(BuyAuctionErrorCode.invalidCommand);
    }
    final passed = <String>{...auction.passedPlayerIds, actor.playerId};
    final updated = auction.withPassed(passed);
    final events = <GameDomainEvent>[
      GameDomainEvent(
        type: 'auctionPassed',
        data: <String, Object?>{
          'auctionId': auction.auctionId,
          'playerId': actor.playerId,
        },
      ),
    ];
    final next = _nextChallenger(updated, actor.playerId);
    if (next != null) {
      return _continueAuction(
        command: command,
        state: state,
        auction: updated,
        currentBid: auction.currentBid,
        leaderPlayerId: auction.leaderPlayerId,
        nextBidderPlayerId: next,
        transitionTime: transitionTime,
        events: events,
      );
    }
    if (auction.leaderPlayerId != null) {
      return _awardAuction(
        command: command,
        state: state,
        auction: updated,
        winnerPlayerId: auction.leaderPlayerId!,
        winningBid: auction.currentBid,
        events: events,
      );
    }
    final outcome = GameDomainEvent(
      type: 'auctionEndedWithoutWinner',
      data: <String, Object?>{
        'auctionId': auction.auctionId,
        'propertyId': auction.propertyId,
      },
    );
    final stateAfter = _copyState(
      state,
      command: command,
      turnState: _turnAfterDecision(state.turnState),
      pendingDecision: const _NullableMap.clear(),
      activeAuction: const _NullableMap.clear(),
      outcome: outcome.toJson(),
    );
    events.add(outcome);
    return BuyAuctionPlan(
      commandId: command.commandId,
      stateVersionBefore: state.header.stateVersion,
      stateAfter: stateAfter,
      events: events,
    );
  }

  static BuyAuctionPlan _continueAuction({
    required GameCommand command,
    required PublicGameState state,
    required _AuctionState auction,
    required int currentBid,
    required String? leaderPlayerId,
    required String nextBidderPlayerId,
    required DateTime transitionTime,
    required List<GameDomainEvent> events,
  }) {
    final now = transitionTime.toUtc();
    final activeAuction = auction.toJson(
      currentBid: currentBid,
      leaderPlayerId: leaderPlayerId,
      currentBidderPlayerId: nextBidderPlayerId,
    );
    final stateAfter = _copyState(
      state,
      command: command,
      pendingDecision: _NullableMap.value(
        _auctionDecision(
          auctionId: auction.auctionId,
          propertyId: auction.propertyId,
          bidderPlayerId: nextBidderPlayerId,
          stateVersionCreated: state.header.stateVersion + 1,
          createdAt: now,
          deadlineAt: _turnDeadline(
            now: now,
            bidSeconds: auction.bidSeconds,
            hardDeadline: auction.hardDeadlineAt,
          ),
        ),
      ),
      activeAuction: _NullableMap.value(activeAuction),
    );
    return BuyAuctionPlan(
      commandId: command.commandId,
      stateVersionBefore: state.header.stateVersion,
      stateAfter: stateAfter,
      events: events,
    );
  }

  static BuyAuctionPlan _awardAuction({
    required GameCommand command,
    required PublicGameState state,
    required _AuctionState auction,
    required String winnerPlayerId,
    required int winningBid,
    required List<GameDomainEvent> events,
  }) {
    final winner = _activePlayer(state, winnerPlayerId);
    if (winner == null || winner.cash < winningBid || winningBid <= 0) {
      throw const DomainContractViolation(
        'A validated auction winner must be able to pay the winning bid',
      );
    }
    final outcome = GameDomainEvent(
      type: 'auctionWon',
      data: <String, Object?>{
        'auctionId': auction.auctionId,
        'propertyId': auction.propertyId,
        'winnerPlayerId': winnerPlayerId,
        'winningBid': winningBid,
      },
    );
    final stateAfter = _copyState(
      state,
      command: command,
      players: _awardProperty(
        state.players,
        winnerPlayerId,
        auction.propertyId,
        winningBid,
      ),
      ownership: _ownershipAfterAward(
        state.ownership,
        auction.propertyId,
        winnerPlayerId,
      ),
      turnState: _turnAfterDecision(state.turnState),
      pendingDecision: const _NullableMap.clear(),
      activeAuction: const _NullableMap.clear(),
      outcome: outcome.toJson(),
    );
    events.add(outcome);
    return BuyAuctionPlan(
      commandId: command.commandId,
      stateVersionBefore: state.header.stateVersion,
      stateAfter: stateAfter,
      events: events,
    );
  }
}

bool _supportedType(GameCommandType type) =>
    type == GameCommandType.buyProperty ||
    type == GameCommandType.declineProperty ||
    type == GameCommandType.placeBid ||
    type == GameCommandType.passAuction;

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

_PropertyOffer? _propertyOffer(
  PublicGameState state,
  GameCommand command,
  String actorPlayerId,
) {
  if (state.turnState['phase'] != 'awaitingPropertyDecision' ||
      state.activeAuction != null ||
      state.activeTrade != null ||
      state.debtCase != null) {
    return null;
  }
  final decision = state.pendingDecision;
  if (decision == null ||
      decision['kind'] != 'propertyOffer' ||
      decision['stateVersionCreated'] != state.header.stateVersion ||
      decision['allowedPlayerIds'] is! List<Object?> ||
      !(decision['allowedPlayerIds'] as List<Object?>).contains(
        actorPlayerId,
      ) ||
      decision['payload'] is! Map<String, Object?>) {
    return null;
  }
  final payload = decision['payload'] as Map<String, Object?>;
  final decisionId = decision['decisionId'];
  final propertyId = payload['propertyId'];
  final purchasePrice = payload['purchasePrice'];
  if (decisionId is! String ||
      propertyId is! String ||
      purchasePrice is! int ||
      purchasePrice < 0 ||
      state.turnState['landingPropertyId'] != propertyId ||
      state.turnState['currentPlayerId'] != actorPlayerId) {
    return null;
  }
  return _PropertyOffer(decisionId, propertyId, purchasePrice);
}

_AuctionState? _auctionState(
  PublicGameState state,
  GameCommand command,
  String actorPlayerId,
) {
  final raw = state.activeAuction;
  final decision = state.pendingDecision;
  if (state.turnState['phase'] != 'auction' ||
      raw == null ||
      decision == null ||
      state.activeTrade != null ||
      state.debtCase != null ||
      decision['kind'] != 'auctionTurn' ||
      decision['stateVersionCreated'] != state.header.stateVersion ||
      decision['allowedPlayerIds'] is! List<Object?> ||
      !(decision['allowedPlayerIds'] as List<Object?>).contains(
        actorPlayerId,
      )) {
    return null;
  }
  try {
    final auction = _AuctionState.from(state);
    final activePlayerIds = state.players
        .where((player) => player.status == PlayerStatus.active)
        .map((player) => player.playerId)
        .toSet();
    final leader = auction.leaderPlayerId == null
        ? null
        : _activePlayer(state, auction.leaderPlayerId!);
    if (decision['decisionId'] !=
            '${auction.auctionId}:turn:${state.header.stateVersion}' ||
        decision['payload'] is! Map<String, Object?> ||
        (decision['payload'] as Map<String, Object?>)['auctionId'] !=
            auction.auctionId ||
        auction.currentBidderPlayerId != actorPlayerId ||
        auction.passedPlayerIds.contains(actorPlayerId) ||
        (auction.leaderPlayerId != null &&
            auction.passedPlayerIds.contains(auction.leaderPlayerId)) ||
        !auction.eligiblePlayerIds.contains(actorPlayerId) ||
        !activePlayerIds.containsAll(auction.eligiblePlayerIds) ||
        (auction.leaderPlayerId != null && leader == null) ||
        (leader != null && leader.cash < auction.currentBid) ||
        _isOwned(state, auction.propertyId) ||
        command.actorPlayerId != actorPlayerId) {
      return null;
    }
    return auction;
  } on DomainContractViolation {
    return null;
  }
}

List<PlayerState> _awardProperty(
  List<PlayerState> players,
  String playerId,
  String propertyId,
  int amount,
) => <PlayerState>[
  for (final player in players)
    if (player.playerId == playerId)
      PlayerState(
        playerId: player.playerId,
        seat: player.seat,
        kind: player.kind,
        status: player.status,
        cash: player.cash - amount,
        position: player.position,
        ownedPropertyIds: <String>[...player.ownedPropertyIds, propertyId]
          ..sort(),
        keepCardIds: player.keepCardIds,
        inCucha: player.inCucha,
        cuchaAttempts: player.cuchaAttempts,
        consecutiveDoubles: player.consecutiveDoubles,
        connectivityStatus: player.connectivityStatus,
      )
    else
      player,
];

Map<String, Object?> _ownershipAfterAward(
  Map<String, Object?> ownership,
  String propertyId,
  String ownerPlayerId,
) {
  final previous = ownership['byPropertyId'];
  final byPropertyId = previous is Map<String, Object?>
      ? previous
      : const <String, Object?>{};
  return <String, Object?>{
    ...ownership,
    'byPropertyId': <String, Object?>{
      ...byPropertyId,
      propertyId: ownerPlayerId,
    },
  };
}

Map<String, Object?> _turnAfterDecision(Map<String, Object?> turnState) =>
    <String, Object?>{...turnState, 'phase': 'turnResolved'}
      ..remove('landingPropertyId');

PublicGameState _copyState(
  PublicGameState state, {
  required GameCommand command,
  List<PlayerState>? players,
  Map<String, Object?>? ownership,
  Map<String, Object?>? turnState,
  Map<String, Object?>? outcome,
  _NullableMap pendingDecision = const _NullableMap.keep(),
  _NullableMap activeAuction = const _NullableMap.keep(),
}) => PublicGameState(
  header: GameStateHeader(
    schemaVersion: state.header.schemaVersion,
    stateVersion: state.header.stateVersion + 1,
    rulesVersion: state.header.rulesVersion,
    rngVersion: state.header.rngVersion,
    rngCommitment: state.header.rngCommitment,
    gameId: state.header.gameId,
    roomId: state.header.roomId,
    status: state.header.status,
  ),
  presetConfig: state.presetConfig,
  roundState: state.roundState,
  turnState: turnState ?? state.turnState,
  players: players ?? state.players,
  seatControllers: state.seatControllers,
  board: state.board,
  ownership: ownership ?? state.ownership,
  bank: state.bank,
  freeParkingPot: state.freeParkingPot,
  deckPublicState: state.deckPublicState,
  pendingDecision: pendingDecision.resolve(state.pendingDecision),
  activeAuction: activeAuction.resolve(state.activeAuction),
  activeTrade: state.activeTrade,
  debtCase: state.debtCase,
  result: state.result,
  lastMutation: <String, Object?>{
    'type': 'buyAuction',
    'commandId': command.commandId,
    'actorPlayerId': command.actorPlayerId,
    if (outcome != null) 'outcome': outcome,
  },
);

Map<String, Object?> _auctionDecision({
  required String auctionId,
  required String propertyId,
  required String bidderPlayerId,
  required int stateVersionCreated,
  required DateTime createdAt,
  required DateTime deadlineAt,
}) => <String, Object?>{
  'decisionId': '$auctionId:turn:$stateVersionCreated',
  'kind': 'auctionTurn',
  'allowedPlayerIds': <Object?>[bidderPlayerId],
  'stateVersionCreated': stateVersionCreated,
  'createdAt': createdAt.toIso8601String(),
  'deadlineAt': deadlineAt.toIso8601String(),
  'timeoutPolicy': 'pass',
  'payload': <String, Object?>{
    'auctionId': auctionId,
    'propertyId': propertyId,
  },
};

DateTime _turnDeadline({
  required DateTime now,
  required int bidSeconds,
  required DateTime hardDeadline,
}) {
  final slotDeadline = now.add(Duration(seconds: bidSeconds));
  return slotDeadline.isAfter(hardDeadline) ? hardDeadline : slotDeadline;
}

List<PlayerState> _cyclicFrom(List<PlayerState> players, String playerId) {
  final start = players.indexWhere((player) => player.playerId == playerId);
  if (start < 0) {
    throw const DomainContractViolation('Auction starter must be eligible');
  }
  return <PlayerState>[...players.skip(start), ...players.take(start)];
}

String? _nextChallenger(_AuctionState auction, String afterPlayerId) {
  final start = auction.eligiblePlayerIds.indexOf(afterPlayerId);
  for (
    var offset = 1;
    offset <= auction.eligiblePlayerIds.length;
    offset += 1
  ) {
    final candidate = auction
        .eligiblePlayerIds[(start + offset) % auction.eligiblePlayerIds.length];
    if (!auction.passedPlayerIds.contains(candidate) &&
        candidate != auction.leaderPlayerId) {
      return candidate;
    }
  }
  return null;
}

bool _isOwned(PublicGameState state, String propertyId) =>
    state.players.any((player) => player.ownedPropertyIds.contains(propertyId));

final class _PropertyOffer {
  const _PropertyOffer(this.decisionId, this.propertyId, this.purchasePrice);

  final String decisionId;
  final String propertyId;
  final int purchasePrice;
}

final class _AuctionState {
  const _AuctionState({
    required this.auctionId,
    required this.propertyId,
    required this.minimumIncrement,
    required this.currentBid,
    required this.leaderPlayerId,
    required this.currentBidderPlayerId,
    required this.eligiblePlayerIds,
    required this.passedPlayerIds,
    required this.startedAt,
    required this.hardDeadlineAt,
    required this.bidSeconds,
  });

  factory _AuctionState.from(PublicGameState state) {
    final raw = state.activeAuction!;
    final auctionId = raw['auctionId'];
    final propertyId = raw['propertyId'];
    final minimumIncrement = raw['minimumIncrement'];
    final currentBid = raw['currentBid'];
    final leaderPlayerId = raw['leaderPlayerId'];
    final currentBidderPlayerId = raw['currentBidderPlayerId'];
    final eligibleRaw = raw['eligiblePlayerIds'];
    final passedRaw = raw['passedPlayerIds'];
    final startedAtRaw = raw['startedAt'];
    final hardDeadlineRaw = raw['hardDeadlineAt'];
    final bidSeconds = state.presetConfig['auctionBidSeconds'];
    if (auctionId is! String ||
        propertyId is! String ||
        minimumIncrement is! int ||
        minimumIncrement <= 0 ||
        currentBid is! int ||
        currentBid < 0 ||
        leaderPlayerId is! String? ||
        currentBidderPlayerId is! String ||
        eligibleRaw is! List<Object?> ||
        passedRaw is! List<Object?> ||
        startedAtRaw is! String ||
        hardDeadlineRaw is! String ||
        bidSeconds is! int ||
        bidSeconds <= 0) {
      throw const DomainContractViolation('Malformed activeAuction');
    }
    final eligible = eligibleRaw.whereType<String>().toList(growable: false);
    final passed = passedRaw.whereType<String>().toSet();
    final startedAt = DateTime.tryParse(startedAtRaw)?.toUtc();
    final hardDeadline = DateTime.tryParse(hardDeadlineRaw)?.toUtc();
    if (eligible.length != eligibleRaw.length ||
        eligible.toSet().length != eligible.length ||
        passed.length != passedRaw.length ||
        !eligible.toSet().containsAll(passed) ||
        !eligible.contains(currentBidderPlayerId) ||
        (leaderPlayerId != null && !eligible.contains(leaderPlayerId)) ||
        startedAt == null ||
        hardDeadline == null ||
        hardDeadline.isBefore(startedAt) ||
        (leaderPlayerId == null) != (currentBid == 0)) {
      throw const DomainContractViolation('Inconsistent activeAuction');
    }
    return _AuctionState(
      auctionId: auctionId,
      propertyId: propertyId,
      minimumIncrement: minimumIncrement,
      currentBid: currentBid,
      leaderPlayerId: leaderPlayerId,
      currentBidderPlayerId: currentBidderPlayerId,
      eligiblePlayerIds: eligible,
      passedPlayerIds: passed,
      startedAt: startedAt,
      hardDeadlineAt: hardDeadline,
      bidSeconds: bidSeconds,
    );
  }

  final String auctionId;
  final String propertyId;
  final int minimumIncrement;
  final int currentBid;
  final String? leaderPlayerId;
  final String currentBidderPlayerId;
  final List<String> eligiblePlayerIds;
  final Set<String> passedPlayerIds;
  final DateTime startedAt;
  final DateTime hardDeadlineAt;
  final int bidSeconds;

  _AuctionState withPassed(Set<String> passed) => _AuctionState(
    auctionId: auctionId,
    propertyId: propertyId,
    minimumIncrement: minimumIncrement,
    currentBid: currentBid,
    leaderPlayerId: leaderPlayerId,
    currentBidderPlayerId: currentBidderPlayerId,
    eligiblePlayerIds: eligiblePlayerIds,
    passedPlayerIds: passed,
    startedAt: startedAt,
    hardDeadlineAt: hardDeadlineAt,
    bidSeconds: bidSeconds,
  );

  Map<String, Object?> toJson({
    required int currentBid,
    required String? leaderPlayerId,
    required String currentBidderPlayerId,
  }) => <String, Object?>{
    'auctionId': auctionId,
    'propertyId': propertyId,
    'minimumIncrement': minimumIncrement,
    'currentBid': currentBid,
    if (leaderPlayerId != null) 'leaderPlayerId': leaderPlayerId,
    'currentBidderPlayerId': currentBidderPlayerId,
    'eligiblePlayerIds': <Object?>[...eligiblePlayerIds],
    'passedPlayerIds': <Object?>[...passedPlayerIds]..sort(),
    'startedAt': startedAt.toIso8601String(),
    'hardDeadlineAt': hardDeadlineAt.toIso8601String(),
  };
}

final class _NullableMap {
  const _NullableMap.keep() : value = null, clear = false, replace = false;
  const _NullableMap.clear() : value = null, clear = true, replace = false;
  const _NullableMap.value(this.value) : clear = false, replace = true;

  final Map<String, Object?>? value;
  final bool clear;
  final bool replace;

  Map<String, Object?>? resolve(Map<String, Object?>? existing) {
    if (clear) return null;
    if (replace) return value;
    return existing;
  }
}
