import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';
import '../feedback/async_action_button.dart';
import '../feedback/interaction_feedback_state.dart';
import 'dice_pair.dart';

class BoardTurnSurface extends StatelessWidget {
  const BoardTurnSurface({
    required this.currentPlayerLabel,
    required this.roundLabel,
    required this.cashLabel,
    required this.connectionLabel,
    required this.currentPosition,
    required this.rollState,
    this.firstDie,
    this.secondDie,
    this.highlightedPosition,
    this.movementSummary,
    this.onRoll,
    this.rollDisabledReason,
    super.key,
  }) : assert(currentPosition >= 0 && currentPosition < 40),
       assert(
         highlightedPosition == null ||
             (highlightedPosition >= 0 && highlightedPosition < 40),
       );

  final String currentPlayerLabel;
  final String roundLabel;
  final String cashLabel;
  final String connectionLabel;
  final int currentPosition;
  final InteractionFeedbackState rollState;
  final int? firstDie;
  final int? secondDie;
  final int? highlightedPosition;
  final String? movementSummary;
  final VoidCallback? onRoll;
  final String? rollDisabledReason;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 375;
            final gutter = compact ? AppSpacing.x3 : AppSpacing.x4;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                gutter,
                AppSpacing.x3,
                gutter,
                AppSpacing.x6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TurnHud(
                    currentPlayerLabel: currentPlayerLabel,
                    roundLabel: roundLabel,
                    cashLabel: cashLabel,
                    connectionLabel: connectionLabel,
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  _BoardFrame(
                    currentPosition: currentPosition,
                    highlightedPosition: highlightedPosition,
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  const Center(
                    child: StampBadge(
                      label: 'Dados de la mesa',
                      color: AppPalette.wornBlue,
                      angle: -0.02,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  DicePair(first: firstDie, second: secondDie),
                  if (movementSummary != null) ...[
                    const SizedBox(height: AppSpacing.x3),
                    Semantics(
                      liveRegion: true,
                      label: movementSummary,
                      child: PaperPanel(
                        background: AppPalette.surface,
                        borderColor: AppPalette.paperEdge,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.x3,
                          vertical: AppSpacing.x2,
                        ),
                        child: Text(
                          movementSummary!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppPalette.inkSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.x4),
                  AsyncActionButton(
                    label: 'Tirar dados',
                    pendingLabel: 'Tirando…',
                    state: rollState,
                    onPressed: onRoll,
                    disabledReason: rollDisabledReason,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TurnHud extends StatelessWidget {
  const _TurnHud({
    required this.currentPlayerLabel,
    required this.roundLabel,
    required this.cashLabel,
    required this.connectionLabel,
  });

  final String currentPlayerLabel;
  final String roundLabel;
  final String cashLabel;
  final String connectionLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          'Turno: $currentPlayerLabel. $roundLabel. Saldo: $cashLabel. Conexión: $connectionLabel.',
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PaperPanel(
            background: AppPalette.surface,
            borderColor: AppPalette.burgundy,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x4,
              AppSpacing.x5,
              AppSpacing.x4,
              AppSpacing.x4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TURNO EN EL MOSTRADOR',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppPalette.primary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  currentPlayerLabel,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: AppSpacing.x3),
                Wrap(
                  spacing: AppSpacing.x2,
                  runSpacing: AppSpacing.x2,
                  children: [
                    _HudTag(
                      icon: Icons.repeat_rounded,
                      label: roundLabel,
                      color: AppPalette.kraft,
                    ),
                    _HudTag(
                      icon: Icons.payments_outlined,
                      label: cashLabel,
                      color: const Color(0xFFE7F0E6),
                      tabular: true,
                    ),
                    _HudTag(
                      icon: Icons.wifi_rounded,
                      label: connectionLabel,
                      color: const Color(0xFFE7EEF1),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Positioned(right: 22, top: -5, child: TapeMark(width: 62)),
        ],
      ),
    );
  }
}

class _HudTag extends StatelessWidget {
  const _HudTag({
    required this.icon,
    required this.label,
    required this.color,
    this.tabular = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool tabular;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: AppSpacing.x2,
      ),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: AppPalette.ink, width: 1),
        borderRadius: BorderRadius.circular(AppRadius.sign),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: AppSpacing.x1),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: tabular
                    ? const [FontFeature.tabularFigures()]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardFrame extends StatelessWidget {
  const _BoardFrame({
    required this.currentPosition,
    required this.highlightedPosition,
  });

  final int currentPosition;
  final int? highlightedPosition;

  @override
  Widget build(BuildContext context) {
    final summary = highlightedPosition == null
        ? 'Tablero de 40 posiciones. Ficha actual en la posición ${currentPosition + 1}.'
        : 'Tablero de 40 posiciones. Ficha actual en la posición ${currentPosition + 1}. Destino resaltado: posición ${highlightedPosition! + 1}.';

    return Semantics(
      container: true,
      label: summary,
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AspectRatio(
            aspectRatio: 0.78,
            child: PaperPanel(
              background: AppPalette.kraft,
              borderColor: AppPalette.ink,
              padding: const EdgeInsets.all(AppSpacing.x2),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final height = constraints.maxHeight;
                  final tileWidth = width / 11;
                  final edge = math.min(36.0, tileWidth * 1.25);
                  final sideHeight = (height - (edge * 2)) / 9;

                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppPalette.canvas,
                      border: Border.all(color: AppPalette.ink, width: 1.2),
                      borderRadius: BorderRadius.circular(AppRadius.sign),
                    ),
                    child: Stack(
                      children: [
                        ...List.generate(40, (index) {
                          final position = _tilePosition(
                            index: index,
                            width: width,
                            height: height,
                            tileWidth: tileWidth,
                            edge: edge,
                            sideHeight: sideHeight,
                          );
                          final isCurrent = index == currentPosition;
                          final isHighlighted = index == highlightedPosition;
                          final isCorner = index % 10 == 0;
                          final reduceMotion = MediaQuery.disableAnimationsOf(
                            context,
                          );
                          final tileColor = switch ((
                            isHighlighted,
                            isCorner,
                          )) {
                            (true, _) => AppPalette.mustard,
                            (false, true) => AppPalette.kraft,
                            _ => AppPalette.surface,
                          };

                          return Positioned(
                            left: position.left,
                            top: position.top,
                            width: position.width,
                            height: position.height,
                            child: AnimatedContainer(
                              key: ValueKey('board-tile-$index'),
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              decoration: BoxDecoration(
                                color: tileColor,
                                border: Border.all(
                                  color: isCurrent
                                      ? AppPalette.burgundy
                                      : AppPalette.ink,
                                  width: isCurrent ? 2.5 : 0.65,
                                ),
                              ),
                              child: isCurrent
                                  ? const Center(
                                      child: _CurrentTokenMarker(),
                                    )
                                  : null,
                            ),
                          );
                        }),
                        Center(
                          child: Padding(
                            padding: EdgeInsets.all(edge + AppSpacing.x3),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const StampBadge(
                                  label: 'Partida en curso',
                                  color: AppPalette.bottleGreen,
                                  angle: 0.018,
                                ),
                                const SizedBox(height: AppSpacing.x3),
                                Text(
                                  'TABLERO\nEN JUEGO',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.1,
                                        height: 0.95,
                                      ),
                                ),
                                const SizedBox(height: AppSpacing.x2),
                                Text(
                                  '40 posiciones · estado confirmado',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: AppPalette.inkSecondary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const Positioned(left: 24, top: -5, child: TapeMark(width: 58)),
          const Positioned(right: 18, bottom: 16, child: InkDoodle(size: 28)),
        ],
      ),
    );
  }

  _TilePosition _tilePosition({
    required int index,
    required double width,
    required double height,
    required double tileWidth,
    required double edge,
    required double sideHeight,
  }) {
    if (index < 11) {
      return _TilePosition(
        left: index * tileWidth,
        top: 0,
        width: tileWidth,
        height: edge,
      );
    }

    if (index < 20) {
      final sideIndex = index - 11;
      return _TilePosition(
        left: width - edge,
        top: edge + (sideIndex * sideHeight),
        width: edge,
        height: sideHeight,
      );
    }

    if (index < 31) {
      final bottomIndex = index - 20;
      return _TilePosition(
        left: width - ((bottomIndex + 1) * tileWidth),
        top: height - edge,
        width: tileWidth,
        height: edge,
      );
    }

    final sideIndex = index - 31;
    return _TilePosition(
      left: 0,
      top: height - edge - ((sideIndex + 1) * sideHeight),
      width: edge,
      height: sideHeight,
    );
  }
}

class _CurrentTokenMarker extends StatelessWidget {
  const _CurrentTokenMarker();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: AppPalette.burgundy,
          shape: BoxShape.circle,
          border: Border.all(color: AppPalette.surface, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              offset: Offset(1, 1),
              blurRadius: 0,
            ),
          ],
        ),
      ),
    );
  }
}

class _TilePosition {
  const _TilePosition({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}
