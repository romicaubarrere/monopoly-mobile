import 'dart:typed_data';

import 'package:board_game_contracts/game_contracts.dart';
import 'package:board_game_core/game_core.dart';

final class ReadyStartViolation implements Exception {
  const ReadyStartViolation(this.code);

  final String code;

  @override
  String toString() => 'ReadyStartViolation: $code';
}

final class ReadyRoomMember {
  const ReadyRoomMember({
    required this.uid,
    required this.playerId,
    required this.kind,
    required this.ready,
    this.botPolicyId,
  });

  final String uid;
  final String playerId;
  final PlayerKind kind;
  final bool ready;
  final String? botPolicyId;
}

/// Authority-private material that must commit with the public initial state.
final class ReadyStartPrivateState {
  ReadyStartPrivateState({
    required List<int> seed,
    required Map<RngStream, int> streamCounters,
    required List<String> cardsAOrder,
    required List<String> cardsBOrder,
  }) : seed = Uint8List.fromList(seed),
       streamCounters = Map<RngStream, int>.unmodifiable(streamCounters),
       cardsAOrder = List<String>.unmodifiable(cardsAOrder),
       cardsBOrder = List<String>.unmodifiable(cardsBOrder);

  final Uint8List seed;
  final Map<RngStream, int> streamCounters;
  final List<String> cardsAOrder;
  final List<String> cardsBOrder;

  Map<String, Object?> toPersistenceJson() => <String, Object?>{
    'schemaVersion': 1,
    'rngVersion': canonicalRngVersion,
    'seedBytes': seed,
    'streamCounters': <String, Object?>{
      for (final stream in RngStream.values)
        stream.label: streamCounters[stream],
    },
    'privateDeckState': <String, Object?>{
      'cardsAOrder': cardsAOrder,
      'cardsBOrder': cardsBOrder,
    },
  };
}

final class ReadyStartPlan {
  ReadyStartPlan({
    required this.commandId,
    required this.roomId,
    required this.roomVersionBefore,
    required this.gameId,
    required this.publicState,
    required this.privateState,
    required this.starterAllocation,
  });

  final String commandId;
  final String roomId;
  final int roomVersionBefore;
  final String gameId;
  final PublicGameState publicState;
  final ReadyStartPrivateState privateState;
  final StarterAllocationResult starterAllocation;

  int get roomVersionAfter => roomVersionBefore + 1;

  Map<String, Object?> get safeResultSummary => <String, Object?>{
    'gameId': gameId,
    'stateVersion': publicState.header.stateVersion,
    'rulesVersion': publicState.header.rulesVersion,
    'presetConfig': publicState.presetConfig,
    'seatOrder': publicState.players
        .map((player) => player.playerId)
        .toList(growable: false),
    'starterAllocation': starterAllocation.allocations
        .map((allocation) => allocation.toJson())
        .toList(growable: false),
  };

  Map<String, Object?> get roomMutation => <String, Object?>{
    'status': 'active',
    'gameId': gameId,
    'roomVersion': roomVersionAfter,
    'frozenRulesVersion': publicState.header.rulesVersion,
    'frozenPresetConfig': publicState.presetConfig,
  };

  RoomCommandResult commandResult(DateTime processedAt) => RoomCommandResult(
    commandId: commandId,
    status: RoomCommandStatus.accepted,
    roomVersionBefore: roomVersionBefore,
    roomVersionAfter: roomVersionAfter,
    gameId: gameId,
    roomSnapshot: <String, Object?>{'roomId': roomId, ...roomMutation},
    serverProcessedAt: processedAt,
  );
}

/// Pure composition of the accepted Engine contracts for StartGame.
///
/// Secure seed and gameId are established once outside a Firestore transaction
/// retry callback. A durable adapter persists this plan atomically or returns a
/// prior persisted result for the same command identity.
abstract final class ReadyStartPlanner {
  static ReadyStartPlan plan({
    required RoomCommand command,
    required String authenticatedActorUid,
    required String hostUid,
    required String gameId,
    required String presetId,
    required List<ReadyRoomMember> members,
    required RulesCatalog catalog,
    required List<int> secureSeed,
  }) {
    if (command.type != RoomCommandType.startGame) {
      throw const ReadyStartViolation('unsupportedRoomCommand');
    }
    if (authenticatedActorUid != hostUid) {
      throw const ReadyStartViolation('notRoomHost');
    }
    if (gameId.isEmpty) throw const ReadyStartViolation('invalidGameId');
    if (members.length < 2) {
      throw const ReadyStartViolation('notEnoughPlayers');
    }
    if (members.any((member) => !member.ready)) {
      throw const ReadyStartViolation('notAllPlayersReady');
    }
    if (_duplicates(members.map((member) => member.uid)) ||
        _duplicates(members.map((member) => member.playerId))) {
      throw const ReadyStartViolation('duplicateMemberIdentity');
    }
    for (final member in members) {
      if (member.uid.isEmpty || member.playerId.isEmpty) {
        throw const ReadyStartViolation('invalidMemberIdentity');
      }
      if (member.kind == PlayerKind.bot &&
          (member.botPolicyId == null || member.botPolicyId!.isEmpty)) {
        throw const ReadyStartViolation('botPolicyRequired');
      }
      if (member.kind == PlayerKind.human && member.botPolicyId != null) {
        throw const ReadyStartViolation('humanBotPolicyForbidden');
      }
    }

    final roomId = command.payload['roomId']! as String;
    final roomVersion = command.expectedRoomVersion!;
    var rng = CanonicalRng(seed: secureSeed);
    final seatShuffle = rng.shuffle(RngStream.seatOrder, members);
    rng = seatShuffle.successor;
    final seatOrder = seatShuffle.value;
    final resolvedPreset = catalog.resolvePreset(presetId, members.length);
    final allocation = allocateStarterProperties(
      catalog: catalog,
      preset: resolvedPreset,
      playerIdsInSeatOrder: seatOrder
          .map((member) => member.playerId)
          .toList(growable: false),
      rng: rng,
    );
    rng = allocation.rngSuccessor;

    final cardsA = catalog.deckCatalog.cards
        .where((card) => card.deckId == 'cards_a')
        .map((card) => card.cardId)
        .toList(growable: false);
    final cardsB = catalog.deckCatalog.cards
        .where((card) => card.deckId == 'cards_b')
        .map((card) => card.cardId)
        .toList(growable: false);
    final cardsAShuffle = rng.shuffle(RngStream.cardsAShuffle, cardsA);
    rng = cardsAShuffle.successor;
    final cardsBShuffle = rng.shuffle(RngStream.cardsBShuffle, cardsB);
    rng = cardsBShuffle.successor;

    final allocationsByPlayer = <String, StarterSeatAllocation>{
      for (final item in allocation.allocations) item.playerId: item,
    };
    final players = <PlayerState>[
      for (final (seat, member) in seatOrder.indexed)
        PlayerState(
          playerId: member.playerId,
          seat: seat,
          kind: member.kind,
          status: PlayerStatus.active,
          cash: allocationsByPlayer[member.playerId]!.cash,
          position: 0,
          ownedPropertyIds: allocationsByPlayer[member.playerId]!.propertyIds,
          keepCardIds: const <String>[],
          inCucha: false,
          cuchaAttempts: 0,
          consecutiveDoubles: 0,
          connectivityStatus: ConnectivityStatus.online,
        ),
    ];
    final ownerByProperty = <String, String>{
      for (final allocation in allocation.allocations)
        for (final propertyId in allocation.propertyIds)
          propertyId: allocation.playerId,
    };
    final properties = <PropertyState>[
      for (final space in catalog.boardDefinition.propertySpaces)
        PropertyState(
          propertyId: space.propertyId!,
          kind: switch (space.type) {
            BoardSpaceType.street => PropertyKind.street,
            BoardSpaceType.transport => PropertyKind.transport,
            BoardSpaceType.utility => PropertyKind.utility,
            _ => throw const ReadyStartViolation('invalidPropertySpace'),
          },
          ownerPlayerId: ownerByProperty[space.propertyId],
          mortgaged: false,
          improvementLevel: 0,
        ),
    ];
    final publicState = PublicGameState(
      header: GameStateHeader(
        schemaVersion: 1,
        stateVersion: 0,
        rulesVersion: catalog.rulesVersion,
        rngVersion: canonicalRngVersion,
        rngCommitment: rng.commitmentHex,
        gameId: gameId,
        roomId: roomId,
        status: GameStatus.active,
      ),
      presetConfig: resolvedPreset.toJson(),
      roundState: const <String, Object?>{'round': 1},
      turnState: <String, Object?>{
        'turnNumber': 1,
        'phase': 'awaitingRoll',
        'currentPlayerId': players.first.playerId,
      },
      players: players,
      seatControllers: <SeatControllerState>[
        for (final member in seatOrder)
          SeatControllerState(
            playerId: member.playerId,
            controller: member.kind == PlayerKind.bot
                ? SeatController.bot
                : SeatController.human,
            botPolicyId: member.botPolicyId,
            humanReclaimPending: false,
          ),
      ],
      board: <String, Object?>{
        'boardId': catalog.boardDefinition.boardId,
        'boardDefinitionVersion': catalog.boardDefinitionVersion,
      },
      ownership: <String, Object?>{
        'properties': properties
            .map((property) => property.toJson())
            .toList(growable: false),
      },
      bank: <String, Object?>{
        'currencyUnit': catalog.economyCatalog.currencyUnit,
      },
      freeParkingPot: 0,
      deckPublicState: <String, Object?>{
        'cardsARemaining': cardsA.length,
        'cardsBRemaining': cardsB.length,
      },
      lastMutation: <String, Object?>{
        'type': 'gameStarted',
        'commandId': command.commandId,
      },
    );
    final privateState = ReadyStartPrivateState(
      seed: secureSeed,
      streamCounters: <RngStream, int>{
        for (final stream in RngStream.values) stream: rng.counterFor(stream),
      },
      cardsAOrder: cardsAShuffle.value,
      cardsBOrder: cardsBShuffle.value,
    );

    return ReadyStartPlan(
      commandId: command.commandId,
      roomId: roomId,
      roomVersionBefore: roomVersion,
      gameId: gameId,
      publicState: publicState,
      privateState: privateState,
      starterAllocation: allocation,
    );
  }
}

bool _duplicates(Iterable<String> values) {
  final materialized = values.toList(growable: false);
  return materialized.toSet().length != materialized.length;
}
