import 'dart:convert';

import 'canonical_rng.dart';

final class DomainContractViolation implements Exception {
  const DomainContractViolation(this.message);

  final String message;

  @override
  String toString() => 'DomainContractViolation: $message';
}

enum GameCommandType {
  rollDice('RollDice'),
  chooseCuchaExit('ChooseCuchaExit'),
  buyProperty('BuyProperty'),
  declineProperty('DeclineProperty'),
  buildImprovement('BuildImprovement'),
  sellImprovement('SellImprovement'),
  mortgageProperty('MortgageProperty'),
  liftMortgage('LiftMortgage'),
  placeBid('PlaceBid'),
  passAuction('PassAuction'),
  proposeTrade('ProposeTrade'),
  acceptTrade('AcceptTrade'),
  rejectTrade('RejectTrade'),
  cancelTrade('CancelTrade'),
  resolveCardChoice('ResolveCardChoice'),
  payDebt('PayDebt'),
  declareBankruptcy('DeclareBankruptcy');

  const GameCommandType(this.wireValue);

  final String wireValue;
}

enum GameCommandStatus {
  accepted('accepted'),
  rejected('rejected'),
  duplicate('duplicate');

  const GameCommandStatus(this.wireValue);

  final String wireValue;
}

enum PlayerKind {
  human('human'),
  bot('bot');

  const PlayerKind(this.wireValue);

  final String wireValue;
}

enum PlayerStatus {
  active('active'),
  bankrupt('bankrupt'),
  finished('finished');

  const PlayerStatus(this.wireValue);

  final String wireValue;
}

enum ConnectivityStatus {
  online('online'),
  reconnecting('reconnecting'),
  absent('absent');

  const ConnectivityStatus(this.wireValue);

  final String wireValue;
}

enum SeatController {
  human('human'),
  bot('bot');

  const SeatController(this.wireValue);

  final String wireValue;
}

enum TakeoverReason {
  disconnectTimeout('disconnect_timeout'),
  blockingTimeout('blocking_timeout');

  const TakeoverReason(this.wireValue);

  final String wireValue;
}

enum PropertyKind {
  street('street'),
  transport('transport'),
  utility('utility');

  const PropertyKind(this.wireValue);

  final String wireValue;
}

enum GameStatus {
  active('active'),
  finished('finished');

  const GameStatus(this.wireValue);

  final String wireValue;
}

/// Canonical integer-only JSON used by domain goldens and command identity.
abstract final class CanonicalDomainJson {
  static String encode(Map<String, Object?> value) =>
      jsonEncode(_normalizeJson(value));
}

final class GameCommand {
  GameCommand({
    required this.commandId,
    required this.schemaVersion,
    required this.expectedStateVersion,
    required this.clientInstanceId,
    required this.gameId,
    required this.actorPlayerId,
    required this.type,
    required Map<String, Object?> payload,
    DateTime? sentAt,
  }) : payload = _immutableJsonObject(payload),
       sentAt = sentAt?.toUtc() {
    _requireIdentifier(commandId, 'commandId');
    _requireSchemaVersion(schemaVersion);
    _requireNonNegative(expectedStateVersion, 'expectedStateVersion');
    _requireIdentifier(clientInstanceId, 'clientInstanceId');
    _requireIdentifier(gameId, 'gameId');
    _requireIdentifier(actorPlayerId, 'actorPlayerId');
  }

  final String commandId;
  final int schemaVersion;
  final int expectedStateVersion;
  final String clientInstanceId;
  final String gameId;
  final String actorPlayerId;
  final GameCommandType type;
  final Map<String, Object?> payload;
  final DateTime? sentAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'commandId': commandId,
    'schemaVersion': schemaVersion,
    'expectedStateVersion': expectedStateVersion,
    'clientInstanceId': clientInstanceId,
    'gameId': gameId,
    'actorPlayerId': actorPlayerId,
    'type': type.wireValue,
    'payload': payload,
    if (sentAt != null) 'sentAt': sentAt!.toIso8601String(),
  };

  String toCanonicalJson() => CanonicalDomainJson.encode(toJson());
}

final class GameDomainEvent {
  GameDomainEvent({required this.type, Map<String, Object?> data = const {}})
    : data = _immutableJsonObject(data) {
    _requireIdentifier(type, 'event.type');
  }

  final String type;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'data': data,
  };
}

final class GameCommandResult {
  GameCommandResult({
    required this.commandId,
    required this.status,
    required this.stateVersionBefore,
    required this.stateVersionAfter,
    required List<GameDomainEvent> events,
    required DateTime serverProcessedAt,
    this.errorCode,
    Map<String, Object?>? errorDetailsSafe,
    this.snapshotHash,
  }) : events = List.unmodifiable(events),
       errorDetailsSafe = errorDetailsSafe == null
           ? null
           : _immutableJsonObject(errorDetailsSafe),
       serverProcessedAt = serverProcessedAt.toUtc() {
    _requireIdentifier(commandId, 'commandId');
    _requireNonNegative(stateVersionBefore, 'stateVersionBefore');
    _requireNonNegative(stateVersionAfter, 'stateVersionAfter');
    final versionDelta = stateVersionAfter - stateVersionBefore;
    if (versionDelta < 0 || versionDelta > 1) {
      throw const DomainContractViolation(
        'A command result may advance stateVersion at most once',
      );
    }
    if (status == GameCommandStatus.accepted && versionDelta != 1) {
      throw const DomainContractViolation(
        'An accepted gameplay command must increment stateVersion once',
      );
    }
    if (status == GameCommandStatus.rejected && versionDelta != 0) {
      throw const DomainContractViolation(
        'A rejected command must not mutate stateVersion',
      );
    }
    if (status == GameCommandStatus.rejected &&
        (errorCode == null || errorCode!.isEmpty)) {
      throw const DomainContractViolation(
        'A rejected command requires a safe errorCode',
      );
    }
    if (snapshotHash != null && snapshotHash!.isEmpty) {
      throw const DomainContractViolation('snapshotHash must not be empty');
    }
  }

  final String commandId;
  final GameCommandStatus status;
  final int stateVersionBefore;
  final int stateVersionAfter;
  final String? errorCode;
  final Map<String, Object?>? errorDetailsSafe;
  final List<GameDomainEvent> events;
  final String? snapshotHash;
  final DateTime serverProcessedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'commandId': commandId,
    'status': status.wireValue,
    'stateVersionBefore': stateVersionBefore,
    'stateVersionAfter': stateVersionAfter,
    if (errorCode != null) 'errorCode': errorCode,
    if (errorDetailsSafe != null) 'errorDetailsSafe': errorDetailsSafe,
    'events': events.map((event) => event.toJson()).toList(growable: false),
    if (snapshotHash != null) 'snapshotHash': snapshotHash,
    'serverProcessedAt': serverProcessedAt.toIso8601String(),
  };

  String toCanonicalJson() => CanonicalDomainJson.encode(toJson());
}

final class PlayerState {
  PlayerState({
    required this.playerId,
    required this.seat,
    required this.kind,
    required this.status,
    required this.cash,
    required this.position,
    required List<String> ownedPropertyIds,
    required List<String> keepCardIds,
    required this.inCucha,
    required this.cuchaAttempts,
    required this.consecutiveDoubles,
    required this.connectivityStatus,
  }) : ownedPropertyIds = _immutableIdentifiers(
         ownedPropertyIds,
         'ownedPropertyIds',
       ),
       keepCardIds = _immutableIdentifiers(keepCardIds, 'keepCardIds') {
    _requireIdentifier(playerId, 'playerId');
    _requireNonNegative(seat, 'seat');
    _requireNonNegative(cash, 'cash');
    _requireNonNegative(position, 'position');
    if (cuchaAttempts < 0 || cuchaAttempts > 3) {
      throw const DomainContractViolation('cuchaAttempts must be within 0..3');
    }
    if (!inCucha && cuchaAttempts != 0) {
      throw const DomainContractViolation(
        'A player outside Cucha cannot retain Cucha attempts',
      );
    }
    if (consecutiveDoubles < 0 || consecutiveDoubles > 2) {
      throw const DomainContractViolation(
        'Stable state consecutiveDoubles must be within 0..2',
      );
    }
  }

  final String playerId;
  final int seat;
  final PlayerKind kind;
  final PlayerStatus status;
  final int cash;
  final int position;
  final List<String> ownedPropertyIds;
  final List<String> keepCardIds;
  final bool inCucha;
  final int cuchaAttempts;
  final int consecutiveDoubles;
  final ConnectivityStatus connectivityStatus;

  Map<String, Object?> toJson() => <String, Object?>{
    'playerId': playerId,
    'seat': seat,
    'kind': kind.wireValue,
    'status': status.wireValue,
    'cash': cash,
    'position': position,
    'ownedPropertyIds': ownedPropertyIds,
    'keepCards': keepCardIds,
    'inCucha': inCucha,
    'cuchaAttempts': cuchaAttempts,
    'consecutiveDoubles': consecutiveDoubles,
    'connectivityStatus': connectivityStatus.wireValue,
  };
}

final class SeatControllerState {
  SeatControllerState({
    required this.playerId,
    required this.controller,
    this.botPolicyId,
    this.takeoverReason,
    DateTime? takeoverStartedAt,
    required this.humanReclaimPending,
  }) : takeoverStartedAt = takeoverStartedAt?.toUtc() {
    _requireIdentifier(playerId, 'playerId');
    if (controller == SeatController.human) {
      if (botPolicyId != null ||
          takeoverReason != null ||
          takeoverStartedAt != null ||
          humanReclaimPending) {
        throw const DomainContractViolation(
          'A human-controlled seat cannot retain bot takeover state',
        );
      }
    } else if (botPolicyId == null || botPolicyId!.isEmpty) {
      throw const DomainContractViolation(
        'A bot-controlled seat requires botPolicyId',
      );
    }
    if ((takeoverReason == null) != (takeoverStartedAt == null)) {
      throw const DomainContractViolation(
        'takeoverReason and takeoverStartedAt must appear together',
      );
    }
  }

  final String playerId;
  final SeatController controller;
  final String? botPolicyId;
  final TakeoverReason? takeoverReason;
  final DateTime? takeoverStartedAt;
  final bool humanReclaimPending;

  Map<String, Object?> toJson() => <String, Object?>{
    'playerId': playerId,
    'controller': controller.wireValue,
    if (botPolicyId != null) 'botPolicyId': botPolicyId,
    if (takeoverReason != null) 'takeoverReason': takeoverReason!.wireValue,
    if (takeoverStartedAt != null)
      'takeoverStartedAt': takeoverStartedAt!.toIso8601String(),
    'humanReclaimPending': humanReclaimPending,
  };
}

final class PropertyState {
  PropertyState({
    required this.propertyId,
    required this.kind,
    this.ownerPlayerId,
    required this.mortgaged,
    required this.improvementLevel,
  }) {
    _requireIdentifier(propertyId, 'propertyId');
    if (ownerPlayerId != null) {
      _requireIdentifier(ownerPlayerId!, 'ownerPlayerId');
    }
    if (improvementLevel < 0 || improvementLevel > 5) {
      throw const DomainContractViolation(
        'improvementLevel must be within 0..5',
      );
    }
    if (ownerPlayerId == null && (mortgaged || improvementLevel != 0)) {
      throw const DomainContractViolation(
        'An unowned property cannot be mortgaged or improved',
      );
    }
    if (kind != PropertyKind.street && improvementLevel != 0) {
      throw const DomainContractViolation(
        'Only a street can contain Manís or a Popón',
      );
    }
    if (mortgaged && improvementLevel != 0) {
      throw const DomainContractViolation(
        'A mortgaged property cannot retain improvements',
      );
    }
  }

  final String propertyId;
  final PropertyKind kind;
  final String? ownerPlayerId;
  final bool mortgaged;
  final int improvementLevel;

  Map<String, Object?> toJson() => <String, Object?>{
    'propertyId': propertyId,
    'kind': kind.wireValue,
    if (ownerPlayerId != null) 'ownerPlayerId': ownerPlayerId,
    'mortgaged': mortgaged,
    'improvementLevel': improvementLevel,
  };
}

final class GameStateHeader {
  GameStateHeader({
    required this.schemaVersion,
    required this.stateVersion,
    required this.rulesVersion,
    required this.rngVersion,
    required this.rngCommitment,
    required this.gameId,
    required this.roomId,
    required this.status,
  }) {
    _requireSchemaVersion(schemaVersion);
    _requireNonNegative(stateVersion, 'stateVersion');
    _requireIdentifier(rulesVersion, 'rulesVersion');
    if (rngVersion != canonicalRngVersion) {
      throw DomainContractViolation('Unsupported rngVersion: $rngVersion');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(rngCommitment)) {
      throw const DomainContractViolation(
        'rngCommitment must be 32-byte lowercase hex',
      );
    }
    _requireIdentifier(gameId, 'gameId');
    _requireIdentifier(roomId, 'roomId');
  }

  final int schemaVersion;
  final int stateVersion;
  final String rulesVersion;
  final String rngVersion;
  final String rngCommitment;
  final String gameId;
  final String roomId;
  final GameStatus status;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'stateVersion': stateVersion,
    'rulesVersion': rulesVersion,
    'rngVersion': rngVersion,
    'rngCommitment': rngCommitment,
    'gameId': gameId,
    'roomId': roomId,
    'status': status.wireValue,
  };
}

/// Stable, public-only state aggregate from Domain Contracts v0.7.
///
/// Subtrees whose executable catalog/content contract is not frozen yet remain
/// integer-only immutable JSON. This prevents the domain layer from inventing
/// economy or board values while still enforcing the public/private boundary.
final class PublicGameState {
  PublicGameState({
    required this.header,
    required Map<String, Object?> presetConfig,
    required Map<String, Object?> roundState,
    required Map<String, Object?> turnState,
    required List<PlayerState> players,
    required List<SeatControllerState> seatControllers,
    required Map<String, Object?> board,
    required Map<String, Object?> ownership,
    required Map<String, Object?> bank,
    required this.freeParkingPot,
    required Map<String, Object?> deckPublicState,
    Map<String, Object?>? pendingDecision,
    Map<String, Object?>? activeAuction,
    Map<String, Object?>? activeTrade,
    Map<String, Object?>? debtCase,
    Map<String, Object?>? result,
    required Map<String, Object?> lastMutation,
  }) : presetConfig = _immutableJsonObject(presetConfig),
       roundState = _immutableJsonObject(roundState),
       turnState = _immutableJsonObject(turnState),
       players = List.unmodifiable(players),
       seatControllers = List.unmodifiable(seatControllers),
       board = _immutableJsonObject(board),
       ownership = _immutableJsonObject(ownership),
       bank = _immutableJsonObject(bank),
       deckPublicState = _immutableJsonObject(deckPublicState),
       pendingDecision = pendingDecision == null
           ? null
           : _immutableJsonObject(pendingDecision),
       activeAuction = activeAuction == null
           ? null
           : _immutableJsonObject(activeAuction),
       activeTrade = activeTrade == null
           ? null
           : _immutableJsonObject(activeTrade),
       debtCase = debtCase == null ? null : _immutableJsonObject(debtCase),
       result = result == null ? null : _immutableJsonObject(result),
       lastMutation = _immutableJsonObject(lastMutation) {
    _requireNonNegative(freeParkingPot, 'freeParkingPot');
    if (players.isEmpty) {
      throw const DomainContractViolation(
        'PublicGameState requires at least one player',
      );
    }
    _requireUnique(
      players.map((player) => player.playerId),
      'players.playerId',
    );
    _requireUnique(players.map((player) => player.seat), 'players.seat');
    _requireUnique(
      seatControllers.map((controller) => controller.playerId),
      'seatControllers.playerId',
    );
    final playerIds = players.map((player) => player.playerId).toSet();
    final controllerIds = seatControllers
        .map((controller) => controller.playerId)
        .toSet();
    if (!playerIds.containsAll(controllerIds)) {
      throw const DomainContractViolation(
        'A seat controller must reference a player in this game',
      );
    }
    final activePlayerIds = players
        .where((player) => player.status == PlayerStatus.active)
        .map((player) => player.playerId)
        .toSet();
    if (!controllerIds.containsAll(activePlayerIds)) {
      throw const DomainContractViolation(
        'Every active player must have exactly one seat controller',
      );
    }
    if ((header.status == GameStatus.finished) != (result != null)) {
      throw const DomainContractViolation(
        'Finished status and result must appear together',
      );
    }
  }

  final GameStateHeader header;
  final Map<String, Object?> presetConfig;
  final Map<String, Object?> roundState;
  final Map<String, Object?> turnState;
  final List<PlayerState> players;
  final List<SeatControllerState> seatControllers;
  final Map<String, Object?> board;
  final Map<String, Object?> ownership;
  final Map<String, Object?> bank;
  final int freeParkingPot;
  final Map<String, Object?> deckPublicState;
  final Map<String, Object?>? pendingDecision;
  final Map<String, Object?>? activeAuction;
  final Map<String, Object?>? activeTrade;
  final Map<String, Object?>? debtCase;
  final Map<String, Object?>? result;
  final Map<String, Object?> lastMutation;

  Map<String, Object?> toJson() => <String, Object?>{
    ...header.toJson(),
    'presetConfig': presetConfig,
    'roundState': roundState,
    'turnState': turnState,
    'players': players.map((player) => player.toJson()).toList(growable: false),
    'seatControllers': seatControllers
        .map((controller) => controller.toJson())
        .toList(growable: false),
    'board': board,
    'ownership': ownership,
    'bank': bank,
    'freeParkingPot': freeParkingPot,
    'deckPublicState': deckPublicState,
    if (pendingDecision != null) 'pendingDecision': pendingDecision,
    if (activeAuction != null) 'activeAuction': activeAuction,
    if (activeTrade != null) 'activeTrade': activeTrade,
    if (debtCase != null) 'debtCase': debtCase,
    if (result != null) 'result': result,
    'lastMutation': lastMutation,
  };

  String toCanonicalJson() => CanonicalDomainJson.encode(toJson());
}

Map<String, Object?> _immutableJsonObject(Map<String, Object?> value) =>
    Map.unmodifiable(_normalizeJson(value) as Map<String, Object?>);

Object? _normalizeJson(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is num) {
    throw const DomainContractViolation(
      'Domain numeric material must use integers only',
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
  throw DomainContractViolation(
    'Unsupported domain JSON value: ${value.runtimeType}',
  );
}

List<String> _immutableIdentifiers(List<String> values, String field) {
  if (values.any((value) => value.isEmpty)) {
    throw DomainContractViolation('$field contains an empty identifier');
  }
  if (values.toSet().length != values.length) {
    throw DomainContractViolation('$field contains duplicates');
  }
  return List.unmodifiable(values);
}

void _requireIdentifier(String value, String field) {
  if (value.isEmpty) {
    throw DomainContractViolation('$field must not be empty');
  }
}

void _requireSchemaVersion(int value) {
  if (value != 1) {
    throw DomainContractViolation('Unsupported schemaVersion: $value');
  }
}

void _requireNonNegative(int value, String field) {
  if (value < 0) {
    throw DomainContractViolation('$field must be non-negative');
  }
}

void _requireUnique(Iterable<Object> values, String field) {
  final materialized = values.toList(growable: false);
  if (materialized.toSet().length != materialized.length) {
    throw DomainContractViolation('$field contains duplicates');
  }
}
