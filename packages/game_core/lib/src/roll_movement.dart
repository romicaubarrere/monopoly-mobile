import 'canonical_rng.dart';
import 'domain_contracts.dart';
import 'rules_catalog.dart';

enum RollMovementErrorCode {
  invalidCommand('invalidCommand'),
  staleVersion('staleVersion'),
  actorNotInGame('actorNotInGame'),
  notYourTurn('notYourTurn'),
  decisionRequired('decisionRequired'),
  invalidState('invalidState'),
  rngCommitmentMismatch('rngCommitmentMismatch'),
  unsupportedVp0Landing('unsupportedVp0Landing');

  const RollMovementErrorCode(this.wireValue);

  final String wireValue;
}

sealed class RollMovementEvaluation {
  const RollMovementEvaluation({
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

final class RollMovementRejection extends RollMovementEvaluation {
  const RollMovementRejection({
    required super.commandId,
    required super.stateVersionBefore,
    required this.errorCode,
  });

  final RollMovementErrorCode errorCode;

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

final class RollMovementPlan extends RollMovementEvaluation {
  RollMovementPlan({
    required super.commandId,
    required super.stateVersionBefore,
    required this.actorPlayerId,
    required this.die1,
    required this.die2,
    required this.fromPosition,
    required this.toPosition,
    required this.propertyId,
    required this.candidatesConsumed,
    required this.successorRng,
    required this.stateAfter,
    required List<GameDomainEvent> events,
  }) : events = List.unmodifiable(events);

  final String actorPlayerId;
  final int die1;
  final int die2;
  final int fromPosition;
  final int toPosition;
  final String propertyId;
  final int candidatesConsumed;

  /// Authority-private successor. It must commit atomically with [stateAfter].
  final CanonicalRng successorRng;
  final PublicGameState stateAfter;
  final List<GameDomainEvent> events;

  int get total => die1 + die2;

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

/// Pure Engine transition for the controlled VP0 Roll/movement slice.
///
/// Authentication, duplicate-result lookup and persistence stay outside this
/// boundary. Re-evaluating with the same immutable state, RNG snapshot and
/// [transitionTime] produces the same public plan and private RNG successor.
abstract final class RollMovementEngine {
  static RollMovementEvaluation evaluate({
    required GameCommand command,
    required PublicGameState state,
    required RulesCatalog catalog,
    required CanonicalRng rng,
    required DateTime transitionTime,
  }) {
    final version = state.header.stateVersion;
    RollMovementRejection reject(RollMovementErrorCode code) =>
        RollMovementRejection(
          commandId: command.commandId,
          stateVersionBefore: version,
          errorCode: code,
        );

    if (command.type != GameCommandType.rollDice ||
        command.payload.isNotEmpty ||
        command.gameId != state.header.gameId) {
      return reject(RollMovementErrorCode.invalidCommand);
    }
    if (command.expectedStateVersion != version) {
      return reject(RollMovementErrorCode.staleVersion);
    }
    if (state.header.status != GameStatus.active ||
        state.header.rulesVersion != catalog.rulesVersion ||
        state.board['boardId'] != catalog.boardDefinition.boardId ||
        state.board['boardDefinitionVersion'] !=
            catalog.boardDefinitionVersion) {
      return reject(RollMovementErrorCode.invalidState);
    }

    final actorMatches = state.players.where(
      (player) => player.playerId == command.actorPlayerId,
    );
    if (actorMatches.isEmpty ||
        actorMatches.single.status != PlayerStatus.active) {
      return reject(RollMovementErrorCode.actorNotInGame);
    }
    if (state.turnState['currentPlayerId'] != command.actorPlayerId) {
      return reject(RollMovementErrorCode.notYourTurn);
    }
    if (state.turnState['phase'] != 'awaitingRoll') {
      return reject(RollMovementErrorCode.invalidCommand);
    }
    if (state.pendingDecision != null ||
        state.activeAuction != null ||
        state.activeTrade != null ||
        state.debtCase != null) {
      return reject(RollMovementErrorCode.decisionRequired);
    }
    final turnNumber = state.turnState['turnNumber'];
    final mandatoryDecisionSeconds =
        state.presetConfig['mandatoryDecisionSeconds'];
    final actor = actorMatches.single;
    if (turnNumber is! int ||
        turnNumber < 1 ||
        mandatoryDecisionSeconds is! int ||
        mandatoryDecisionSeconds <= 0 ||
        actor.position < 0 ||
        actor.position >= 40) {
      return reject(RollMovementErrorCode.invalidState);
    }
    if (actor.inCucha || actor.consecutiveDoubles != 0) {
      return reject(RollMovementErrorCode.invalidCommand);
    }
    if (rng.commitmentHex != state.header.rngCommitment) {
      return reject(RollMovementErrorCode.rngCommitmentMismatch);
    }

    final first = rng.nextInt(RngStream.dice, 6);
    final second = first.successor.nextInt(RngStream.dice, 6);
    final die1 = first.value + 1;
    final die2 = second.value + 1;
    if (die1 == die2) {
      return reject(RollMovementErrorCode.unsupportedVp0Landing);
    }
    final unwrappedDestination = actor.position + die1 + die2;
    final destination = unwrappedDestination % 40;
    final landingSpace = catalog.boardDefinition.spaces.singleWhere(
      (space) => space.index == destination,
    );

    // VP0 deliberately excludes passing Salida and every landing consequence
    // except opening an offer for an unowned property. The source RNG remains
    // immutable when this controlled fixture boundary is not satisfied.
    if (unwrappedDestination >= 40 ||
        !landingSpace.type.isProperty ||
        landingSpace.propertyId == null ||
        _isOwned(state, landingSpace.propertyId!)) {
      return reject(RollMovementErrorCode.unsupportedVp0Landing);
    }

    final propertyId = landingSpace.propertyId!;
    final decisionCreatedAt = transitionTime.toUtc();
    final decisionDeadlineAt = decisionCreatedAt.add(
      Duration(seconds: mandatoryDecisionSeconds),
    );
    final stateAfter = PublicGameState(
      header: GameStateHeader(
        schemaVersion: state.header.schemaVersion,
        stateVersion: version + 1,
        rulesVersion: state.header.rulesVersion,
        rngVersion: state.header.rngVersion,
        rngCommitment: state.header.rngCommitment,
        gameId: state.header.gameId,
        roomId: state.header.roomId,
        status: state.header.status,
      ),
      presetConfig: state.presetConfig,
      roundState: state.roundState,
      turnState: <String, Object?>{
        ...state.turnState,
        'phase': 'awaitingPropertyDecision',
        'landingPropertyId': propertyId,
        'lastRoll': <String, Object?>{
          'die1': die1,
          'die2': die2,
          'total': die1 + die2,
        },
      },
      players: <PlayerState>[
        for (final player in state.players)
          player.playerId == actor.playerId
              ? _atPosition(player, destination)
              : player,
      ],
      seatControllers: state.seatControllers,
      board: state.board,
      ownership: state.ownership,
      bank: state.bank,
      freeParkingPot: state.freeParkingPot,
      deckPublicState: state.deckPublicState,
      pendingDecision: <String, Object?>{
        'decisionId': '${command.commandId}:propertyOffer',
        'kind': 'propertyOffer',
        'allowedPlayerIds': <Object?>[command.actorPlayerId],
        'stateVersionCreated': version + 1,
        'createdAt': decisionCreatedAt.toIso8601String(),
        'deadlineAt': decisionDeadlineAt.toIso8601String(),
        'timeoutPolicy': 'pass',
        'payload': <String, Object?>{
          'propertyId': propertyId,
          'purchasePrice':
              catalog.economyCatalog.properties[propertyId]!.purchasePrice,
        },
      },
      activeAuction: state.activeAuction,
      activeTrade: state.activeTrade,
      debtCase: state.debtCase,
      result: state.result,
      lastMutation: <String, Object?>{
        'type': 'rollMovement',
        'commandId': command.commandId,
        'actorPlayerId': command.actorPlayerId,
      },
    );
    final events = <GameDomainEvent>[
      GameDomainEvent(
        type: 'diceRolled',
        data: <String, Object?>{
          'playerId': command.actorPlayerId,
          'die1': die1,
          'die2': die2,
          'total': die1 + die2,
        },
      ),
      GameDomainEvent(
        type: 'playerMoved',
        data: <String, Object?>{
          'playerId': command.actorPlayerId,
          'from': actor.position,
          'to': destination,
          'spaces': die1 + die2,
        },
      ),
    ];

    return RollMovementPlan(
      commandId: command.commandId,
      stateVersionBefore: version,
      actorPlayerId: command.actorPlayerId,
      die1: die1,
      die2: die2,
      fromPosition: actor.position,
      toPosition: destination,
      propertyId: propertyId,
      candidatesConsumed: first.candidatesConsumed + second.candidatesConsumed,
      successorRng: second.successor,
      stateAfter: stateAfter,
      events: events,
    );
  }
}

bool _isOwned(PublicGameState state, String propertyId) =>
    state.players.any((player) => player.ownedPropertyIds.contains(propertyId));

PlayerState _atPosition(PlayerState player, int position) => PlayerState(
  playerId: player.playerId,
  seat: player.seat,
  kind: player.kind,
  status: player.status,
  cash: player.cash,
  position: position,
  ownedPropertyIds: player.ownedPropertyIds,
  keepCardIds: player.keepCardIds,
  inCucha: player.inCucha,
  cuchaAttempts: player.cuchaAttempts,
  consecutiveDoubles: player.consecutiveDoubles,
  connectivityStatus: player.connectivityStatus,
);
