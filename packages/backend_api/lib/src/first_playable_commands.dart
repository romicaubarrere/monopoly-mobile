import 'package:board_game_contracts/game_contracts.dart';
import 'package:board_game_core/game_core.dart';

import 'client_authority.dart';

/// Supplies a fresh durable identity for a new user intent.
///
/// The application composition root owns the implementation. This package
/// deliberately provides no clock/random fallback: retries must reuse the
/// already persisted [AuthorityCommandRequest] instead of minting a new ID.
abstract interface class AuthorityCommandIdSource {
  String nextCommandId();
}

/// Constructs the canonical Authority requests used by the First Playable.
///
/// All version and target values are caller-supplied from the last confirmed
/// room result or public game snapshot. This class selects a canonical command
/// type and payload only; it never evaluates legality, movement, money,
/// ownership, auction order, RNG, or deadlines.
final class FirstPlayableAuthorityCommands {
  FirstPlayableAuthorityCommands({
    required String clientInstanceId,
    required AuthorityCommandIdSource commandIds,
  }) : this._(
         _identifier(clientInstanceId, 'invalidClientInstanceId'),
         commandIds,
       );

  FirstPlayableAuthorityCommands._(this._clientInstanceId, this._commandIds);

  final String _clientInstanceId;
  final AuthorityCommandIdSource _commandIds;

  AuthorityCommandRequest createRoom({
    required Map<String, Object?> presetDraft,
  }) => _room(
    type: RoomCommandType.createRoom,
    payload: <String, Object?>{'presetDraft': presetDraft},
  );

  AuthorityCommandRequest joinRoom({required String roomCode}) => _room(
    type: RoomCommandType.joinRoom,
    payload: <String, Object?>{'roomCode': roomCode},
  );

  AuthorityCommandRequest setReady({
    required String roomId,
    required int expectedRoomVersion,
    required bool ready,
  }) => _room(
    type: RoomCommandType.setReady,
    expectedRoomVersion: expectedRoomVersion,
    payload: <String, Object?>{'roomId': roomId, 'ready': ready},
  );

  AuthorityCommandRequest startGame({
    required String roomId,
    required int expectedRoomVersion,
  }) => _room(
    type: RoomCommandType.startGame,
    expectedRoomVersion: expectedRoomVersion,
    payload: <String, Object?>{'roomId': roomId},
  );

  AuthorityCommandRequest rollDice({
    required String gameId,
    required int expectedStateVersion,
    required String actorPlayerId,
  }) => _game(
    type: GameCommandType.rollDice,
    gameId: gameId,
    expectedStateVersion: expectedStateVersion,
    actorPlayerId: actorPlayerId,
    payload: const <String, Object?>{},
  );

  AuthorityCommandRequest buyProperty({
    required String gameId,
    required int expectedStateVersion,
    required String actorPlayerId,
    required String decisionId,
    required String propertyId,
  }) => _propertyDecision(
    type: GameCommandType.buyProperty,
    gameId: gameId,
    expectedStateVersion: expectedStateVersion,
    actorPlayerId: actorPlayerId,
    decisionId: decisionId,
    propertyId: propertyId,
  );

  AuthorityCommandRequest declineProperty({
    required String gameId,
    required int expectedStateVersion,
    required String actorPlayerId,
    required String decisionId,
    required String propertyId,
  }) => _propertyDecision(
    type: GameCommandType.declineProperty,
    gameId: gameId,
    expectedStateVersion: expectedStateVersion,
    actorPlayerId: actorPlayerId,
    decisionId: decisionId,
    propertyId: propertyId,
  );

  AuthorityCommandRequest placeBid({
    required String gameId,
    required int expectedStateVersion,
    required String actorPlayerId,
    required String auctionId,
    required int amount,
  }) {
    if (amount <= 0) {
      throw const ClientAuthorityContractViolation('invalidBidAmount');
    }
    return _auction(
      type: GameCommandType.placeBid,
      gameId: gameId,
      expectedStateVersion: expectedStateVersion,
      actorPlayerId: actorPlayerId,
      auctionId: auctionId,
      extraPayload: <String, Object?>{'amount': amount},
    );
  }

  AuthorityCommandRequest passAuction({
    required String gameId,
    required int expectedStateVersion,
    required String actorPlayerId,
    required String auctionId,
  }) => _auction(
    type: GameCommandType.passAuction,
    gameId: gameId,
    expectedStateVersion: expectedStateVersion,
    actorPlayerId: actorPlayerId,
    auctionId: auctionId,
  );

  AuthorityCommandRequest _propertyDecision({
    required GameCommandType type,
    required String gameId,
    required int expectedStateVersion,
    required String actorPlayerId,
    required String decisionId,
    required String propertyId,
  }) => _game(
    type: type,
    gameId: gameId,
    expectedStateVersion: expectedStateVersion,
    actorPlayerId: actorPlayerId,
    payload: <String, Object?>{
      'decisionId': _identifier(decisionId, 'invalidDecisionId'),
      'propertyId': _identifier(propertyId, 'invalidPropertyId'),
    },
  );

  AuthorityCommandRequest _auction({
    required GameCommandType type,
    required String gameId,
    required int expectedStateVersion,
    required String actorPlayerId,
    required String auctionId,
    Map<String, Object?> extraPayload = const <String, Object?>{},
  }) => _game(
    type: type,
    gameId: gameId,
    expectedStateVersion: expectedStateVersion,
    actorPlayerId: actorPlayerId,
    payload: <String, Object?>{
      'auctionId': _identifier(auctionId, 'invalidAuctionId'),
      ...extraPayload,
    },
  );

  AuthorityCommandRequest _room({
    required RoomCommandType type,
    required Map<String, Object?> payload,
    int? expectedRoomVersion,
  }) => AuthorityCommandRequest.room(
    RoomCommand(
      commandId: _nextId(),
      schemaVersion: 1,
      expectedRoomVersion: expectedRoomVersion,
      clientInstanceId: _clientInstanceId,
      type: type,
      payload: payload,
    ),
  );

  AuthorityCommandRequest _game({
    required GameCommandType type,
    required String gameId,
    required int expectedStateVersion,
    required String actorPlayerId,
    required Map<String, Object?> payload,
  }) => AuthorityCommandRequest.game(
    GameCommand(
      commandId: _nextId(),
      schemaVersion: 1,
      expectedStateVersion: expectedStateVersion,
      clientInstanceId: _clientInstanceId,
      gameId: _identifier(gameId, 'invalidGameId'),
      actorPlayerId: _identifier(actorPlayerId, 'invalidActorPlayerId'),
      type: type,
      payload: payload,
    ),
  );

  String _nextId() =>
      _identifier(_commandIds.nextCommandId(), 'invalidGeneratedCommandId');
}

String _identifier(String value, String code) {
  if (value.isEmpty) throw ClientAuthorityContractViolation(code);
  return value;
}
