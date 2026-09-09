import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';
import '../home_screen.dart';
import 'live_first_playable_authority.dart';
import 'live_first_playable_ui_state.dart';
import 'live_first_playable_view_model.dart';

export 'live_first_playable_authority.dart';

/// Existing VP0 presentation, now backed by the feature ViewModel. Supplying
/// authority keeps constructor-driven tests/embedders working without Firebase;
/// the routed app instead uses the root Riverpod override.
class LiveFirstPlayableApp extends StatelessWidget {
  const LiveFirstPlayableApp({
    this.authority,
    this.entryStep,
    this.initialRoomCode,
    this.requestedGameId,
    this.routeError,
    super.key,
  });

  final LiveFirstPlayableAuthority? authority;
  final FirstPlayableStep? entryStep;
  final String? initialRoomCode;
  final String? requestedGameId;
  final String? routeError;

  @override
  Widget build(BuildContext context) {
    final view = _LiveFirstPlayableView(
      entryStep: entryStep,
      initialRoomCode: initialRoomCode,
      requestedGameId: requestedGameId,
      routeError: routeError,
    );
    final repository = authority;
    if (repository == null) return view;
    return ProviderScope(
      overrides: [
        liveFirstPlayableAuthorityProvider.overrideWithValue(repository),
      ],
      child: view,
    );
  }
}

class _LiveFirstPlayableView extends ConsumerStatefulWidget {
  const _LiveFirstPlayableView({
    this.entryStep,
    this.initialRoomCode,
    this.requestedGameId,
    this.routeError,
  });
  final FirstPlayableStep? entryStep;
  final String? initialRoomCode;
  final String? requestedGameId;
  final String? routeError;

  @override
  ConsumerState<_LiveFirstPlayableView> createState() =>
      _LiveFirstPlayableViewState();
}

class _LiveFirstPlayableViewState extends ConsumerState<_LiveFirstPlayableView>
    with WidgetsBindingObserver {
  final _roomCodeController = TextEditingController();
  final _bidController = TextEditingController(text: '10');
  LiveFirstPlayableUiState get _ui =>
      ref.read(liveFirstPlayableViewModelProvider);
  LiveFirstPlayableViewModel get _model =>
      ref.read(liveFirstPlayableViewModelProvider.notifier);
  LobbyUiState? get _lobby => _ui.lobby;
  BoardUiState? get _game => _ui.game;
  String? get _roomCode => _ui.roomCode;
  String? get _safeError => _ui.safeError;
  SnapshotErrorSource? get _snapshotErrorSource => _ui.snapshotErrorSource;
  bool get _snapshotErrorRecoverable => _ui.snapshotErrorRecoverable;
  bool get _busy => _ui.busy;
  bool get _reconnectRequired => _ui.reconnectRequired;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _roomCodeController.text = widget.initialRoomCode ?? '';
  }

  @override
  void didUpdateWidget(covariant _LiveFirstPlayableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialRoomCode != oldWidget.initialRoomCode) {
      _roomCodeController.text = widget.initialRoomCode ?? '';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _model.restoreConfirmedPresentation();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _roomCodeController.dispose();
    _bidController.dispose();
    super.dispose();
  }

  void _navigate(String location, FirstPlayableStep step) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go(location);
    } else {
      _model.showEntry(step);
    }
  }

  Future<void> _refreshLobbyAction() => _model.refreshLobbyAction();
  Future<void> _createRoom() => _model.createRoom();
  Future<void> _joinRoom() => _model.joinRoom(_roomCodeController.text);
  Future<void> _setReady() => _model.setReady();
  Future<void> _startGame() => _model.startGame();
  Future<void> _roll() => _model.roll();
  Future<void> _buy() => _model.buy();
  Future<void> _decline() => _model.decline();
  Future<void> _bid() => _model.bid(_bidController.text);
  Future<void> _passAuction() => _model.passAuction();
  Future<void> _reconnect() => _model.reconnect();
  Future<void> _recoverSnapshotError() => _model.recoverSnapshotError();

  @override
  Widget build(BuildContext context) {
    ref.watch(liveFirstPlayableViewModelProvider);
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
                          _snapshotErrorSource == SnapshotErrorSource.room &&
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
    final requested = widget.requestedGameId;
    if (widget.routeError != null ||
        requested != null &&
            (_lobby?.gameId != requested ||
                _game != null && _game!.gameId != requested)) {
      return _Stage(
        key: const ValueKey('live-route-unavailable'),
        label: 'ACCESO',
        title: 'No se pudo abrir esta partida',
        body: const Text(
          'El enlace no autoriza acceso. Necesitás una sala confirmada por Authority.',
        ),
        primaryLabel: 'Volver al inicio',
        onPrimary: () async => _navigate('/', FirstPlayableStep.home),
      );
    }
    if (_reconnectRequired) return _buildReconnect();
    final game = _game;
    if (game != null) return _buildGame(game);
    if (_lobby?.gameId != null) return _buildGameLoading();
    return switch (widget.entryStep ?? _ui.step) {
      FirstPlayableStep.home => HomeScreen(
        onCreateRoom: () => _navigate('/create', FirstPlayableStep.create),
        onJoinRoom: () => _navigate('/join', FirstPlayableStep.join),
      ),
      FirstPlayableStep.create => _Stage(
        key: const ValueKey('live-create'),
        label: 'ARMAR SALA',
        title: 'Creá una mesa',
        body: const Text(
          'El código aparece sólo después del ACK de Authority.',
        ),
        primaryLabel: 'Crear sala',
        onPrimary: _createRoom,
        onBack: () => _navigate('/', FirstPlayableStep.home),
      ),
      FirstPlayableStep.join => _Stage(
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
        onBack: () => _navigate('/', FirstPlayableStep.home),
      ),
      FirstPlayableStep.lobby => _buildLobby(),
      FirstPlayableStep.board ||
      FirstPlayableStep.property ||
      FirstPlayableStep.auction ||
      FirstPlayableStep.reconnect => _buildGameLoading(),
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

  Widget _buildGame(BoardUiState game) {
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

  List<Widget> _confirmedBuyAuctionOutcomeReceipt(BoardUiState game) {
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

final class _ConfirmedBuyAuctionOutcomeReceipt extends StatelessWidget {
  const _ConfirmedBuyAuctionOutcomeReceipt({required this.receipt});

  final BuyAuctionOutcomeReceipt receipt;

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

class _GameSummary extends StatelessWidget {
  const _GameSummary({required this.game});

  final BoardUiState game;

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

  final LobbyMemberUiState member;

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
