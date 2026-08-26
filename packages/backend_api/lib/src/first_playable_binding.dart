import 'client_authority.dart';
import 'client_authority_session.dart';
import 'first_playable_commands.dart';

/// Presentation intents that cross the Flutter/Authority boundary.
///
/// Navigation-only actions are intentionally absent. Implementations may only
/// return accepted after an Authority ACK or durable reconnect result.
enum FirstPlayableAuthorityAction {
  createRoom,
  joinRoom,
  setReady,
  startGame,
  roll,
  buyProperty,
  declineProperty,
  placeBid,
  passAuction,
  reconnect,
}

enum FirstPlayableAuthorityOutcome { accepted, rejected, uncertain, blocked }

final class FirstPlayableAuthorityResult {
  const FirstPlayableAuthorityResult({
    required this.outcome,
    this.safeErrorCode,
  });

  final FirstPlayableAuthorityOutcome outcome;
  final String? safeErrorCode;

  bool get accepted => outcome == FirstPlayableAuthorityOutcome.accepted;
}

/// Port consumed by the Direction B shell.
abstract interface class FirstPlayableAuthorityBinding {
  Future<FirstPlayableAuthorityResult> perform(
    FirstPlayableAuthorityAction action, {
    String? input,
  });
}

/// Confirmed identifiers and versions required to construct the next command.
///
/// A Flutter repository updates this source only from accepted room results or
/// replacement public snapshots. It cannot provide Engine services or private
/// state, and this boundary never computes the values itself.
abstract interface class FirstPlayableConfirmedContext {
  String get roomId;
  int get roomVersion;
  String get gameId;
  int get stateVersion;
  String get actorPlayerId;
  String get propertyDecisionId;
  String get propertyId;
  String get auctionId;

  /// Applies only an ACK/duplicate result already validated by the session.
  void applyCommandReply(
    AuthorityCommandRequest request,
    AuthorityCommandReply reply,
  );

  /// Replaces confirmed game context from Authority's public snapshot.
  void replacePublicSnapshot(AuthorityPublicSnapshot snapshot);
}

/// Resolves a UI intent to one canonical request using confirmed context only.
final class ConfirmedFirstPlayableRequestResolver {
  ConfirmedFirstPlayableRequestResolver({
    required FirstPlayableAuthorityCommands commands,
    required FirstPlayableConfirmedContext context,
    required Map<String, Object?> createRoomPresetDraft,
  }) : this._(
         commands,
         context,
         Map<String, Object?>.unmodifiable(createRoomPresetDraft),
       );

  ConfirmedFirstPlayableRequestResolver._(
    this._commands,
    this._context,
    this._createRoomPresetDraft,
  );

  final FirstPlayableAuthorityCommands _commands;
  final FirstPlayableConfirmedContext _context;
  final Map<String, Object?> _createRoomPresetDraft;

  String get reconnectGameId => _context.gameId;

  AuthorityCommandRequest commandFor(
    FirstPlayableAuthorityAction action, {
    String? input,
  }) => switch (action) {
    FirstPlayableAuthorityAction.createRoom => _commands.createRoom(
      presetDraft: _createRoomPresetDraft,
    ),
    FirstPlayableAuthorityAction.joinRoom => _commands.joinRoom(
      roomCode: input ?? '',
    ),
    FirstPlayableAuthorityAction.setReady => _commands.setReady(
      roomId: _context.roomId,
      expectedRoomVersion: _context.roomVersion,
      ready: true,
    ),
    FirstPlayableAuthorityAction.startGame => _commands.startGame(
      roomId: _context.roomId,
      expectedRoomVersion: _context.roomVersion,
    ),
    FirstPlayableAuthorityAction.roll => _commands.rollDice(
      gameId: _context.gameId,
      expectedStateVersion: _context.stateVersion,
      actorPlayerId: _context.actorPlayerId,
    ),
    FirstPlayableAuthorityAction.buyProperty => _commands.buyProperty(
      gameId: _context.gameId,
      expectedStateVersion: _context.stateVersion,
      actorPlayerId: _context.actorPlayerId,
      decisionId: _context.propertyDecisionId,
      propertyId: _context.propertyId,
    ),
    FirstPlayableAuthorityAction.declineProperty => _commands.declineProperty(
      gameId: _context.gameId,
      expectedStateVersion: _context.stateVersion,
      actorPlayerId: _context.actorPlayerId,
      decisionId: _context.propertyDecisionId,
      propertyId: _context.propertyId,
    ),
    FirstPlayableAuthorityAction.placeBid => _commands.placeBid(
      gameId: _context.gameId,
      expectedStateVersion: _context.stateVersion,
      actorPlayerId: _context.actorPlayerId,
      auctionId: _context.auctionId,
      amount: int.tryParse(input ?? '') ?? 0,
    ),
    FirstPlayableAuthorityAction.passAuction => _commands.passAuction(
      gameId: _context.gameId,
      expectedStateVersion: _context.stateVersion,
      actorPlayerId: _context.actorPlayerId,
      auctionId: _context.auctionId,
    ),
    FirstPlayableAuthorityAction.reconnect =>
      throw const ClientAuthorityContractViolation('reconnectIsNotACommand'),
  };

  void applyCommandReply(
    AuthorityCommandRequest request,
    AuthorityCommandReply reply,
  ) => _context.applyCommandReply(request, reply);

  void replacePublicSnapshot(AuthorityPublicSnapshot snapshot) =>
      _context.replacePublicSnapshot(snapshot);
}

/// Concrete adapter between Direction B actions and the accepted session port.
///
/// It does not update presentation on send. The result is accepted only after
/// the session has an ACK, duplicate durable result, or successful reconnect.
final class SessionFirstPlayableAuthorityBinding
    implements FirstPlayableAuthorityBinding {
  SessionFirstPlayableAuthorityBinding({
    required AuthorityClientSession session,
    required ConfirmedFirstPlayableRequestResolver requests,
  }) : this._(session, requests);

  SessionFirstPlayableAuthorityBinding._(this._session, this._requests);

  final AuthorityClientSession _session;
  final ConfirmedFirstPlayableRequestResolver _requests;

  @override
  Future<FirstPlayableAuthorityResult> perform(
    FirstPlayableAuthorityAction action, {
    String? input,
  }) async {
    if (action == FirstPlayableAuthorityAction.reconnect) {
      final reply = await _session.reconnect(_requests.reconnectGameId);
      if (reply != null) {
        _requests.replacePublicSnapshot(reply.snapshot);
      }
      if (reply?.disposition == ReconnectDisposition.uncertainRejected) {
        return const FirstPlayableAuthorityResult(
          outcome: FirstPlayableAuthorityOutcome.rejected,
          safeErrorCode: 'durableCommandRejected',
        );
      }
      return _fromSession();
    }

    try {
      final request = _requests.commandFor(action, input: input);
      final reply = await _session.send(request);
      if (reply?.status == AuthorityCommandStatus.rejected) {
        return FirstPlayableAuthorityResult(
          outcome: FirstPlayableAuthorityOutcome.rejected,
          safeErrorCode: reply!.errorCode,
        );
      }
      if (reply != null) _requests.applyCommandReply(request, reply);
      return _fromSession();
    } on ClientAuthorityContractViolation catch (error) {
      return FirstPlayableAuthorityResult(
        outcome: FirstPlayableAuthorityOutcome.blocked,
        safeErrorCode: error.code,
      );
    }
  }

  FirstPlayableAuthorityResult _fromSession() =>
      switch (_session.state.status) {
        AuthoritySessionStatus.confirmed => const FirstPlayableAuthorityResult(
          outcome: FirstPlayableAuthorityOutcome.accepted,
        ),
        AuthoritySessionStatus.rejected => FirstPlayableAuthorityResult(
          outcome: FirstPlayableAuthorityOutcome.rejected,
          safeErrorCode: _session.state.safeErrorCode,
        ),
        AuthoritySessionStatus.blocked => FirstPlayableAuthorityResult(
          outcome: FirstPlayableAuthorityOutcome.blocked,
          safeErrorCode: _session.state.safeErrorCode,
        ),
        AuthoritySessionStatus.idle ||
        AuthoritySessionStatus.sending ||
        AuthoritySessionStatus.uncertain ||
        AuthoritySessionStatus.reconnecting => FirstPlayableAuthorityResult(
          outcome: FirstPlayableAuthorityOutcome.uncertain,
          safeErrorCode: _session.state.safeErrorCode,
        ),
      };
}
