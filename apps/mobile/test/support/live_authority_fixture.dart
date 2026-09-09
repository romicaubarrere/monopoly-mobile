import 'dart:async';

import 'package:board_backend_api/backend_api.dart';
import 'package:board_mobile/ui/first_playable/live_first_playable_authority.dart';

// Synthetic, offline fixture preserving the accepted VP0 public protocol.
final class FakeLiveAuthority implements LiveFirstPlayableAuthority {
  FakeLiveAuthority({this.actorPlayerId = 'player-host'});

  final String actorPlayerId;
  final List<FirstPlayableAuthorityAction> actions = [];
  final StreamController<AuthorityPublicRoomSnapshot> _lobbyController =
      StreamController<AuthorityPublicRoomSnapshot>.broadcast();
  final StreamController<AuthorityPublicSnapshot> _gameController =
      StreamController<AuthorityPublicSnapshot>.broadcast();
  Completer<FirstPlayableAuthorityResult>? performCompleter;
  int refreshCalls = 0;
  bool hostReady = false;
  bool gameStarted = false;
  FirstPlayableAuthorityOutcome rollOutcome =
      FirstPlayableAuthorityOutcome.accepted;
  FirstPlayableAuthorityOutcome reconnectOutcome =
      FirstPlayableAuthorityOutcome.accepted;
  Completer<AuthorityPublicRoomSnapshot>? refreshCompleter;
  bool failRefresh = false;
  String? lastInput;
  AuthorityPublicRoomSnapshot? _confirmedLobby;
  AuthorityPublicSnapshot? _confirmedGame;

  @override
  String? get latestCreatedRoomCode => 'ABC123';

  @override
  AuthorityPublicRoomSnapshot? get confirmedLobbySnapshot => _confirmedLobby;

  @override
  AuthorityPublicSnapshot? get confirmedGameSnapshot => _confirmedGame;

  @override
  bool requiresReconciliation = false;

  @override
  Stream<AuthorityPublicRoomSnapshot> get lobbySnapshots =>
      _lobbyController.stream;

  @override
  Stream<AuthorityPublicSnapshot> get gameSnapshots => _gameController.stream;

  @override
  Future<FirstPlayableAuthorityResult> perform(
    FirstPlayableAuthorityAction action, {
    String? input,
  }) async {
    actions.add(action);
    lastInput = input;
    final pending = performCompleter;
    if (pending != null) return pending.future;
    if (action == FirstPlayableAuthorityAction.setReady &&
        actorPlayerId == 'player-host') {
      hostReady = true;
    }
    if (action == FirstPlayableAuthorityAction.startGame) gameStarted = true;
    final outcome = switch (action) {
      FirstPlayableAuthorityAction.roll => rollOutcome,
      FirstPlayableAuthorityAction.reconnect => reconnectOutcome,
      _ => FirstPlayableAuthorityOutcome.accepted,
    };
    if (action == FirstPlayableAuthorityAction.reconnect &&
        outcome != FirstPlayableAuthorityOutcome.uncertain &&
        outcome != FirstPlayableAuthorityOutcome.blocked) {
      requiresReconciliation = false;
    }
    return FirstPlayableAuthorityResult(outcome: outcome);
  }

  @override
  Future<AuthorityPublicRoomSnapshot> refreshLobby() async {
    refreshCalls += 1;
    final pendingRefresh = refreshCompleter;
    if (pendingRefresh != null) return pendingRefresh.future;
    if (failRefresh) throw StateError('snapshot unavailable');
    final snapshot = _lobbySnapshot(gameId: gameStarted ? 'game-live' : null);
    _confirmedLobby = snapshot;
    return snapshot;
  }

  void emitLobby({String? gameId, int? roomVersion}) {
    final snapshot = _lobbySnapshot(gameId: gameId, roomVersion: roomVersion);
    _confirmedLobby = snapshot;
    _lobbyController.add(snapshot);
  }

  void emitGame(AuthorityPublicSnapshot snapshot) {
    _confirmedGame = snapshot;
    _gameController.add(snapshot);
  }

  void emitGameError(Object error) => _gameController.addError(error);

  Future<void> close() async {
    await _lobbyController.close();
    await _gameController.close();
  }

  AuthorityPublicRoomSnapshot _lobbySnapshot({
    String? gameId,
    int? roomVersion,
  }) => AuthorityPublicRoomSnapshot(<String, Object?>{
    'schemaVersion': 1,
    'roomId': 'room-live',
    'roomVersion':
        roomVersion ??
        (gameId != null
            ? 4
            : hostReady
            ? 3
            : 2),
    'status': gameId == null ? 'open' : 'active',
    'hostPlayerId': 'player-host',
    'actorPlayerId': actorPlayerId,
    'presetId': 'express',
    'rulesVersion': 'synthetic-rules-vp0',
    'gameId': ?gameId,
    'members': <Object?>[
      <String, Object?>{
        'playerId': 'player-host',
        'kind': 'human',
        'ready': hostReady || gameId != null,
      },
      const <String, Object?>{
        'playerId': 'player-guest',
        'kind': 'human',
        'ready': true,
      },
    ],
  });
}

AuthorityPublicSnapshot gameSnapshot({
  required int version,
  required String phase,
  required String currentPlayerId,
  bool propertyOffer = false,
  bool auction = false,
  List<int>? lastRoll,
  Map<String, Object?>? lastMutation,
  Map<String, Object?>? ownership,
}) => AuthorityPublicSnapshot(<String, Object?>{
  'schemaVersion': 1,
  'stateVersion': version,
  'gameId': 'game-live',
  'roomId': 'room-live',
  'status': 'active',
  'rulesVersion': 'synthetic-rules-vp0',
  'presetConfig': const <String, Object?>{'presetId': 'express'},
  'turnState': <String, Object?>{
    'phase': phase,
    'currentPlayerId': currentPlayerId,
    if (lastRoll != null)
      'lastRoll': <String, Object?>{
        'die1': lastRoll[0],
        'die2': lastRoll[1],
        'total': lastRoll[0] + lastRoll[1],
      },
  },
  if (propertyOffer)
    'pendingDecision': const <String, Object?>{
      'decisionId': 'decision-live',
      'kind': 'propertyOffer',
      'payload': <String, Object?>{
        'propertyId': 'property-placeholder',
        'purchasePrice': 100,
      },
      'allowedPlayerIds': <Object?>['player-host'],
    },
  if (auction)
    'activeAuction': const <String, Object?>{
      'auctionId': 'auction-live',
      'propertyId': 'property-placeholder',
      'currentBid': 10,
      'currentBidderPlayerId': 'player-host',
    },
  'lastMutation': ?lastMutation,
  'ownership': ?ownership,
});
