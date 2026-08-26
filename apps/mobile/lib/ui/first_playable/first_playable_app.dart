import 'package:flutter/material.dart';
import 'package:board_backend_api/backend_api.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';
import '../game_board/dice_pair.dart';
import '../game_board/vertical_board_b.dart';
import '../home_screen.dart';

enum FirstPlayableStep {
  home,
  createRoom,
  joinRoom,
  lobby,
  board,
  propertyOffer,
  auction,
  reconnect,
}

class FirstPlayableApp extends StatefulWidget {
  const FirstPlayableApp({
    super.key,
    this.initialStep = FirstPlayableStep.home,
    this.onIntent,
    this.authority,
  });

  final FirstPlayableStep initialStep;

  /// Emits only presentation intent identifiers. A production adapter owns
  /// command construction, authority calls and confirmed snapshots.
  final ValueChanged<String>? onIntent;

  /// When present, authoritative actions advance presentation only after an
  /// accepted ACK. Null keeps the existing preview/golden harness isolated.
  final FirstPlayableAuthorityBinding? authority;

  @override
  State<FirstPlayableApp> createState() => _FirstPlayableAppState();
}

class _FirstPlayableAppState extends State<FirstPlayableApp> {
  late FirstPlayableStep _step;
  bool _ready = false;
  bool _rolled = false;
  bool _recovered = false;
  bool _busy = false;
  final _roomCodeController = TextEditingController(text: 'ABC123');
  final _bidController = TextEditingController(text: 'PLACEHOLDER');

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep;
  }

  @override
  void dispose() {
    _roomCodeController.dispose();
    _bidController.dispose();
    super.dispose();
  }

  void _emit(String intentId, {FirstPlayableStep? then}) {
    widget.onIntent?.call(intentId);
    if (then != null) setState(() => _step = then);
  }

  Future<void> _perform(
    String intentId,
    FirstPlayableAuthorityAction action, {
    String? input,
    VoidCallback? onAccepted,
  }) async {
    if (_busy) return;
    widget.onIntent?.call(intentId);
    final authority = widget.authority;
    if (authority == null) {
      onAccepted?.call();
      return;
    }
    setState(() => _busy = true);
    late final FirstPlayableAuthorityResult result;
    try {
      result = await authority.perform(action, input: input);
    } on Object {
      result = const FirstPlayableAuthorityResult(
        outcome: FirstPlayableAuthorityOutcome.blocked,
        safeErrorCode: 'authorityBindingUnavailable',
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.accepted) {
      onAccepted?.call();
      return;
    }
    final code =
        result.safeErrorCode ??
        switch (result.outcome) {
          FirstPlayableAuthorityOutcome.rejected => 'commandRejected',
          FirstPlayableAuthorityOutcome.uncertain => 'commandOutcomeUncertain',
          FirstPlayableAuthorityOutcome.blocked => 'commandBlocked',
          FirstPlayableAuthorityOutcome.accepted => 'commandAccepted',
        };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Authority · $code')));
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(
      children: [
        AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : AppMotion.page,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: switch (_step) {
            FirstPlayableStep.home => HomeScreen(
              key: const ValueKey('fp-home'),
              onCreateRoom: () =>
                  _emit('open-create-room', then: FirstPlayableStep.createRoom),
              onJoinRoom: () =>
                  _emit('open-join-room', then: FirstPlayableStep.joinRoom),
            ),
            FirstPlayableStep.createRoom => _CreateRoomB(
              key: const ValueKey('fp-create'),
              onBack: () => setState(() => _step = FirstPlayableStep.home),
              onCreate: () => _perform(
                'create-room',
                FirstPlayableAuthorityAction.createRoom,
                onAccepted: () =>
                    setState(() => _step = FirstPlayableStep.lobby),
              ),
            ),
            FirstPlayableStep.joinRoom => _JoinRoomB(
              key: const ValueKey('fp-join'),
              controller: _roomCodeController,
              onBack: () => setState(() => _step = FirstPlayableStep.home),
              onJoin: () => _perform(
                'join-room',
                FirstPlayableAuthorityAction.joinRoom,
                input: _roomCodeController.text,
                onAccepted: () =>
                    setState(() => _step = FirstPlayableStep.lobby),
              ),
            ),
            FirstPlayableStep.lobby => _LobbyB(
              key: const ValueKey('fp-lobby'),
              isReady: _ready,
              onReady: () {
                _perform(
                  'set-ready',
                  FirstPlayableAuthorityAction.setReady,
                  onAccepted: () => setState(() => _ready = true),
                );
              },
              onStart: _ready
                  ? () => _perform(
                      'start-game',
                      FirstPlayableAuthorityAction.startGame,
                      onAccepted: () =>
                          setState(() => _step = FirstPlayableStep.board),
                    )
                  : null,
            ),
            FirstPlayableStep.board => _BoardB(
              key: const ValueKey('fp-board'),
              rolled: _rolled,
              onRoll: () {
                _perform(
                  'roll',
                  FirstPlayableAuthorityAction.roll,
                  onAccepted: () => setState(() => _rolled = true),
                );
              },
              onOffer: _rolled
                  ? () =>
                        setState(() => _step = FirstPlayableStep.propertyOffer)
                  : null,
            ),
            FirstPlayableStep.propertyOffer => _PropertyOfferB(
              key: const ValueKey('fp-property'),
              onBuy: () => _perform(
                'buy-property',
                FirstPlayableAuthorityAction.buyProperty,
                onAccepted: () =>
                    setState(() => _step = FirstPlayableStep.reconnect),
              ),
              onDecline: () => _perform(
                'decline-property',
                FirstPlayableAuthorityAction.declineProperty,
                onAccepted: () =>
                    setState(() => _step = FirstPlayableStep.auction),
              ),
            ),
            FirstPlayableStep.auction => _AuctionB(
              key: const ValueKey('fp-auction'),
              controller: _bidController,
              onBid: () => _perform(
                'place-bid',
                FirstPlayableAuthorityAction.placeBid,
                input: _bidController.text,
              ),
              onPass: () => _perform(
                'pass-auction',
                FirstPlayableAuthorityAction.passAuction,
                onAccepted: () =>
                    setState(() => _step = FirstPlayableStep.reconnect),
              ),
            ),
            FirstPlayableStep.reconnect => _ReconnectB(
              key: const ValueKey('fp-reconnect'),
              recovered: _recovered,
              onRetry: () {
                _perform(
                  'retry-reconnect',
                  FirstPlayableAuthorityAction.reconnect,
                  onAccepted: () => setState(() => _recovered = true),
                );
              },
              onReturn: _recovered
                  ? () =>
                        _emit('return-to-board', then: FirstPlayableStep.board)
                  : null,
            ),
          },
        ),
        if (_busy)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              key: ValueKey('fp-authority-pending'),
            ),
          ),
      ],
    );
  }
}

class _FlowScaffold extends StatelessWidget {
  const _FlowScaffold({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.child,
    this.onBack,
    super.key,
  });

  final String step;
  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: key,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final gutter = constraints.maxWidth < 375
                ? AppSpacing.x3
                : AppSpacing.x5;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                gutter,
                AppSpacing.x3,
                gutter,
                AppSpacing.x8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (onBack != null) ...[
                        IconButton(
                          onPressed: onBack,
                          tooltip: 'Volver',
                          constraints: const BoxConstraints(
                            minWidth: AppSizes.minTouchTarget,
                            minHeight: AppSizes.minTouchTarget,
                          ),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: AppSpacing.x2),
                      ],
                      Expanded(
                        child: GamePill(label: step, color: AppPalette.violet),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppPalette.inkSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x5),
                  child,
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CreateRoomB extends StatelessWidget {
  const _CreateRoomB({required this.onBack, required this.onCreate, super.key});

  final VoidCallback onBack;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return _FlowScaffold(
      key: key,
      step: '1 · ARMAR SALA',
      title: 'Elegí cómo empieza esta vuelta',
      subtitle: 'El preset llega resuelto por la capa dueña. La UI no inventa reglas ni caps.',
      onBack: onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GameCard(
            background: AppPalette.coralSoft,
            borderColor: AppPalette.coral,
            child: Row(
              children: [
                CharacterArtSlot(
                  identity: CharacterIdentity.almendra,
                  size: 86,
                ),
                SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PRESET PLACEHOLDER',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: AppSpacing.x1),
                      Text('Configuración confirmada por la sala.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x5),
          FilledButton(
            key: const ValueKey('fp-create-room'),
            onPressed: onCreate,
            child: const Text('Crear sala'),
          ),
        ],
      ),
    );
  }
}

class _JoinRoomB extends StatelessWidget {
  const _JoinRoomB({
    required this.controller,
    required this.onBack,
    required this.onJoin,
    super.key,
  });

  final TextEditingController controller;
  final VoidCallback onBack;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return _FlowScaffold(
      key: key,
      step: '1 · ENTRAR',
      title: 'Sumate a la mesa',
      subtitle: 'Usá el código de seis caracteres que te compartieron.',
      onBack: onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('fp-room-code'),
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'Código de sala',
              filled: true,
              fillColor: AppPalette.surface,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          FilledButton(onPressed: onJoin, child: const Text('Unirse a sala')),
        ],
      ),
    );
  }
}

class _LobbyB extends StatelessWidget {
  const _LobbyB({
    required this.isReady,
    required this.onReady,
    required this.onStart,
    super.key,
  });

  final bool isReady;
  final VoidCallback onReady;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    return _FlowScaffold(
      key: key,
      step: '2 · LOBBY',
      title: 'La mesa está casi lista',
      subtitle: 'Ready y Start se habilitan sólo desde el estado confirmado de la sala.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GameCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'CÓDIGO · ABC 123',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppSpacing.x4),
                _PlayerRow(
                  name: 'Romina PLACEHOLDER',
                  detail: isReady ? 'Lista' : 'Todavía no está lista',
                  ready: isReady,
                ),
                const SizedBox(height: AppSpacing.x2),
                const _PlayerRow(
                  name: 'Jugador PLACEHOLDER',
                  detail: 'Listo',
                  ready: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x5),
          if (!isReady)
            OutlinedButton.icon(
              onPressed: onReady,
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('Estoy lista'),
            ),
          if (!isReady) const SizedBox(height: AppSpacing.x3),
          FilledButton(
            onPressed: onStart,
            child: const Text('Empezar partida'),
          ),
          if (onStart == null) ...[
            const SizedBox(height: AppSpacing.x2),
            const Text(
              'Marcá Estoy lista para habilitar Start.',
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.name,
    required this.detail,
    required this.ready,
  });

  final String name;
  final String detail;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$name. $detail.',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
          padding: const EdgeInsets.all(AppSpacing.x2),
          decoration: BoxDecoration(
            color: ready ? AppPalette.greenSoft : AppPalette.coralSoft,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Row(
            children: [
              Icon(
                ready
                    ? Icons.check_circle_rounded
                    : Icons.hourglass_bottom_rounded,
                color: ready ? AppPalette.primary : AppPalette.coral,
              ),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name),
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.inkSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardB extends StatelessWidget {
  const _BoardB({
    required this.rolled,
    required this.onRoll,
    required this.onOffer,
    super.key,
  });

  final bool rolled;
  final VoidCallback onRoll;
  final VoidCallback? onOffer;

  @override
  Widget build(BuildContext context) {
    return _FlowScaffold(
      key: key,
      step: '3 · TU TURNO',
      title: 'El tablero vuelve al centro',
      subtitle: 'Los dados y el destino visibles son snapshots PLACEHOLDER confirmados; la UI no calcula movimiento.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Expanded(
                child: GamePill(
                  label: 'TU TURNO',
                  color: AppPalette.primary,
                  icon: Icons.pets_rounded,
                ),
              ),
              SizedBox(width: AppSpacing.x2),
              Expanded(
                child: GamePill(
                  label: 'CONECTADA',
                  color: AppPalette.violet,
                  icon: Icons.wifi_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          VerticalBoardB(
            currentPosition: rolled ? 7 : 0,
            highlightedPosition: rolled ? 7 : null,
            height: 260,
          ),
          const SizedBox(height: AppSpacing.x4),
          DicePair(first: rolled ? 4 : null, second: rolled ? 3 : null),
          const SizedBox(height: AppSpacing.x3),
          if (rolled)
            Semantics(
              liveRegion: true,
              child: const GameCard(
                background: AppPalette.coralSoft,
                borderColor: AppPalette.coral,
                child: Text(
                  'Movimiento confirmado PLACEHOLDER · destino 8.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.x4),
          FilledButton(
            key: const ValueKey('fp-board-action'),
            onPressed: rolled ? onOffer : onRoll,
            child: Text(rolled ? 'Ver oferta' : 'Tirar dados'),
          ),
        ],
      ),
    );
  }
}

class _PropertyOfferB extends StatelessWidget {
  const _PropertyOfferB({
    required this.onBuy,
    required this.onDecline,
    super.key,
  });

  final VoidCallback onBuy;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return _FlowScaffold(
      key: key,
      step: '4 · PROPIEDAD',
      title: '¿La sumás a tu vuelta?',
      subtitle: 'Datos PLACEHOLDER caller-owned. La consecuencia visible no modifica cash ni ownership.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GameCard(
            background: AppPalette.coralSoft,
            borderColor: AppPalette.coral,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Wrap(
                  spacing: AppSpacing.x2,
                  runSpacing: AppSpacing.x2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'PROPIEDAD PLACEHOLDER',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    GamePill(label: 'GRUPO PLACEHOLDER'),
                  ],
                ),
                const SizedBox(height: AppSpacing.x4),
                Text(
                  r'Precio confirmado · $ PLACEHOLDER',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.x2),
                const Text('Alquiler y saldo proyectado: PLACEHOLDER DEC-065.'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x5),
          FilledButton(onPressed: onBuy, child: const Text('Comprar')),
          const SizedBox(height: AppSpacing.x3),
          OutlinedButton(
            onPressed: onDecline,
            child: const Text('No comprar · abrir subasta'),
          ),
        ],
      ),
    );
  }
}

class _AuctionB extends StatelessWidget {
  const _AuctionB({
    required this.controller,
    required this.onBid,
    required this.onPass,
    super.key,
  });

  final TextEditingController controller;
  final VoidCallback onBid;
  final VoidCallback onPass;

  @override
  Widget build(BuildContext context) {
    return _FlowScaffold(
      key: key,
      step: '5 · SUBASTA',
      title: 'La mesa se picó',
      subtitle: 'Turno, puja mínima y deadline llegan confirmados. La UI sólo emite intención.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GameCard(
            background: AppPalette.violetSoft,
            borderColor: AppPalette.violet,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GamePill(label: 'TU TURNO DE PUJAR', color: AppPalette.coral),
                SizedBox(height: AppSpacing.x3),
                Text(
                  r'Puja actual · $ PLACEHOLDER',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                SizedBox(height: AppSpacing.x2),
                Text('Deadline confirmado · PLACEHOLDER'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x4),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Tu puja',
              filled: true,
              fillColor: AppPalette.surface,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          FilledButton(onPressed: onBid, child: const Text('Pujar')),
          const SizedBox(height: AppSpacing.x3),
          OutlinedButton(onPressed: onPass, child: const Text('Pasar')),
        ],
      ),
    );
  }
}

class _ReconnectB extends StatelessWidget {
  const _ReconnectB({
    required this.recovered,
    required this.onRetry,
    required this.onReturn,
    super.key,
  });

  final bool recovered;
  final VoidCallback onRetry;
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    final title = recovered ? 'Volviste a la partida' : 'La señal se cortó';
    final body = recovered
        ? 'Snapshot confirmado recuperado. Ninguna acción se repitió.'
        : 'Conservamos el último tablero confirmado en modo sólo lectura.';
    return _FlowScaffold(
      key: key,
      step: '6 · RECONECTAR',
      title: title,
      subtitle: body,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GameCard(
            background: recovered
                ? AppPalette.greenSoft
                : AppPalette.violetSoft,
            borderColor: recovered ? AppPalette.primary : AppPalette.violet,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  recovered
                      ? Icons.cloud_done_rounded
                      : Icons.cloud_off_rounded,
                  size: 44,
                  color: recovered ? AppPalette.primary : AppPalette.violet,
                ),
                const SizedBox(height: AppSpacing.x3),
                Text(
                  recovered ? 'CONTROL RECUPERADO' : 'ÚLTIMO ESTADO CONFIRMADO',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppSpacing.x2),
                const Text(
                  'Tablero PLACEHOLDER · sólo lectura durante reconciliación.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x5),
          FilledButton(
            onPressed: recovered ? onReturn : onRetry,
            child: Text(
              recovered ? 'Volver al tablero' : 'Reintentar conexión',
            ),
          ),
        ],
      ),
    );
  }
}
