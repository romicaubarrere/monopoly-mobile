import 'domain_contracts.dart';
import 'rules_catalog.dart';

enum TaxFreeParkingErrorCode {
  invalidOperation('invalidOperation'),
  staleVersion('staleVersion'),
  actorNotInGame('actorNotInGame'),
  notCurrentPlayer('notCurrentPlayer'),
  decisionRequired('decisionRequired'),
  invalidState('invalidState'),
  unsupportedLanding('unsupportedLanding');

  const TaxFreeParkingErrorCode(this.wireValue);

  final String wireValue;
}

sealed class TaxFreeParkingEvaluation {
  const TaxFreeParkingEvaluation({
    required this.operationId,
    required this.stateVersionBefore,
  });

  final String operationId;
  final int stateVersionBefore;

  bool get accepted;
  int get stateVersionAfter;
  Map<String, Object?> toPublicJson();

  String toCanonicalPublicJson() => CanonicalDomainJson.encode(toPublicJson());
}

final class TaxFreeParkingRejection extends TaxFreeParkingEvaluation {
  const TaxFreeParkingRejection({
    required super.operationId,
    required super.stateVersionBefore,
    required this.errorCode,
  });

  final TaxFreeParkingErrorCode errorCode;

  @override
  bool get accepted => false;

  @override
  int get stateVersionAfter => stateVersionBefore;

  @override
  Map<String, Object?> toPublicJson() => <String, Object?>{
    'operationId': operationId,
    'status': 'rejected',
    'stateVersionBefore': stateVersionBefore,
    'stateVersionAfter': stateVersionAfter,
    'errorCode': errorCode.wireValue,
    'events': const <Object?>[],
  };
}

enum LandingEconomyKind {
  taxPaid('taxPaid'),
  taxDebtOpened('taxDebtOpened'),
  freeParkingCollected('freeParkingCollected');

  const LandingEconomyKind(this.wireValue);

  final String wireValue;
}

final class TaxFreeParkingPlan extends TaxFreeParkingEvaluation {
  TaxFreeParkingPlan({
    required super.operationId,
    required super.stateVersionBefore,
    required this.kind,
    required this.amount,
    required this.stateAfter,
    required List<GameDomainEvent> events,
  }) : events = List.unmodifiable(events);

  final LandingEconomyKind kind;
  final int amount;
  final PublicGameState stateAfter;
  final List<GameDomainEvent> events;

  @override
  bool get accepted => true;

  @override
  int get stateVersionAfter => stateVersionBefore + 1;

  @override
  Map<String, Object?> toPublicJson() => <String, Object?>{
    'operationId': operationId,
    'status': 'accepted',
    'stateVersionBefore': stateVersionBefore,
    'stateVersionAfter': stateVersionAfter,
    'kind': kind.wireValue,
    'amount': amount,
    'events': events.map((event) => event.toJson()).toList(growable: false),
    'state': stateAfter.toJson(),
  };
}

/// Pure resolution of the configured tax and Free Parking landing effects.
///
/// Authority owns operation identity lookup, atomic persistence and durable
/// retry/concurrency handling. Re-evaluating the same immutable inputs yields
/// the same plan and never reads or advances an RNG stream.
abstract final class TaxFreeParkingEngine {
  static TaxFreeParkingEvaluation evaluate({
    required String operationId,
    required int expectedStateVersion,
    required String playerId,
    required PublicGameState state,
    required RulesCatalog catalog,
    required DateTime transitionTime,
  }) {
    final version = state.header.stateVersion;
    TaxFreeParkingRejection reject(TaxFreeParkingErrorCode code) =>
        TaxFreeParkingRejection(
          operationId: operationId,
          stateVersionBefore: version,
          errorCode: code,
        );

    if (operationId.isEmpty || playerId.isEmpty || expectedStateVersion < 0) {
      return reject(TaxFreeParkingErrorCode.invalidOperation);
    }
    if (expectedStateVersion != version) {
      return reject(TaxFreeParkingErrorCode.staleVersion);
    }
    if (!_catalogMatches(state, catalog) ||
        catalog.ruleFlags['freeParkingPot'] != true) {
      return reject(TaxFreeParkingErrorCode.invalidState);
    }
    final players = state.players.where(
      (candidate) =>
          candidate.playerId == playerId &&
          candidate.status == PlayerStatus.active,
    );
    if (players.length != 1) {
      return reject(TaxFreeParkingErrorCode.actorNotInGame);
    }
    if (state.turnState['currentPlayerId'] != playerId) {
      return reject(TaxFreeParkingErrorCode.notCurrentPlayer);
    }
    if (state.pendingDecision != null ||
        state.activeAuction != null ||
        state.activeTrade != null ||
        state.debtCase != null) {
      return reject(TaxFreeParkingErrorCode.decisionRequired);
    }
    if (state.turnState['phase'] != 'resolvingLanding') {
      return reject(TaxFreeParkingErrorCode.invalidState);
    }

    final player = players.single;
    if (player.position < 0 || player.position >= 40) {
      return reject(TaxFreeParkingErrorCode.invalidState);
    }
    final space = catalog.boardDefinition.spaces.singleWhere(
      (candidate) => candidate.index == player.position,
    );
    return switch (space.type) {
      BoardSpaceType.tax => _resolveTax(
        operationId: operationId,
        state: state,
        catalog: catalog,
        player: player,
        ruleRef: space.ruleRef,
        transitionTime: transitionTime,
        reject: reject,
      ),
      BoardSpaceType.freeParking => _collectPot(
        operationId: operationId,
        state: state,
        player: player,
      ),
      _ => reject(TaxFreeParkingErrorCode.unsupportedLanding),
    };
  }
}

TaxFreeParkingEvaluation _resolveTax({
  required String operationId,
  required PublicGameState state,
  required RulesCatalog catalog,
  required PlayerState player,
  required String? ruleRef,
  required DateTime transitionTime,
  required TaxFreeParkingRejection Function(TaxFreeParkingErrorCode) reject,
}) {
  final amount = ruleRef == null ? null : catalog.economyCatalog.taxes[ruleRef];
  if (amount == null) {
    return reject(TaxFreeParkingErrorCode.invalidState);
  }
  if (player.cash < amount) {
    return _openTaxDebt(
      operationId: operationId,
      state: state,
      player: player,
      ruleRef: ruleRef!,
      amount: amount,
      transitionTime: transitionTime,
      reject: reject,
    );
  }

  final potBefore = state.freeParkingPot;
  final event = GameDomainEvent(
    type: 'taxPaid',
    data: <String, Object?>{
      'playerId': player.playerId,
      'ruleRef': ruleRef!,
      'amount': amount,
      'potBefore': potBefore,
      'potAfter': potBefore + amount,
    },
  );
  return TaxFreeParkingPlan(
    operationId: operationId,
    stateVersionBefore: state.header.stateVersion,
    kind: LandingEconomyKind.taxPaid,
    amount: amount,
    stateAfter: _copyState(
      state,
      operationId: operationId,
      players: _withCash(state.players, player.playerId, player.cash - amount),
      freeParkingPot: potBefore + amount,
      turnState: <String, Object?>{...state.turnState, 'phase': 'turnResolved'},
      mutationType: 'taxPaid',
    ),
    events: <GameDomainEvent>[event],
  );
}

TaxFreeParkingEvaluation _openTaxDebt({
  required String operationId,
  required PublicGameState state,
  required PlayerState player,
  required String ruleRef,
  required int amount,
  required DateTime transitionTime,
  required TaxFreeParkingRejection Function(TaxFreeParkingErrorCode) reject,
}) {
  final debtSeconds = state.presetConfig['debtDecisionSeconds'];
  if (debtSeconds is! int || debtSeconds <= 0) {
    return reject(TaxFreeParkingErrorCode.invalidState);
  }
  final createdAt = transitionTime.toUtc();
  final versionAfter = state.header.stateVersion + 1;
  final debtCaseId = '$operationId:debt';
  final decisionId = '$debtCaseId:decision';
  final event = GameDomainEvent(
    type: 'taxDebtOpened',
    data: <String, Object?>{
      'debtCaseId': debtCaseId,
      'playerId': player.playerId,
      'ruleRef': ruleRef,
      'amount': amount,
      'availableCash': player.cash,
    },
  );
  return TaxFreeParkingPlan(
    operationId: operationId,
    stateVersionBefore: state.header.stateVersion,
    kind: LandingEconomyKind.taxDebtOpened,
    amount: amount,
    stateAfter: _copyState(
      state,
      operationId: operationId,
      players: state.players,
      freeParkingPot: state.freeParkingPot,
      turnState: <String, Object?>{
        ...state.turnState,
        'phase': 'debtResolution',
      },
      mutationType: 'taxDebtOpened',
      pendingDecision: <String, Object?>{
        'decisionId': decisionId,
        'kind': 'debtResolution',
        'allowedPlayerIds': <Object?>[player.playerId],
        'stateVersionCreated': versionAfter,
        'createdAt': createdAt.toIso8601String(),
        'deadlineAt': createdAt
            .add(Duration(seconds: debtSeconds))
            .toIso8601String(),
        'timeoutPolicy': 'declareBankruptcy',
      },
      debtCase: <String, Object?>{
        'debtCaseId': debtCaseId,
        'debtorPlayerId': player.playerId,
        'creditor': const <String, Object?>{'kind': 'bank'},
        'amountDue': amount,
        'status': 'open',
        'purpose': 'taxToFreeParkingPot',
        'ruleRef': ruleRef,
      },
    ),
    events: <GameDomainEvent>[event],
  );
}

TaxFreeParkingPlan _collectPot({
  required String operationId,
  required PublicGameState state,
  required PlayerState player,
}) {
  final amount = state.freeParkingPot;
  final event = GameDomainEvent(
    type: 'freeParkingCollected',
    data: <String, Object?>{
      'playerId': player.playerId,
      'amount': amount,
      'potBefore': amount,
      'potAfter': 0,
    },
  );
  return TaxFreeParkingPlan(
    operationId: operationId,
    stateVersionBefore: state.header.stateVersion,
    kind: LandingEconomyKind.freeParkingCollected,
    amount: amount,
    stateAfter: _copyState(
      state,
      operationId: operationId,
      players: _withCash(state.players, player.playerId, player.cash + amount),
      freeParkingPot: 0,
      turnState: <String, Object?>{...state.turnState, 'phase': 'turnResolved'},
      mutationType: 'freeParkingCollected',
    ),
    events: <GameDomainEvent>[event],
  );
}

bool _catalogMatches(PublicGameState state, RulesCatalog catalog) =>
    state.header.status == GameStatus.active &&
    state.header.rulesVersion == catalog.rulesVersion &&
    state.board['boardId'] == catalog.boardDefinition.boardId &&
    state.board['boardDefinitionVersion'] == catalog.boardDefinitionVersion;

List<PlayerState> _withCash(
  List<PlayerState> players,
  String playerId,
  int cash,
) => <PlayerState>[
  for (final player in players)
    if (player.playerId == playerId)
      PlayerState(
        playerId: player.playerId,
        seat: player.seat,
        kind: player.kind,
        status: player.status,
        cash: cash,
        position: player.position,
        ownedPropertyIds: player.ownedPropertyIds,
        keepCardIds: player.keepCardIds,
        inCucha: player.inCucha,
        cuchaAttempts: player.cuchaAttempts,
        consecutiveDoubles: player.consecutiveDoubles,
        connectivityStatus: player.connectivityStatus,
      )
    else
      player,
];

PublicGameState _copyState(
  PublicGameState state, {
  required String operationId,
  required List<PlayerState> players,
  required int freeParkingPot,
  required Map<String, Object?> turnState,
  required String mutationType,
  Map<String, Object?>? pendingDecision,
  Map<String, Object?>? debtCase,
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
  turnState: turnState,
  players: players,
  seatControllers: state.seatControllers,
  board: state.board,
  ownership: state.ownership,
  bank: state.bank,
  freeParkingPot: freeParkingPot,
  deckPublicState: state.deckPublicState,
  pendingDecision: pendingDecision,
  activeAuction: state.activeAuction,
  activeTrade: state.activeTrade,
  debtCase: debtCase,
  result: state.result,
  lastMutation: <String, Object?>{
    'type': mutationType,
    'operationId': operationId,
  },
);
