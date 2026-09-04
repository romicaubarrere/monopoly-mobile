import 'package:board_game_contracts/game_contracts.dart';

import 'client_authority.dart';
import 'first_playable_binding.dart';

/// Confirmed identifiers consumed by the First Playable command resolver.
///
/// Room values come only from an accepted Authority result. Game values and
/// decision identifiers come only from a public replacement snapshot (or the
/// accepted StartGame summary for the initial game version). This repository
/// does not infer turn legality, prices, ownership, movement, or auction rules.
final class FirstPlayableAuthorityContext
    implements FirstPlayableConfirmedContext {
  FirstPlayableAuthorityContext();

  String? _actorPlayerId;
  String? _roomId;
  int? _roomVersion;
  String? _gameId;
  int? _stateVersion;
  String? _snapshotCanonicalJson;
  String? _roomSnapshotCanonicalJson;
  String? _propertyDecisionId;
  String? _propertyId;
  String? _auctionId;

  /// Establishes actor membership only from an authenticated public room read.
  ///
  /// Device persistence never supplies actor identity. The snapshot wrapper has
  /// already rejected private material and inconsistent public membership.
  void restorePublicRoomSnapshot(AuthorityPublicRoomSnapshot snapshot) {
    if (_actorPlayerId == null) {
      final actor = _identifier(snapshot.snapshot['actorPlayerId']);
      final members = snapshot.snapshot['members']! as List<Object?>;
      if (actor == null ||
          !members.whereType<Map<String, Object?>>().any(
            (member) => member['playerId'] == actor,
          )) {
        throw const ClientAuthorityContractViolation(
          'roomSnapshotActorMissing',
        );
      }
      _actorPlayerId = actor;
    }
    replacePublicRoomSnapshot(snapshot);
  }

  @override
  String get actorPlayerId =>
      _requiredIdentifier(_actorPlayerId, 'confirmedActorUnavailable');

  @override
  String get roomId => _requiredIdentifier(_roomId, 'confirmedRoomUnavailable');

  @override
  int get roomVersion =>
      _requiredVersion(_roomVersion, 'confirmedRoomUnavailable');

  @override
  String get gameId => _requiredIdentifier(_gameId, 'confirmedGameUnavailable');

  @override
  int get stateVersion =>
      _requiredVersion(_stateVersion, 'confirmedGameSnapshotRequired');

  @override
  String get propertyDecisionId => _requiredIdentifier(
    _propertyDecisionId,
    'confirmedPropertyDecisionUnavailable',
  );

  @override
  String get propertyId =>
      _requiredIdentifier(_propertyId, 'confirmedPropertyDecisionUnavailable');

  @override
  String get auctionId =>
      _requiredIdentifier(_auctionId, 'confirmedAuctionUnavailable');

  @override
  void applyCommandReply(
    AuthorityCommandRequest request,
    AuthorityCommandReply reply,
  ) {
    if (request.commandId != reply.commandId) {
      throw const ClientAuthorityContractViolation('replyCommandMismatch');
    }
    if (reply.isRejectedOutcome) return;

    switch (request.family) {
      case AuthorityCommandFamily.room:
        _applyRoomReply(request, reply);
      case AuthorityCommandFamily.game:
        _applyGameReply(request, reply);
    }
  }

  @override
  void replacePublicSnapshot(AuthorityPublicSnapshot snapshot) {
    final value = snapshot.snapshot;
    final canonicalJson = snapshot.toCanonicalJson();
    final nextGameId = _identifier(value['gameId']);
    final nextRoomId = _identifier(value['roomId']);
    if (nextGameId == null) {
      throw const ClientAuthorityContractViolation('invalidSnapshotGameId');
    }
    if (nextRoomId == null) {
      throw const ClientAuthorityContractViolation('invalidSnapshotRoomId');
    }
    if (_gameId != null && _gameId != nextGameId) {
      throw const ClientAuthorityContractViolation('snapshotGameMismatch');
    }
    if (_roomId != null && _roomId != nextRoomId) {
      throw const ClientAuthorityContractViolation('snapshotRoomMismatch');
    }
    if (_stateVersion != null && snapshot.stateVersion < _stateVersion!) {
      return;
    }
    if (_stateVersion == snapshot.stateVersion &&
        _snapshotCanonicalJson != null &&
        _snapshotCanonicalJson != canonicalJson) {
      throw const ClientAuthorityContractViolation('snapshotVersionCollision');
    }

    String? nextPropertyDecisionId;
    String? nextPropertyId;
    String? nextAuctionId;

    final pending = _object(value['pendingDecision']);
    if (pending?['kind'] == 'propertyOffer') {
      final payload = _object(pending?['payload']);
      nextPropertyDecisionId = _identifier(pending?['decisionId']);
      nextPropertyId = _identifier(payload?['propertyId']);
      if (nextPropertyDecisionId == null || nextPropertyId == null) {
        throw const ClientAuthorityContractViolation(
          'invalidPropertyDecisionSnapshot',
        );
      }
    }

    final auction = _object(value['activeAuction']);
    if (auction != null) {
      nextAuctionId = _identifier(auction['auctionId']);
      if (nextAuctionId == null) {
        throw const ClientAuthorityContractViolation('invalidAuctionSnapshot');
      }
    }

    _gameId = nextGameId;
    _roomId = nextRoomId;
    _stateVersion = snapshot.stateVersion;
    _snapshotCanonicalJson = canonicalJson;
    _propertyDecisionId = nextPropertyDecisionId;
    _propertyId = nextPropertyId;
    _auctionId = nextAuctionId;
  }

  @override
  void replacePublicRoomSnapshot(AuthorityPublicRoomSnapshot snapshot) {
    final value = snapshot.snapshot;
    final nextRoomId = snapshot.roomId;
    if (_roomId != null && _roomId != nextRoomId) {
      throw const ClientAuthorityContractViolation('roomSnapshotMismatch');
    }
    if (_roomVersion != null && snapshot.roomVersion < _roomVersion!) return;
    final canonicalJson = snapshot.toCanonicalJson();
    if (_roomVersion == snapshot.roomVersion &&
        _roomSnapshotCanonicalJson != null &&
        _roomSnapshotCanonicalJson != canonicalJson) {
      throw const ClientAuthorityContractViolation(
        'roomSnapshotVersionCollision',
      );
    }
    final members = value['members']! as List<Object?>;
    final actor = _actorPlayerId;
    if (actor == null || value['actorPlayerId'] != actor) {
      throw const ClientAuthorityContractViolation('roomSnapshotActorMismatch');
    }
    if (!members.whereType<Map<String, Object?>>().any(
      (member) => member['playerId'] == actor,
    )) {
      throw const ClientAuthorityContractViolation('roomSnapshotActorMissing');
    }
    final nextGameId = snapshot.gameId;
    if (nextGameId != null && _gameId != null && _gameId != nextGameId) {
      throw const ClientAuthorityContractViolation('roomSnapshotGameMismatch');
    }
    _roomId = nextRoomId;
    _roomVersion = snapshot.roomVersion;
    _roomSnapshotCanonicalJson = canonicalJson;
    if (nextGameId != null) {
      _gameId = nextGameId;
    }
  }

  void _applyRoomReply(
    AuthorityCommandRequest request,
    AuthorityCommandReply reply,
  ) {
    final commandType = request.asRoomCommand.type;
    final result = reply.publicResult;
    final roomSnapshot = _object(result['roomSnapshot']);
    final requestedRoomId = _identifier(
      (request.command['payload'] as Map<String, Object?>)['roomId'],
    );
    final nextRoomId =
        _identifier(roomSnapshot?['roomId']) ??
        _identifier(result['roomId']) ??
        requestedRoomId;
    final nextRoomVersion =
        _version(roomSnapshot?['roomVersion']) ??
        _version(result['roomVersion']) ??
        reply.versionAfter;
    if (nextRoomId == null || nextRoomVersion != reply.versionAfter) {
      throw const ClientAuthorityContractViolation('invalidRoomReplyContext');
    }
    final replyActorPlayerId =
        _identifier(result['actorPlayerId']) ??
        _identifier(roomSnapshot?['actorPlayerId']);
    final establishesMembership =
        commandType == RoomCommandType.createRoom ||
        commandType == RoomCommandType.joinRoom;
    if (establishesMembership && replyActorPlayerId == null) {
      throw const ClientAuthorityContractViolation(
        'missingAuthorityActorPlayerId',
      );
    }
    if (_actorPlayerId != null &&
        replyActorPlayerId != null &&
        _actorPlayerId != replyActorPlayerId) {
      throw const ClientAuthorityContractViolation('actorPlayerIdMismatch');
    }
    if (_roomId == nextRoomId &&
        _roomVersion != null &&
        nextRoomVersion < _roomVersion!) {
      return;
    }

    final advancesConfirmedRoomVersion = _roomVersion != nextRoomVersion;
    _actorPlayerId ??= replyActorPlayerId;
    _roomId = nextRoomId;
    _roomVersion = nextRoomVersion;
    if (advancesConfirmedRoomVersion) {
      // A command receipt can advance routing context without carrying a full
      // public room snapshot. Its canonical bytes must not be compared with
      // the later authoritative snapshot at this new room version.
      _roomSnapshotCanonicalJson = null;
    }
    final nextGameId =
        _identifier(result['gameId']) ?? _identifier(roomSnapshot?['gameId']);
    if (nextGameId != null) {
      _gameId = nextGameId;
      final initialStateVersion = _version(result['stateVersion']);
      if (initialStateVersion != null) _stateVersion = initialStateVersion;
    }
    if (reply.snapshot != null) replacePublicSnapshot(reply.snapshot!);
  }

  void _applyGameReply(
    AuthorityCommandRequest request,
    AuthorityCommandReply reply,
  ) {
    final commandGameId = _identifier(request.command['gameId']);
    if (commandGameId == null || _gameId != null && _gameId != commandGameId) {
      throw const ClientAuthorityContractViolation('replyGameMismatch');
    }
    final resultVersion = _version(reply.publicResult['stateVersionAfter']);
    if (resultVersion != null && resultVersion != reply.versionAfter) {
      throw const ClientAuthorityContractViolation('invalidGameReplyContext');
    }
    _gameId = commandGameId;
    _stateVersion = resultVersion ?? reply.versionAfter;
    _snapshotCanonicalJson = null;
    _propertyDecisionId = null;
    _propertyId = null;
    _auctionId = null;
    if (reply.snapshot != null) replacePublicSnapshot(reply.snapshot!);
  }
}

Map<String, Object?>? _object(Object? value) =>
    value is Map<String, Object?> ? value : null;

String? _identifier(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int? _version(Object? value) => value is int && value >= 0 ? value : null;

String _requiredIdentifier(Object? value, String code) {
  final identifier = _identifier(value);
  if (identifier == null) throw ClientAuthorityContractViolation(code);
  return identifier;
}

int _requiredVersion(Object? value, String code) {
  final version = _version(value);
  if (version == null) throw ClientAuthorityContractViolation(code);
  return version;
}
