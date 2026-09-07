import 'dart:async';

import 'package:board_backend_api/backend_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'live_first_playable_authority.dart';
import 'live_first_playable_ui_state.dart';

/// Composition boundary: production injects the existing repository adapter;
/// provider/widget tests override it without Firebase or transport initialization.
final liveFirstPlayableAuthorityProvider = Provider<LiveFirstPlayableAuthority>(
  (ref) => throw StateError('liveAuthorityOverrideRequired'),
);

final liveFirstPlayableViewModelProvider =
    NotifierProvider<LiveFirstPlayableViewModel, LiveFirstPlayableUiState>(
      LiveFirstPlayableViewModel.new,
      isAutoDispose: true,
      dependencies: [liveFirstPlayableAuthorityProvider],
    );

/// Derives immutable presentation state from confirmed repository snapshots.
/// Commands/retry identity, membership and gameplay remain in the existing
/// repository/Authority boundary. No ACK fabricates a gameplay snapshot.
final class LiveFirstPlayableViewModel
    extends Notifier<LiveFirstPlayableUiState> {
  late LiveFirstPlayableAuthority _authority;
  FirstPlayableStep _step = FirstPlayableStep.home;
  LobbyUiState? _lobby;
  BoardUiState? _game;
  String? _roomCode;
  String? _safeError;
  SnapshotErrorSource? _snapshotErrorSource;
  bool _snapshotErrorRecoverable = false;
  bool _busy = false;
  bool _reconnectRequired = false;
  AuthorityPublicSnapshot? _pendingGameSnapshot;
  AuthorityPublicRoomSnapshot? _confirmedLobbySnapshot;
  AuthorityPublicSnapshot? _confirmedGameSnapshot;
  StreamSubscription<AuthorityPublicRoomSnapshot>? _lobbySubscription;
  StreamSubscription<AuthorityPublicSnapshot>? _gameSubscription;
  int _authorityGeneration = 0;
  bool _active = false;
  bool _initializing = false;

  @override
  LiveFirstPlayableUiState build() {
    _authority = ref.watch(liveFirstPlayableAuthorityProvider);
    _authorityGeneration += 1;
    _active = true;
    _initializing = true;
    _step = FirstPlayableStep.home;
    _lobby = null;
    _game = null;
    _roomCode = null;
    _safeError = null;
    _snapshotErrorSource = null;
    _snapshotErrorRecoverable = false;
    _busy = false;
    _reconnectRequired = false;
    _pendingGameSnapshot = null;
    _confirmedLobbySnapshot = null;
    _confirmedGameSnapshot = null;
    ref.onDispose(() {
      _active = false;
      _authorityGeneration += 1;
      _lobbySubscription?.cancel();
      _gameSubscription?.cancel();
    });
    _listenToAuthority();
    _initializing = false;
    return _uiState;
  }

  LiveFirstPlayableUiState get _uiState => LiveFirstPlayableUiState(
    step: _step,
    lobby: _lobby,
    game: _game,
    roomCode: _roomCode,
    safeError: _safeError,
    snapshotErrorSource: _snapshotErrorSource,
    snapshotErrorRecoverable: _snapshotErrorRecoverable,
    busy: _busy,
    reconnectRequired: _reconnectRequired,
    confirmedLobbySnapshot: _confirmedLobbySnapshot,
    confirmedGameSnapshot: _confirmedGameSnapshot,
  );

  void _change(void Function() update) {
    if (!_active) return;
    update();
    if (!_initializing) state = _uiState;
  }

  void showEntry(FirstPlayableStep step) {
    if (_busy || _reconnectRequired) return;
    _change(() => _step = step);
  }

  /// Rebuild only from the repository's confirmed data on foreground. This
  /// does not replay an uncertain command or synthesize a new command identity.
  void restoreConfirmedPresentation() {
    if (!_active) return;
    final lobby = _authority.confirmedLobbySnapshot;
    if (lobby != null) _acceptLobbySnapshot(lobby);
    final game = _authority.confirmedGameSnapshot;
    if (game != null) _acceptGameSnapshot(game);
    _change(() => _reconnectRequired = _authority.requiresReconciliation);
  }

  void _listenToAuthority() {
    final generation = _authorityGeneration;
    final authority = _authority;
    _lobbySubscription = authority.lobbySnapshots.listen(
      (snapshot) {
        if (generation == _authorityGeneration) _acceptLobbySnapshot(snapshot);
      },
      onError: (Object error, StackTrace _) {
        if (generation == _authorityGeneration) {
          _setSnapshotError(
            _safeSnapshotErrorCode(error, 'roomSnapshotUnavailable'),
            SnapshotErrorSource.room,
            recoverable: error is! ClientAuthorityContractViolation,
          );
        }
      },
      onDone: () {
        if (generation == _authorityGeneration) {
          _setSnapshotError(
            'roomSnapshotStreamEnded',
            SnapshotErrorSource.room,
            recoverable: true,
          );
        }
      },
    );
    _gameSubscription = authority.gameSnapshots.listen(
      (snapshot) {
        if (generation == _authorityGeneration) _acceptGameSnapshot(snapshot);
      },
      onError: (Object error, StackTrace _) {
        if (generation == _authorityGeneration) {
          _setSnapshotError(
            _safeSnapshotErrorCode(error, 'gameSnapshotUnavailable'),
            SnapshotErrorSource.game,
            recoverable: error is! ClientAuthorityContractViolation,
          );
        }
      },
      onDone: () {
        if (generation == _authorityGeneration) {
          _setSnapshotError(
            'gameSnapshotStreamEnded',
            SnapshotErrorSource.game,
            recoverable: true,
          );
        }
      },
    );
    final lobby = authority.confirmedLobbySnapshot;
    if (lobby != null) _acceptLobbySnapshot(lobby);
    final game = authority.confirmedGameSnapshot;
    if (game != null) _acceptGameSnapshot(game);
    if (authority.requiresReconciliation) _reconnectRequired = true;
  }

  void _acceptLobbySnapshot(AuthorityPublicRoomSnapshot snapshot) {
    try {
      final lobby = LobbyUiState.fromSnapshot(snapshot);
      final currentLobby = _lobby;
      if (currentLobby != null &&
          lobby.roomVersion < currentLobby.roomVersion) {
        return;
      }
      if (!_active) return;
      _change(() {
        _lobby = lobby;
        _confirmedLobbySnapshot = snapshot;
        if (_snapshotErrorSource != SnapshotErrorSource.game) {
          _safeError = null;
          _snapshotErrorSource = null;
          _snapshotErrorRecoverable = false;
        }
        if (_game == null) _step = FirstPlayableStep.lobby;
      });
      final pendingGame = _pendingGameSnapshot;
      if (pendingGame != null) {
        _pendingGameSnapshot = null;
        _acceptGameSnapshot(pendingGame);
      }
    } on Object {
      _setSafeError('invalidPublicLobbySnapshot');
    }
  }

  void _acceptGameSnapshot(AuthorityPublicSnapshot snapshot) {
    try {
      final lobby = _lobby;
      if (lobby == null || lobby.gameId == null) {
        final pending = _pendingGameSnapshot;
        if (pending == null || snapshot.stateVersion >= pending.stateVersion) {
          _pendingGameSnapshot = snapshot;
        }
        return;
      }
      if (snapshot.gameId != lobby.gameId) {
        _setSafeError('gameSnapshotRoomMismatch');
        return;
      }
      final actorPlayerId = lobby.actorPlayerId;
      final game = BoardUiState.fromSnapshot(
        snapshot,
        actorPlayerId: actorPlayerId,
      );
      final currentGame = _game;
      if (currentGame != null && game.stateVersion < currentGame.stateVersion) {
        return;
      }
      if (!_active) return;
      _change(() {
        _game = game;
        _confirmedGameSnapshot = snapshot;
        _reconnectRequired = _authority.requiresReconciliation;
        if (_snapshotErrorSource != SnapshotErrorSource.room) {
          _safeError = null;
          _snapshotErrorSource = null;
          _snapshotErrorRecoverable = false;
        }
      });
    } on Object {
      _setSafeError('invalidPublicGameSnapshot');
    }
  }

  void _setSafeError(String value) {
    if (_active) {
      _change(() {
        _safeError = value;
        _snapshotErrorSource = null;
        _snapshotErrorRecoverable = false;
      });
    }
  }

  void _setSnapshotError(
    String value,
    SnapshotErrorSource source, {
    required bool recoverable,
  }) {
    if (_active) {
      _change(() {
        _safeError = value;
        _snapshotErrorSource = source;
        _snapshotErrorRecoverable = recoverable;
      });
    }
  }

  String _safeSnapshotErrorCode(Object error, String fallback) =>
      switch (error) {
        ClientAuthorityContractViolation(:final code) => code,
        AuthorityTransportException(:final code) => code,
        _ => fallback,
      };

  Future<FirstPlayableAuthorityResult?> _perform(
    FirstPlayableAuthorityAction action, {
    String? input,
  }) async {
    if (!_active || _busy) return null;
    final generation = _authorityGeneration;
    final authority = _authority;
    _change(() {
      _busy = true;
      if (_snapshotErrorSource == null) _safeError = null;
    });
    try {
      final result = await authority.perform(action, input: input);
      if (!_active || generation != _authorityGeneration) return null;
      if (result.outcome == FirstPlayableAuthorityOutcome.uncertain ||
          authority.requiresReconciliation) {
        _change(() => _reconnectRequired = true);
      } else if (result.accepted &&
          action != FirstPlayableAuthorityAction.reconnect) {
        // An accepted reply can publish its public snapshot before the client
        // finishes durably acknowledging the retained command identity. Do
        // not leave that brief intermediate reconciliation state on screen
        // after the locator and receipt have both been finalized.
        _change(() => _reconnectRequired = false);
      } else if (!result.accepted) {
        _change(() {
          _safeError = result.safeErrorCode ?? result.outcome.name;
        });
      }
      return result;
    } on Object {
      if (_active && generation == _authorityGeneration) {
        _setSafeError('authorityBindingUnavailable');
      }
      return null;
    } finally {
      if (_active && generation == _authorityGeneration) {
        _change(() => _busy = false);
      }
    }
  }

  Future<bool> _refreshLobby() async {
    if (!_active) return false;
    final generation = _authorityGeneration;
    final authority = _authority;
    try {
      final snapshot = await authority.refreshLobby();
      if (!_active ||
          generation != _authorityGeneration ||
          authority != _authority) {
        return false;
      }
      _acceptLobbySnapshot(snapshot);
      if (!authority.requiresReconciliation && _reconnectRequired) {
        _change(() => _reconnectRequired = false);
      }
      return true;
    } on Object catch (error) {
      if (_active && generation == _authorityGeneration) {
        _setSnapshotError(
          _safeSnapshotErrorCode(error, 'roomSnapshotUnavailable'),
          SnapshotErrorSource.room,
          recoverable: error is! ClientAuthorityContractViolation,
        );
      }
      return false;
    }
  }

  Future<void> refreshLobbyAction() async {
    await _refreshLobby();
  }

  Future<void> createRoom() async {
    final result = await _perform(FirstPlayableAuthorityAction.createRoom);
    if (result?.accepted != true) return;
    final code = _authority.latestCreatedRoomCode;
    if (code == null) {
      _change(() => _safeError = 'authorityRoomCodeUnavailable');
      return;
    }
    _roomCode = code;
    if (await _refreshLobby() && _active) {
      _change(() => _step = FirstPlayableStep.lobby);
    }
  }

  Future<void> joinRoom(String input) async {
    final code = input.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
      _change(() => _safeError = 'invalidRoomCode');
      return;
    }
    final result = await _perform(
      FirstPlayableAuthorityAction.joinRoom,
      input: code,
    );
    if (result?.accepted != true) return;
    _roomCode = code;
    if (await _refreshLobby() && _active) {
      _change(() => _step = FirstPlayableStep.lobby);
    }
  }

  Future<void> setReady() async {
    final result = await _perform(FirstPlayableAuthorityAction.setReady);
    if (result?.accepted == true) await _refreshLobby();
  }

  Future<void> startGame() async {
    final result = await _perform(FirstPlayableAuthorityAction.startGame);
    if (result?.accepted == true) await _refreshLobby();
  }

  Future<void> roll() async {
    await _perform(FirstPlayableAuthorityAction.roll);
  }

  Future<void> buy() async {
    await _perform(FirstPlayableAuthorityAction.buyProperty);
  }

  Future<void> decline() async {
    await _perform(FirstPlayableAuthorityAction.declineProperty);
  }

  Future<void> bid(String input) async {
    await _perform(FirstPlayableAuthorityAction.placeBid, input: input.trim());
  }

  Future<void> passAuction() async {
    await _perform(FirstPlayableAuthorityAction.passAuction);
  }

  Future<void> reconnect() async {
    final generation = _authorityGeneration;
    final authority = _authority;
    final result = await _perform(FirstPlayableAuthorityAction.reconnect);
    if (!_active ||
        generation != _authorityGeneration ||
        authority != _authority ||
        result == null ||
        result.outcome == FirstPlayableAuthorityOutcome.uncertain ||
        result.outcome == FirstPlayableAuthorityOutcome.blocked) {
      return;
    }
    if (result.outcome == FirstPlayableAuthorityOutcome.rejected) {
      _change(() => _reconnectRequired = false);
      return;
    }
    if (_roomCode == null) {
      try {
        final roomCode = authority.latestCreatedRoomCode;
        if (roomCode != null &&
            _active &&
            generation == _authorityGeneration &&
            authority == _authority) {
          _change(() => _roomCode = roomCode);
        }
      } on ClientAuthorityContractViolation catch (error) {
        if (_active &&
            generation == _authorityGeneration &&
            authority == _authority) {
          _setSafeError(error.code);
        }
        return;
      }
    }
    final refreshed = await _refreshLobby();
    if (!_active ||
        generation != _authorityGeneration ||
        authority != _authority ||
        !refreshed) {
      return;
    }
    final confirmedGame = authority.confirmedGameSnapshot;
    if (confirmedGame != null) _acceptGameSnapshot(confirmedGame);
    if (_active &&
        generation == _authorityGeneration &&
        authority == _authority) {
      _change(() => _reconnectRequired = false);
    }
  }

  Future<void> recoverSnapshotError() async {
    final source = _snapshotErrorSource;
    if (source == null || !_snapshotErrorRecoverable) return;
    final hasConfirmedGame = _game != null || _lobby?.gameId != null;
    if (source == SnapshotErrorSource.room && !hasConfirmedGame) {
      await _refreshLobby();
      return;
    }
    await reconnect();
  }
}
