import 'package:board_backend_api/backend_api.dart';

enum FirstPlayableStep {
  home,
  create,
  join,
  lobby,
  board,
  property,
  auction,
  reconnect,
}

enum SnapshotErrorSource { room, game }

/// Read-only presentation projection. The authoritative snapshots are retained
/// unchanged; transport/UI flags are the only state this layer originates.
final class LiveFirstPlayableUiState {
  const LiveFirstPlayableUiState({
    required this.step,
    this.lobby,
    this.game,
    this.roomCode,
    this.safeError,
    this.snapshotErrorSource,
    this.snapshotErrorRecoverable = false,
    this.busy = false,
    this.reconnectRequired = false,
    this.confirmedLobbySnapshot,
    this.confirmedGameSnapshot,
  });
  final FirstPlayableStep step;
  final LobbyUiState? lobby;
  final BoardUiState? game;
  final String? roomCode;
  final String? safeError;
  final SnapshotErrorSource? snapshotErrorSource;
  final bool snapshotErrorRecoverable;
  final bool busy;
  final bool reconnectRequired;
  final AuthorityPublicRoomSnapshot? confirmedLobbySnapshot;
  final AuthorityPublicSnapshot? confirmedGameSnapshot;
}

final class LobbyUiState {
  LobbyUiState({
    required this.roomVersion,
    required this.actorPlayerId,
    required this.hostPlayerId,
    required this.gameId,
    required Iterable<LobbyMemberUiState> members,
  }) : members = List.unmodifiable(members);

  factory LobbyUiState.fromSnapshot(AuthorityPublicRoomSnapshot snapshot) {
    final value = snapshot.snapshot;
    final actorPlayerId = value['actorPlayerId'];
    final hostPlayerId = value['hostPlayerId'];
    final gameId = snapshot.gameId;
    final rawMembers = value['members'];
    if (actorPlayerId is! String ||
        actorPlayerId.isEmpty ||
        hostPlayerId is! String ||
        hostPlayerId.isEmpty ||
        rawMembers is! List<Object?>) {
      throw const FormatException('invalidPublicLobbySnapshot');
    }
    final members = rawMembers
        .map((raw) {
          if (raw is! Map<String, Object?>) {
            throw const FormatException('invalidPublicLobbyMember');
          }
          final playerId = raw['playerId'];
          final ready = raw['ready'];
          final kind = raw['kind'];
          if (playerId is! String ||
              playerId.isEmpty ||
              ready is! bool ||
              kind is! String ||
              kind.isEmpty) {
            throw const FormatException('invalidPublicLobbyMember');
          }
          return LobbyMemberUiState(
            playerId: playerId,
            ready: ready,
            kind: kind,
          );
        })
        .toList(growable: false);
    if (members.isEmpty ||
        !members.any((member) => member.playerId == actorPlayerId) ||
        !members.any((member) => member.playerId == hostPlayerId)) {
      throw const FormatException('invalidPublicLobbyMembership');
    }
    return LobbyUiState(
      roomVersion: snapshot.roomVersion,
      actorPlayerId: actorPlayerId,
      hostPlayerId: hostPlayerId,
      gameId: gameId,
      members: members,
    );
  }

  final int roomVersion;
  final String actorPlayerId;
  final String hostPlayerId;
  final String? gameId;
  final List<LobbyMemberUiState> members;
}

final class LobbyMemberUiState {
  const LobbyMemberUiState({
    required this.playerId,
    required this.ready,
    required this.kind,
  });

  final String playerId;
  final bool ready;
  final String kind;
}

final class BoardUiState {
  const BoardUiState({
    required this.gameId,
    required this.stateVersion,
    required this.presetId,
    required this.status,
    required this.phase,
    required this.currentPlayerId,
    required this.lastRoll,
    required this.actorPlayerId,
    required this.propertyOffer,
    required this.auction,
    required this.winnerPlayerId,
    required this.buyAuctionOutcomeReceipt,
  });

  factory BoardUiState.fromSnapshot(
    AuthorityPublicSnapshot snapshot, {
    required String actorPlayerId,
  }) {
    final value = snapshot.snapshot;
    final preset = _requiredObject(value['presetConfig'], 'presetConfig');
    final turn = _requiredObject(value['turnState'], 'turnState');
    final presetId = _requiredString(preset['presetId'], 'presetId');
    final status = _requiredString(value['status'], 'status');
    final phase = _requiredString(turn['phase'], 'turnState.phase');
    final currentPlayerId = _requiredString(
      turn['currentPlayerId'],
      'turnState.currentPlayerId',
    );
    final rawLastRoll = _optionalObject(turn['lastRoll']);
    final lastRoll = rawLastRoll == null
        ? null
        : ConfirmedRollUiState.fromSnapshot(rawLastRoll);
    final pending = _optionalObject(value['pendingDecision']);
    final activeAuction = _optionalObject(value['activeAuction']);
    final propertyOffer = pending?['kind'] == 'propertyOffer'
        ? PropertyOfferUiState.fromSnapshot(pending!)
        : null;
    final auction = activeAuction == null
        ? null
        : AuctionUiState.fromSnapshot(activeAuction);
    final result = _optionalObject(value['result']);
    final winnerPlayerId = result?['winnerPlayerId'];
    if (winnerPlayerId != null &&
        (winnerPlayerId is! String || winnerPlayerId.isEmpty)) {
      throw const FormatException('invalidPublicGameResult');
    }
    final buyAuctionOutcomeReceipt = BuyAuctionOutcomeReceipt.fromLastMutation(
      value['lastMutation'],
      ownership: value['ownership'],
    );
    if (buyAuctionOutcomeReceipt != null &&
        (phase != 'turnResolved' || pending != null || activeAuction != null)) {
      throw const FormatException(
        'invalidPublicGameSnapshot:lastMutation.outcome.context',
      );
    }
    return BoardUiState(
      gameId: snapshot.gameId,
      stateVersion: snapshot.stateVersion,
      presetId: presetId,
      status: status,
      phase: phase,
      currentPlayerId: currentPlayerId,
      lastRoll: lastRoll,
      actorPlayerId: actorPlayerId,
      propertyOffer: propertyOffer,
      auction: auction,
      winnerPlayerId: winnerPlayerId as String?,
      buyAuctionOutcomeReceipt: buyAuctionOutcomeReceipt,
    );
  }

  final String gameId;
  final int stateVersion;
  final String presetId;
  final String status;
  final String phase;
  final String currentPlayerId;
  final ConfirmedRollUiState? lastRoll;
  final String actorPlayerId;
  final PropertyOfferUiState? propertyOffer;
  final AuctionUiState? auction;
  final String? winnerPlayerId;
  final BuyAuctionOutcomeReceipt? buyAuctionOutcomeReceipt;

  bool get finished => status == 'finished';
  bool get isActorTurn => currentPlayerId == actorPlayerId;
  bool get awaitingRoll => phase == 'awaitingRoll';
  bool get canResolveProperty =>
      propertyOffer != null &&
      propertyOffer!.allowedPlayerIds.contains(actorPlayerId);
  bool get canBid =>
      auction != null && auction!.currentBidderPlayerId == actorPlayerId;
}

final class ConfirmedRollUiState {
  const ConfirmedRollUiState({
    required this.die1,
    required this.die2,
    required this.total,
  });

  factory ConfirmedRollUiState.fromSnapshot(Map<String, Object?> value) {
    final die1 = _requiredDie(value['die1'], 'lastRoll.die1');
    final die2 = _requiredDie(value['die2'], 'lastRoll.die2');
    final total = _requiredNonNegativeInt(value['total'], 'lastRoll.total');
    if (total != die1 + die2) {
      throw const FormatException('invalidPublicGameSnapshot:lastRoll.total');
    }
    return ConfirmedRollUiState(die1: die1, die2: die2, total: total);
  }

  final int die1;
  final int die2;
  final int total;
}

final class PropertyOfferUiState {
  PropertyOfferUiState({
    required this.propertyId,
    required this.purchasePrice,
    required Iterable<String> allowedPlayerIds,
  }) : allowedPlayerIds = List.unmodifiable(allowedPlayerIds);

  factory PropertyOfferUiState.fromSnapshot(Map<String, Object?> value) {
    final payload = _requiredObject(value['payload'], 'propertyOffer.payload');
    final allowed = _requiredStringList(
      value['allowedPlayerIds'],
      'propertyOffer.allowedPlayerIds',
    );
    return PropertyOfferUiState(
      propertyId: _requiredString(
        payload['propertyId'],
        'propertyOffer.propertyId',
      ),
      purchasePrice: _requiredNonNegativeInt(
        payload['purchasePrice'],
        'propertyOffer.purchasePrice',
      ),
      allowedPlayerIds: allowed,
    );
  }

  final String propertyId;
  final int purchasePrice;
  final List<String> allowedPlayerIds;
}

final class AuctionUiState {
  const AuctionUiState({
    required this.propertyId,
    required this.currentBid,
    required this.currentBidderPlayerId,
  });

  factory AuctionUiState.fromSnapshot(Map<String, Object?> value) =>
      AuctionUiState(
        propertyId: _requiredString(value['propertyId'], 'auction.propertyId'),
        currentBid: _requiredNonNegativeInt(
          value['currentBid'],
          'auction.currentBid',
        ),
        currentBidderPlayerId: _requiredString(
          value['currentBidderPlayerId'],
          'auction.currentBidderPlayerId',
        ),
      );

  final String propertyId;
  final int currentBid;
  final String currentBidderPlayerId;
}

enum BuyAuctionOutcomeKind {
  propertyPurchased,
  auctionWon,
  auctionEndedWithoutWinner,
}

/// A terminal Buy/Auction outcome that Authority durably included in the
/// replacement public snapshot. It is intentionally parsed from the snapshot,
/// never inferred from an acknowledged command.
final class BuyAuctionOutcomeReceipt {
  const BuyAuctionOutcomeReceipt._({
    required this.kind,
    required this.propertyId,
    this.ownerPlayerId,
    this.amount,
  });

  static BuyAuctionOutcomeReceipt? fromLastMutation(
    Object? rawLastMutation, {
    required Object? ownership,
  }) {
    if (rawLastMutation == null) return null;
    final lastMutation = _requiredObject(rawLastMutation, 'lastMutation');
    if (lastMutation['type'] != 'buyAuction') return null;

    final rawOutcome = lastMutation['outcome'];
    if (rawOutcome == null) return null;
    _requiredString(lastMutation['commandId'], 'lastMutation.commandId');
    final outcome = _requiredObject(rawOutcome, 'lastMutation.outcome');
    final type = _requiredString(outcome['type'], 'lastMutation.outcome.type');
    final data = _requiredObject(outcome['data'], 'lastMutation.outcome.data');

    return switch (type) {
      'propertyPurchased' => _propertyPurchased(data, ownership: ownership),
      'auctionWon' => _auctionWon(data, ownership: ownership),
      'auctionEndedWithoutWinner' => _auctionEndedWithoutWinner(
        data,
        ownership: ownership,
      ),
      _ => throw const FormatException(
        'invalidPublicGameSnapshot:lastMutation.outcome.type',
      ),
    };
  }

  static BuyAuctionOutcomeReceipt _propertyPurchased(
    Map<String, Object?> data, {
    required Object? ownership,
  }) {
    final playerId = _requiredString(
      data['playerId'],
      'lastMutation.outcome.data.playerId',
    );
    final propertyId = _requiredString(
      data['propertyId'],
      'lastMutation.outcome.data.propertyId',
    );
    final price = _requiredNonNegativeInt(
      data['price'],
      'lastMutation.outcome.data.price',
    );
    _requireOwnership(
      ownership,
      propertyId: propertyId,
      ownerPlayerId: playerId,
    );
    return BuyAuctionOutcomeReceipt._(
      kind: BuyAuctionOutcomeKind.propertyPurchased,
      propertyId: propertyId,
      ownerPlayerId: playerId,
      amount: price,
    );
  }

  static BuyAuctionOutcomeReceipt _auctionWon(
    Map<String, Object?> data, {
    required Object? ownership,
  }) {
    _requiredString(data['auctionId'], 'lastMutation.outcome.data.auctionId');
    final propertyId = _requiredString(
      data['propertyId'],
      'lastMutation.outcome.data.propertyId',
    );
    final winnerPlayerId = _requiredString(
      data['winnerPlayerId'],
      'lastMutation.outcome.data.winnerPlayerId',
    );
    final winningBid = _requiredPositiveInt(
      data['winningBid'],
      'lastMutation.outcome.data.winningBid',
    );
    _requireOwnership(
      ownership,
      propertyId: propertyId,
      ownerPlayerId: winnerPlayerId,
    );
    return BuyAuctionOutcomeReceipt._(
      kind: BuyAuctionOutcomeKind.auctionWon,
      propertyId: propertyId,
      ownerPlayerId: winnerPlayerId,
      amount: winningBid,
    );
  }

  static BuyAuctionOutcomeReceipt _auctionEndedWithoutWinner(
    Map<String, Object?> data, {
    required Object? ownership,
  }) {
    _requiredString(data['auctionId'], 'lastMutation.outcome.data.auctionId');
    final propertyId = _requiredString(
      data['propertyId'],
      'lastMutation.outcome.data.propertyId',
    );
    final byPropertyId = _optionalOwnershipByPropertyId(ownership);
    if (byPropertyId?.containsKey(propertyId) ?? false) {
      throw const FormatException(
        'invalidPublicGameSnapshot:lastMutation.outcome.ownership',
      );
    }
    return BuyAuctionOutcomeReceipt._(
      kind: BuyAuctionOutcomeKind.auctionEndedWithoutWinner,
      propertyId: propertyId,
    );
  }

  static void _requireOwnership(
    Object? rawOwnership, {
    required String propertyId,
    required String ownerPlayerId,
  }) {
    final ownership = _requiredObject(rawOwnership, 'ownership');
    final byPropertyId = _requiredObject(
      ownership['byPropertyId'],
      'ownership.byPropertyId',
    );
    if (byPropertyId[propertyId] != ownerPlayerId) {
      throw const FormatException(
        'invalidPublicGameSnapshot:lastMutation.outcome.ownership',
      );
    }
  }

  static Map<String, Object?>? _optionalOwnershipByPropertyId(
    Object? rawOwnership,
  ) {
    if (rawOwnership == null) return null;
    final ownership = _requiredObject(rawOwnership, 'ownership');
    final rawByPropertyId = ownership['byPropertyId'];
    if (rawByPropertyId == null) return null;
    return _requiredObject(rawByPropertyId, 'ownership.byPropertyId');
  }

  final BuyAuctionOutcomeKind kind;
  final String propertyId;
  final String? ownerPlayerId;
  final int? amount;

  String get cardKey => switch (kind) {
    BuyAuctionOutcomeKind.propertyPurchased => 'live-confirmed-buy-outcome',
    BuyAuctionOutcomeKind.auctionWon => 'live-confirmed-auction-award',
    BuyAuctionOutcomeKind.auctionEndedWithoutWinner =>
      'live-confirmed-auction-no-winner',
  };

  String get summary => switch (kind) {
    BuyAuctionOutcomeKind.propertyPurchased =>
      'Compra confirmada · $propertyId pertenece a $ownerPlayerId. Pago confirmado: $amount.',
    BuyAuctionOutcomeKind.auctionWon =>
      'Subasta adjudicada · $propertyId pertenece a $ownerPlayerId. Pago confirmado: $amount.',
    BuyAuctionOutcomeKind.auctionEndedWithoutWinner =>
      'Subasta cerrada · $propertyId quedó sin adjudicar.',
  };
}

Map<String, Object?> _requiredObject(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  throw FormatException('invalidPublicGameSnapshot:$field');
}

Map<String, Object?>? _optionalObject(Object? value) {
  if (value == null) return null;
  return _requiredObject(value, 'optionalObject');
}

String _requiredString(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('invalidPublicGameSnapshot:$field');
}

int _requiredNonNegativeInt(Object? value, String field) {
  if (value is int && value >= 0) return value;
  throw FormatException('invalidPublicGameSnapshot:$field');
}

int _requiredPositiveInt(Object? value, String field) {
  if (value is int && value > 0) return value;
  throw FormatException('invalidPublicGameSnapshot:$field');
}

int _requiredDie(Object? value, String field) {
  if (value is int && value >= 1 && value <= 6) return value;
  throw FormatException('invalidPublicGameSnapshot:$field');
}

List<String> _requiredStringList(Object? value, String field) {
  if (value is! List<Object?>) {
    throw FormatException('invalidPublicGameSnapshot:$field');
  }
  final parsed = value.whereType<String>().toList(growable: false);
  if (parsed.length != value.length || parsed.isEmpty) {
    throw FormatException('invalidPublicGameSnapshot:$field');
  }
  return parsed;
}
