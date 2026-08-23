import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
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
                  const SizedBox(height: AppSpacing.x3),
                  _BoardFrame(
                    currentPosition: currentPosition,
                    highlightedPosition: highlightedPosition,
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  DicePair(first: firstDie, second: secondDie),
                  if (movementSummary != null) ...[
                    const SizedBox(height: AppSpacing.x3),
                    Semantics(
                      liveRegion: true,
                      label: movementSummary,
                      child: Text(
                        movementSummary!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppPalette.inkSecondary,
                          fontWeight: FontWeight.w700,
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentPlayerLabel,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  roundLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.inkSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.x3),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  cashLabel,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: AppSpacing.x1),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_rounded, size: 16),
                    const SizedBox(width: AppSpacing.x1),
                    Flexible(
                      child: Text(
                        connectionLabel,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: AppPalette.inkSecondary),
                      ),
                    ),
                  ],
                ),
              ],
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
      child: AspectRatio(
        aspectRatio: 0.78,
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
                border: Border.all(color: AppPalette.ink, width: 1.5),
                borderRadius: BorderRadius.circular(AppRadius.control),
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
                    final reduceMotion = MediaQuery.disableAnimationsOf(
                      context,
                    );

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
                          color: isHighlighted
                              ? AppPalette.ritual
                              : AppPalette.surface,
                          border: Border.all(
                            color: isCurrent
                                ? AppPalette.primary
                                : AppPalette.ink,
                            width: isCurrent ? 2.5 : 0.6,
                          ),
                        ),
                        child: isCurrent
                            ? const Center(
                                child: Icon(
                                  Icons.circle,
                                  size: 10,
                                  color: AppPalette.primary,
                                  semanticLabel: null,
                                ),
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
                          Icon(
                            Icons.route_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 30,
                          ),
                          const SizedBox(height: AppSpacing.x2),
                          Text(
                            'TU JUGADA',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
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
