import 'dart:async';

import 'package:board_backend_api/backend_api.dart';
import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';
import '../home_screen.dart';

/// Narrow presentation port for the live First Playable.
///
/// It exposes only public Authority data that the UI must render. Gameplay
/// legality, membership authorization and persistence remain server-owned.
abstract interface class LiveFirstPlayableAuthority {
  Future<FirstPlayableAuthorityResult> perform(
    FirstPlayableAuthorityAction action, {
    String? input,
  });

  String? get latestCreatedRoomCode;

  Future<AuthorityPublicRoomSnapshot> refreshLobby();

  /// Most recently validated lobby state, if this device has joined a room.
  AuthorityPublicRoomSnapshot? get confirmedLobbySnapshot;

  /// Most recently validated public game state, if the room has started.
  AuthorityPublicSnapshot? get confirmedGameSnapshot;

  /// Authenticated public room replacement snapshots.
  Stream<AuthorityPublicRoomSnapshot> get lobbySnapshots;

  /// Authenticated public game replacement snapshots.
  Stream<AuthorityPublicSnapshot> get gameSnapshots;

  /// A durable command identity survived a restart and needs explicit
  /// Authority reconciliation before the user can issue another command.
  bool get requiresReconciliation;
}

final class ClientLiveFirstPlayableAuthority
    implements LiveFirstPlayableAuthority {
  const ClientLiveFirstPlayableAuthority(this.client);

  final FirstPlayableAuthorityClient client;

  @override
  String? get latestCreatedRoomCode => client.latestCreatedRoomCode;

  @override
  Future<FirstPlayableAuthorityResult> perform(
    FirstPlayableAuthorityAction action, {
    String? input,
  }) => client.perform(action, input: input);

  @override
  Future<AuthorityPublicRoomSnapshot> refreshLobby() =>
      client.refreshConfirmedRoom();

  @override
  AuthorityPublicRoomSnapshot? get confirmedLobbySnapshot =>
      client.confirmedRoomSnapshot;

  @override
  AuthorityPublicSnapshot? get confirmedGameSnapshot =>
      client.confirmedGameSnapshot;

  @override
  Stream<AuthorityPublicRoomSnapshot> get lobbySnapshots =>
      client.roomSnapshots;

  @override
  Stream<AuthorityPublicSnapshot> get gameSnapshots => client.gameSnapshots;

  @override
  bool get requiresReconciliation => client.requiresReconciliation;
}

enum _LiveStep {
  home,
  create,
  join,
  lobby,
  board,
  property,
  auction,
  reconnect,
}

enum _SnapshotErrorSource { room, game }

class LiveFirstPlayableApp extends StatefulWidget {
  const LiveFirstPlayableApp({required this.authority, super.key});

  final LiveFirstPlayableAuthority authority;

  @override
  State<LiveFirstPlayableApp> createState() => _LiveFirstPlayableAppState();
}

class _LiveFirstPlayableAppState extends State<LiveFirstPlayableApp> {
  final _roomCodeController = TextEditingController();
  final _bidController = TextEditingController(text: '10');
  _LiveStep _step = _LiveStep.home;
  _LobbyView? _lobby;
  _GameView? _game;
  String? _roomCode;
  String? _safeError;
  _SnapshotErrorSource? _snapshotErrorSource;
  bool _snapshotErrorRecoverable = false;
  bool _busy = false;
  bool _reconnectRequired = false;
  AuthorityPublicSnapshot? _pendingGameSnapshot;
  StreamSubscription<AuthorityPublicRoomSnapshot>? _lobbySubscription;
  StreamSubscription<AuthorityPublicSnapshot>? _gameSubscription;
  int _authorityGeneration = 0;

  @override
  void initState() {
    super.initState();
    _listenToAuthority();
  }

  @override
  void didUpdateWidget(covariant LiveFirstPlayableApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authority == widget.authority) return;
    _authorityGeneration += 1;
    _lobbySubscription?.cancel();
    _gameSubscription?.cancel();
    _lobby = null;
    _game = null;
    _pendingGameSnapshot = null;
    _roomCode = null;
    _safeError = null;
    _snapshotErrorSource = null;
    _snapshotErrorRecoverable = false;
    _busy = false;
    _reconnectRequired = false;
    _step = _LiveStep.home;
    _listenToAuthority();
  }

  void _listenToAuthority() {
    final generation = _authorityGeneration;
    final authority = widget.authority;
    _lobbySubscription = authority.lobbySnapshots.listen(
      (snapshot) {
        if (generation == _authorityGeneration) _acceptLobbySnapshot(snapshot);
      },
      onError: (Object error, StackTrace _) {
        if (generation == _authorityGeneration) {
          _setSnapshotError(
            _safeSnapshotErrorCode(error, 'roomSnapshotUnavailable'),
            _SnapshotErrorSource.room,
            recoverable: error is! ClientAuthorityContractViolation,
          );
        }
      },
      onDone: () {
        if (generation == _authorityGeneration) {
          _setSnapshotError(
            'roomSnapshotStreamEnded',
            _SnapshotErrorSource.room,
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
            _SnapshotErrorSource.game,
            recoverable: error is! ClientAuthorityContractViolation,
          );
        }
      },
      onDone: () {
        if (generation == _authorityGeneration) {
          _setSnapshotError(
            'gameSnapshotStreamEnded',
            _SnapshotErrorSource.game,
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
      final lobby = _LobbyView.fromSnapshot(snapshot);
      final currentLobby = _lobby;
      if (currentLobby != null &&
          lobby.roomVersion < currentLobby.roomVersion) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _lobby = lobby;
        if (_snapshotErrorSource != _SnapshotErrorSource.game) {
          _safeError = null;
          _snapshotErrorSource = null;
          _snapshotErrorRecoverable = false;
        }
        if (_game == null) _step = _LiveStep.lobby;
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
      final game = _GameView.fromSnapshot(
        snapshot,
        actorPlayerId: actorPlayerId,
      );
      final currentGame = _game;
      if (currentGame != null && game.stateVersion < currentGame.stateVersion) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _game = game;
        _reconnectRequired = widget.authority.requiresReconciliation;
        if (_snapshotErrorSource != _SnapshotErrorSource.room) {
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
    if (mounted) {
      setState(() {
        _safeError = value;
        _snapshotErrorSource = null;
        _snapshotErrorRecoverable = false;
      });
    }
  }

  void _setSnapshotError(
    String value,
    _SnapshotErrorSource source, {
    required bool recoverable,
  }) {
    if (mounted) {
      setState(() {
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

  @override
  void dispose() {
    _authorityGeneration += 1;
    _lobbySubscription?.cancel();
    _gameSubscription?.cancel();
    _roomCodeController.dispose();
    _bidController.dispose();
    super.dispose();
  }

  Future<FirstPlayableAuthorityResult?> _perform(
    FirstPlayableAuthorityAction action, {
    String? input,
  }) async {
    if (_busy) return null;
    final generation = _authorityGeneration;
    final authority = widget.authority;
    setState(() {
      _busy = true;
      if (_snapshotErrorSource == null) _safeError = null;
    });
    try {
      final result = await authority.perform(action, input: input);
      if (!mounted || generation != _authorityGeneration) return null;
      if (result.outcome == FirstPlayableAuthorityOutcome.uncertain ||
          authority.requiresReconciliation) {
        setState(() => _reconnectRequired = true);
      } else if (result.accepted &&
          action != FirstPlayableAuthorityAction.reconnect) {
        // An accepted reply can publish its public snapshot before the client
        // finishes durably acknowledging the retained command identity. Do
        // not leave that brief intermediate reconciliation state on screen
        // after the locator and receipt have both been finalized.
        setState(() => _reconnectRequired = false);
      } else if (!result.accepted) {
        setState(() {
          _safeError = result.safeErrorCode ?? result.outcome.name;
        });
      }
      return result;
    } on Object {
      if (mounted && generation == _authorityGeneration) {
        _setSafeError('authorityBindingUnavailable');
      }
      return null;
    } finally {
      if (mounted && generation == _authorityGeneration) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool> _refreshLobby() async {
    final generation = _authorityGeneration;
    final authority = widget.authority;
    try {
      final snapshot = await authority.refreshLobby();
      if (!mounted ||
          generation != _authorityGeneration ||
          authority != widget.authority) {
        return false;
      }
      _acceptLobbySnapshot(snapshot);
      if (!authority.requiresReconciliation && _reconnectRequired) {
        setState(() => _reconnectRequired = false);
      }
      return true;
    } on Object catch (error) {
      if (mounted && generation == _authorityGeneration) {
        _setSnapshotError(
          _safeSnapshotErrorCode(error, 'roomSnapshotUnavailable'),
          _SnapshotErrorSource.room,
          recoverable: error is! ClientAuthorityContractViolation,
        );
      }
      return false;
    }
  }

  Future<void> _refreshLobbyAction() async {
    await _refreshLobby();
  }

  Future<void> _createRoom() async {
    final result = await _perform(FirstPlayableAuthorityAction.createRoom);
    if (result?.accepted != true) return;
    final code = widget.authority.latestCreatedRoomCode;
    if (code == null) {
      setState(() => _safeError = 'authorityRoomCodeUnavailable');
      return;
    }
    _roomCode = code;
    if (await _refreshLobby() && mounted) {
      setState(() => _step = _LiveStep.lobby);
    }
  }

  Future<void> _joinRoom() async {
    final code = _roomCodeController.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
      setState(() => _safeError = 'invalidRoomCode');
      return;
    }
    final result = await _perform(
      FirstPlayableAuthorityAction.joinRoom,
      input: code,
    );
    if (result?.accepted != true) return;
    _roomCode = code;
    if (await _refreshLobby() && mounted) {
      setState(() => _step = _LiveStep.lobby);
    }
  }

  Future<void> _setReady() async {
    final result = await _perform(FirstPlayableAuthorityAction.setReady);
    if (result?.accepted == true) await _refreshLobby();
  }

  Future<void> _startGame() async {
    final result = await _perform(FirstPlayableAuthorityAction.startGame);
    if (result?.accepted == true) await _refreshLobby();
  }

  Future<void> _roll() async {
    await _perform(FirstPlayableAuthorityAction.roll);
  }

  Future<void> _buy() async {
    await _perform(FirstPlayableAuthorityAction.buyProperty);
  }

  Future<void> _decline() async {
    await _perform(FirstPlayableAuthorityAction.declineProperty);
  }

  Future<void> _bid() async {
    await _perform(
      FirstPlayableAuthorityAction.placeBid,
      input: _bidController.text.trim(),
    );
  }

  Future<void> _passAuction() async {
    await _perform(FirstPlayableAuthorityAction.passAuction);
  }

  Future<void> _reconnect() async {
    final generation = _authorityGeneration;
    final authority = widget.authority;
    final result = await _perform(FirstPlayableAuthorityAction.reconnect);
    if (!mounted ||
        generation != _authorityGeneration ||
        authority != widget.authority ||
        result == null ||
        result.outcome == FirstPlayableAuthorityOutcome.uncertain ||
        result.outcome == FirstPlayableAuthorityOutcome.blocked) {
      return;
    }
    if (result.outcome == FirstPlayableAuthorityOutcome.rejected) {
      setState(() => _reconnectRequired = false);
      return;
    }
    if (_roomCode == null) {
      try {
        final roomCode = authority.latestCreatedRoomCode;
        if (roomCode != null &&
            mounted &&
            generation == _authorityGeneration &&
            authority == widget.authority) {
          setState(() => _roomCode = roomCode);
        }
      } on ClientAuthorityContractViolation catch (error) {
        if (mounted &&
            generation == _authorityGeneration &&
            authority == widget.authority) {
          _setSafeError(error.code);
        }
        return;
      }
    }
    final refreshed = await _refreshLobby();
    if (!mounted ||
        generation != _authorityGeneration ||
        authority != widget.authority ||
        !refreshed) {
      return;
    }
    final confirmedGame = authority.confirmedGameSnapshot;
    if (confirmedGame != null) _acceptGameSnapshot(confirmedGame);
    if (mounted &&
        generation == _authorityGeneration &&
        authority == widget.authority) {
      setState(() => _reconnectRequired = false);
    }
  }

  Future<void> _recoverSnapshotError() async {
    final source = _snapshotErrorSource;
    if (source == null || !_snapshotErrorRecoverable) return;
    final hasConfirmedGame = _game != null || _lobby?.gameId != null;
    if (source == _SnapshotErrorSource.room && !hasConfirmedGame) {
      await _refreshLobby();
      return;
    }
    await _reconnect();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildSurface(),
        if (_safeError != null)
          Positioned(
            left: AppSpacing.x3,
            right: AppSpacing.x3,
            bottom: AppSpacing.x3,
            child: Material(
              color: AppPalette.coralSoft,
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.x3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Authority · $_safeError',
                      key: const ValueKey('live-safe-error'),
                      textAlign: TextAlign.center,
                    ),
                    if (_snapshotErrorRecoverable) ...[
                      const SizedBox(height: AppSpacing.x2),
                      TextButton(
                        key: const ValueKey('live-snapshot-recovery-action'),
                        onPressed: _busy ? null : _recoverSnapshotError,
                        child: Text(
                          _snapshotErrorSource == _SnapshotErrorSource.room &&
                                  _lobby?.gameId == null
                              ? 'Actualizar lobby'
                              : 'Reconciliar',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        if (_busy)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              key: ValueKey('live-authority-pending'),
            ),
          ),
      ],
    );
  }

  Widget _buildSurface() {
    if (_reconnectRequired) return _buildReconnect();
    final game = _game;
    if (game != null) return _buildGame(game);
    if (_lobby?.gameId != null) return _buildGameLoading();
    return switch (_step) {
      _LiveStep.home => HomeScreen(
        onCreateRoom: () => setState(() => _step = _LiveStep.create),
        onJoinRoom: () => setState(() => _step = _LiveStep.join),
      ),
      _LiveStep.create => _Stage(
        key: const ValueKey('live-create'),
        label: 'ARMAR SALA',
        title: 'Creá una mesa',
        body: const Text(
          'El código aparece sólo después del ACK de Authority.',
        ),
        primaryLabel: 'Crear sala',
        onPrimary: _createRoom,
        onBack: () => setState(() => _step = _LiveStep.home),
      ),
      _LiveStep.join => _Stage(
        key: const ValueKey('live-join'),
        label: 'ENTRAR',
        title: 'Sumate con el código',
        body: TextField(
          key: const ValueKey('live-room-code-input'),
          controller: _roomCodeController,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Código de sala',
            border: OutlineInputBorder(),
          ),
        ),
        primaryLabel: 'Unirse',
        onPrimary: _joinRoom,
        onBack: () => setState(() => _step = _LiveStep.home),
      ),
      _LiveStep.lobby => _buildLobby(),
      _LiveStep.board ||
      _LiveStep.property ||
      _LiveStep.auction ||
      _LiveStep.reconnect => _buildGameLoading(),
    };
  }

  Widget _buildGameLoading() {
    final gameId = _lobby?.gameId;
    return _Stage(
      key: const ValueKey('live-game-loading'),
      label: 'PARTIDA',
      title: 'Sincronizando la partida',
      body: GameCard(
        child: Text(
          gameId == null
              ? 'Esperando el snapshot público de Authority.'
              : 'La sala confirmó la partida $gameId. Esperando el snapshot público.',
        ),
      ),
      primaryLabel: 'Actualizar lobby',
      onPrimary: _refreshLobbyAction,
    );
  }

  Widget _buildReconnect() => _Stage(
    key: const ValueKey('live-reconnect'),
    label: 'RECONECTAR',
    title: 'Recuperá el estado confirmado',
    body: const GameCard(
      child: Text(
        'Authority no confirmó el último comando. Reconnect reutiliza la identidad durable y reemplaza el snapshot local.',
      ),
    ),
    primaryLabel: 'Reconciliar',
    onPrimary: _reconnect,
  );

  Widget _buildGame(_GameView game) {
    if (game.finished) {
      return _Stage(
        key: const ValueKey('live-results'),
        label: 'RESULTADO',
        title: 'Partida finalizada',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GameSummary(game: game),
            ..._confirmedBuyAuctionOutcomeReceipt(game),
            const SizedBox(height: AppSpacing.x3),
            GameCard(
              child: Text(
                game.winnerPlayerId == null
                    ? 'Authority confirmó el cierre de la partida.'
                    : 'Ganó ${game.winnerPlayerId}.',
              ),
            ),
          ],
        ),
        primaryLabel: 'Actualizar lobby',
        onPrimary: _refreshLobbyAction,
      );
    }

    final offer = game.propertyOffer;
    if (offer != null) {
      return _Stage(
        key: const ValueKey('live-property'),
        label: 'PROPIEDAD',
        title: 'Decisión confirmada',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GameSummary(game: game),
            ..._confirmedBuyAuctionOutcomeReceipt(game),
            const SizedBox(height: AppSpacing.x3),
            GameCard(
              child: Text(
                'Propiedad ${offer.propertyId} · ${offer.purchasePrice}. El contenido DEC-065 sigue fuera de este VP0.',
              ),
            ),
            if (game.lastRoll != null) ...[
              const SizedBox(height: AppSpacing.x2),
              GameCard(
                child: Text(
                  'Dados confirmados: ${game.lastRoll!.die1} + ${game.lastRoll!.die2} = ${game.lastRoll!.total}.',
                ),
              ),
            ],
            if (game.canResolveProperty) ...[
              const SizedBox(height: AppSpacing.x3),
              OutlinedButton(
                onPressed: _busy ? null : _decline,
                child: const Text('No comprar · abrir subasta'),
              ),
            ] else ...[
              const SizedBox(height: AppSpacing.x3),
              const Text(
                'Esperando la decisión confirmada del jugador activo.',
              ),
            ],
          ],
        ),
        primaryLabel: 'Comprar',
        onPrimary: _buy,
        hidePrimary: !game.canResolveProperty,
      );
    }

    final auction = game.auction;
    if (auction != null) {
      return _Stage(
        key: const ValueKey('live-auction'),
        label: 'SUBASTA',
        title: 'Subasta autoritativa',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GameSummary(game: game),
            ..._confirmedBuyAuctionOutcomeReceipt(game),
            const SizedBox(height: AppSpacing.x3),
            GameCard(
              child: Text(
                'Propiedad ${auction.propertyId} · puja actual ${auction.currentBid} · turno de ${auction.currentBidderPlayerId}.',
              ),
            ),
            if (game.canBid) ...[
              const SizedBox(height: AppSpacing.x3),
              TextField(
                controller: _bidController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tu puja',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.x3),
              OutlinedButton(
                onPressed: _busy ? null : _passAuction,
                child: const Text('Pasar'),
              ),
            ] else ...[
              const SizedBox(height: AppSpacing.x3),
              const Text('Esperando la puja confirmada del jugador activo.'),
            ],
          ],
        ),
        primaryLabel: 'Pujar',
        onPrimary: _bid,
        hidePrimary: !game.canBid,
      );
    }

    if (game.awaitingRoll) {
      return _Stage(
        key: const ValueKey('live-board'),
        label: 'TURNO CONFIRMADO',
        title: game.isActorTurn ? 'Tu turno' : 'Esperando turno',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GameSummary(game: game),
            ..._confirmedBuyAuctionOutcomeReceipt(game),
            const SizedBox(height: AppSpacing.x3),
            const GameCard(
              child: Text(
                'El movimiento se aplica únicamente cuando Authority confirma el Roll.',
              ),
            ),
          ],
        ),
        primaryLabel: 'Tirar dados',
        onPrimary: _roll,
        hidePrimary: !game.isActorTurn,
      );
    }

    return _Stage(
      key: const ValueKey('live-game-waiting'),
      label: 'PARTIDA',
      title: 'Esperando transición autoritativa',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GameSummary(game: game),
          ..._confirmedBuyAuctionOutcomeReceipt(game),
          const SizedBox(height: AppSpacing.x3),
          GameCard(
            child: Text(
              'Authority confirmó la fase ${game.phase}. No hay una acción local habilitada para este estado.',
            ),
          ),
        ],
      ),
      primaryLabel: 'Actualizar lobby',
      onPrimary: _refreshLobbyAction,
    );
  }

  List<Widget> _confirmedBuyAuctionOutcomeReceipt(_GameView game) {
    final receipt = game.buyAuctionOutcomeReceipt;
    if (receipt == null) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: AppSpacing.x3),
      _ConfirmedBuyAuctionOutcomeReceipt(receipt: receipt),
    ];
  }

  Widget _buildLobby() {
    final lobby = _lobby;
    if (lobby == null) {
      return _Stage(
        key: const ValueKey('live-lobby-loading'),
        label: 'LOBBY',
        title: 'Sincronizando la mesa',
        body: const Text('Esperando el snapshot público confirmado.'),
        primaryLabel: 'Actualizar lobby',
        onPrimary: _refreshLobbyAction,
      );
    }
    final actor = lobby.members.firstWhere(
      (member) => member.playerId == lobby.actorPlayerId,
    );
    return _Stage(
      key: const ValueKey('live-lobby'),
      label: 'LOBBY',
      title: 'La mesa está casi lista',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GameCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _roomCode == null ? 'SALA CONFIRMADA' : 'CÓDIGO · $_roomCode',
                  key: const ValueKey('live-authoritative-room-code'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppSpacing.x3),
                for (final member in lobby.members) ...[
                  _LobbyMemberRow(member: member),
                  const SizedBox(height: AppSpacing.x2),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          OutlinedButton.icon(
            onPressed: _busy ? null : _refreshLobbyAction,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Actualizar lobby'),
          ),
          if (!actor.ready) ...[
            const SizedBox(height: AppSpacing.x3),
            OutlinedButton.icon(
              onPressed: _busy ? null : _setReady,
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('Estoy lista'),
            ),
          ],
          if (lobby.actorPlayerId == lobby.hostPlayerId) ...[
            const SizedBox(height: AppSpacing.x3),
            FilledButton(
              onPressed: _busy ? null : _startGame,
              child: const Text('Empezar partida'),
            ),
          ],
        ],
      ),
      primaryLabel: 'Actualizar lobby',
      onPrimary: _refreshLobbyAction,
      hidePrimary: true,
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({
    required this.label,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.onBack,
    this.hidePrimary = false,
    super.key,
  });

  final String label;
  final String title;
  final Widget body;
  final String primaryLabel;
  final Future<void> Function() onPrimary;
  final VoidCallback? onBack;
  final bool hidePrimary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (onBack != null)
                    IconButton(
                      onPressed: onBack,
                      tooltip: 'Volver',
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  Expanded(
                    child: GamePill(label: label, color: AppPalette.violet),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x4),
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: AppSpacing.x4),
              body,
              if (!hidePrimary) ...[
                const SizedBox(height: AppSpacing.x5),
                FilledButton(
                  onPressed: () => onPrimary(),
                  child: Text(primaryLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final class _LobbyView {
  const _LobbyView({
    required this.roomVersion,
    required this.actorPlayerId,
    required this.hostPlayerId,
    required this.gameId,
    required this.members,
  });

  factory _LobbyView.fromSnapshot(AuthorityPublicRoomSnapshot snapshot) {
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
          return _LobbyMember(playerId: playerId, ready: ready, kind: kind);
        })
        .toList(growable: false);
    if (members.isEmpty ||
        !members.any((member) => member.playerId == actorPlayerId) ||
        !members.any((member) => member.playerId == hostPlayerId)) {
      throw const FormatException('invalidPublicLobbyMembership');
    }
    return _LobbyView(
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
  final List<_LobbyMember> members;
}

final class _LobbyMember {
  const _LobbyMember({
    required this.playerId,
    required this.ready,
    required this.kind,
  });

  final String playerId;
  final bool ready;
  final String kind;
}

final class _GameView {
  const _GameView({
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

  factory _GameView.fromSnapshot(
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
        : _RollView.fromSnapshot(rawLastRoll);
    final pending = _optionalObject(value['pendingDecision']);
    final activeAuction = _optionalObject(value['activeAuction']);
    final propertyOffer = pending?['kind'] == 'propertyOffer'
        ? _PropertyOfferView.fromSnapshot(pending!)
        : null;
    final auction = activeAuction == null
        ? null
        : _AuctionView.fromSnapshot(activeAuction);
    final result = _optionalObject(value['result']);
    final winnerPlayerId = result?['winnerPlayerId'];
    if (winnerPlayerId != null &&
        (winnerPlayerId is! String || winnerPlayerId.isEmpty)) {
      throw const FormatException('invalidPublicGameResult');
    }
    final buyAuctionOutcomeReceipt = _BuyAuctionOutcomeReceipt.fromLastMutation(
      value['lastMutation'],
      ownership: value['ownership'],
    );
    if (buyAuctionOutcomeReceipt != null &&
        (phase != 'turnResolved' || pending != null || activeAuction != null)) {
      throw const FormatException(
        'invalidPublicGameSnapshot:lastMutation.outcome.context',
      );
    }
    return _GameView(
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
  final _RollView? lastRoll;
  final String actorPlayerId;
  final _PropertyOfferView? propertyOffer;
  final _AuctionView? auction;
  final String? winnerPlayerId;
  final _BuyAuctionOutcomeReceipt? buyAuctionOutcomeReceipt;

  bool get finished => status == 'finished';
  bool get isActorTurn => currentPlayerId == actorPlayerId;
  bool get awaitingRoll => phase == 'awaitingRoll';
  bool get canResolveProperty =>
      propertyOffer != null &&
      propertyOffer!.allowedPlayerIds.contains(actorPlayerId);
  bool get canBid =>
      auction != null && auction!.currentBidderPlayerId == actorPlayerId;
}

final class _RollView {
  const _RollView({
    required this.die1,
    required this.die2,
    required this.total,
  });

  factory _RollView.fromSnapshot(Map<String, Object?> value) {
    final die1 = _requiredDie(value['die1'], 'lastRoll.die1');
    final die2 = _requiredDie(value['die2'], 'lastRoll.die2');
    final total = _requiredNonNegativeInt(value['total'], 'lastRoll.total');
    if (total != die1 + die2) {
      throw const FormatException('invalidPublicGameSnapshot:lastRoll.total');
    }
    return _RollView(die1: die1, die2: die2, total: total);
  }

  final int die1;
  final int die2;
  final int total;
}

final class _PropertyOfferView {
  const _PropertyOfferView({
    required this.propertyId,
    required this.purchasePrice,
    required this.allowedPlayerIds,
  });

  factory _PropertyOfferView.fromSnapshot(Map<String, Object?> value) {
    final payload = _requiredObject(value['payload'], 'propertyOffer.payload');
    final allowed = _requiredStringList(
      value['allowedPlayerIds'],
      'propertyOffer.allowedPlayerIds',
    );
    return _PropertyOfferView(
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

final class _AuctionView {
  const _AuctionView({
    required this.propertyId,
    required this.currentBid,
    required this.currentBidderPlayerId,
  });

  factory _AuctionView.fromSnapshot(Map<String, Object?> value) => _AuctionView(
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

enum _BuyAuctionOutcomeKind {
  propertyPurchased,
  auctionWon,
  auctionEndedWithoutWinner,
}

/// A terminal Buy/Auction outcome that Authority durably included in the
/// replacement public snapshot. It is intentionally parsed from the snapshot,
/// never inferred from an acknowledged command.
final class _BuyAuctionOutcomeReceipt {
  const _BuyAuctionOutcomeReceipt._({
    required this.kind,
    required this.propertyId,
    this.ownerPlayerId,
    this.amount,
  });

  static _BuyAuctionOutcomeReceipt? fromLastMutation(
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

  static _BuyAuctionOutcomeReceipt _propertyPurchased(
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
    return _BuyAuctionOutcomeReceipt._(
      kind: _BuyAuctionOutcomeKind.propertyPurchased,
      propertyId: propertyId,
      ownerPlayerId: playerId,
      amount: price,
    );
  }

  static _BuyAuctionOutcomeReceipt _auctionWon(
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
    return _BuyAuctionOutcomeReceipt._(
      kind: _BuyAuctionOutcomeKind.auctionWon,
      propertyId: propertyId,
      ownerPlayerId: winnerPlayerId,
      amount: winningBid,
    );
  }

  static _BuyAuctionOutcomeReceipt _auctionEndedWithoutWinner(
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
    return _BuyAuctionOutcomeReceipt._(
      kind: _BuyAuctionOutcomeKind.auctionEndedWithoutWinner,
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

  final _BuyAuctionOutcomeKind kind;
  final String propertyId;
  final String? ownerPlayerId;
  final int? amount;

  String get cardKey => switch (kind) {
    _BuyAuctionOutcomeKind.propertyPurchased => 'live-confirmed-buy-outcome',
    _BuyAuctionOutcomeKind.auctionWon => 'live-confirmed-auction-award',
    _BuyAuctionOutcomeKind.auctionEndedWithoutWinner =>
      'live-confirmed-auction-no-winner',
  };

  String get summary => switch (kind) {
    _BuyAuctionOutcomeKind.propertyPurchased =>
      'Compra confirmada · $propertyId pertenece a $ownerPlayerId. Pago confirmado: $amount.',
    _BuyAuctionOutcomeKind.auctionWon =>
      'Subasta adjudicada · $propertyId pertenece a $ownerPlayerId. Pago confirmado: $amount.',
    _BuyAuctionOutcomeKind.auctionEndedWithoutWinner =>
      'Subasta cerrada · $propertyId quedó sin adjudicar.',
  };
}

final class _ConfirmedBuyAuctionOutcomeReceipt extends StatelessWidget {
  const _ConfirmedBuyAuctionOutcomeReceipt({required this.receipt});

  final _BuyAuctionOutcomeReceipt receipt;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: 'Resultado confirmado. ${receipt.summary}',
    child: GameCard(
      key: ValueKey(receipt.cardKey),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'RESULTADO CONFIRMADO',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppPalette.primaryDeep,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(receipt.summary),
        ],
      ),
    ),
  );
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

class _GameSummary extends StatelessWidget {
  const _GameSummary({required this.game});

  final _GameView game;

  @override
  Widget build(BuildContext context) {
    return GameCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'PARTIDA · ${game.gameId}',
            key: const ValueKey('live-game-id'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(
            'VERSIÓN · ${game.stateVersion}',
            key: const ValueKey('live-game-version'),
          ),
          Text(
            'PRESET · ${game.presetId}',
            key: const ValueKey('live-game-preset'),
          ),
          Text(
            'TURNO · ${game.currentPlayerId}',
            key: const ValueKey('live-game-current-player'),
          ),
        ],
      ),
    );
  }
}

class _LobbyMemberRow extends StatelessWidget {
  const _LobbyMemberRow({required this.member});

  final _LobbyMember member;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${member.playerId}. ${member.ready ? 'Listo' : 'No listo'}.',
      child: Container(
        key: ValueKey('live-member-${member.playerId}'),
        padding: const EdgeInsets.all(AppSpacing.x2),
        decoration: BoxDecoration(
          color: member.ready ? AppPalette.greenSoft : AppPalette.coralSoft,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          children: [
            Icon(
              member.ready
                  ? Icons.check_circle_rounded
                  : Icons.hourglass_bottom_rounded,
              color: member.ready ? AppPalette.primary : AppPalette.coral,
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Text(
                '${member.playerId} · ${member.kind} · ${member.ready ? 'Listo' : 'No listo'}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
