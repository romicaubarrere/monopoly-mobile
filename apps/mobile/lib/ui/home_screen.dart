import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design_system/tokens.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 375;
            final gutter = compact ? AppSpacing.x3 : AppSpacing.x5;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                gutter,
                AppSpacing.x4,
                gutter,
                AppSpacing.x8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Eyebrow(),
                  const SizedBox(height: AppSpacing.x4),
                  Semantics(
                    header: true,
                    child: Text(
                      'Una partida que entra en una mano.',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900, height: 1.05),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  Text(
                    'Mobile-first, competitiva y legible. El tablero da contexto; las decisiones viven cerca del pulgar.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppPalette.inkSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x6),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Crear partida'),
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  OutlinedButton(
                    onPressed: () {},
                    child: const Text('Unirse con código'),
                  ),
                  const SizedBox(height: AppSpacing.x8),
                  Text(
                    'Shell de partida',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Text(
                    'Checkpoint estructural con 40 posiciones sintéticas. No contiene mapa, economía ni cartas DEC-065.',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: AppPalette.inkSecondary),
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  const _GameShellPreview(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x3,
            vertical: AppSpacing.x2,
          ),
          decoration: BoxDecoration(
            color: AppPalette.ink,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Text(
            'M1 · UI SHELL',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppPalette.surface,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const Spacer(),
        Semantics(
          label: 'Estado de conexión: prototipo local',
          child: Icon(Icons.wifi_tethering_rounded, semanticLabel: null),
        ),
      ],
    );
  }
}

class _GameShellPreview extends StatelessWidget {
  const _GameShellPreview();

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppPalette.ink, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Flexible(child: _TurnBadge()),
                const SizedBox(width: AppSpacing.x2),
                Flexible(
                  child: Text(
                    'Saldo · \$ —',
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x4),
            const _BoardContextPreview(),
            const SizedBox(height: AppSpacing.x4),
            FilledButton(onPressed: null, child: const Text('Tirar dados')),
            const SizedBox(height: AppSpacing.x2),
            Text(
              'Disponible cuando exista una partida confirmada.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppPalette.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnBadge extends StatelessWidget {
  const _TurnBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Turno de ejemplo, sin estado autoritativo',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x3,
          vertical: AppSpacing.x2,
        ),
        decoration: BoxDecoration(
          color: AppPalette.info,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'TU TURNO · DEMO',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _BoardContextPreview extends StatelessWidget {
  const _BoardContextPreview();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Tablero estructural de demostración, 40 casilleros sintéticos',
      child: AspectRatio(
        aspectRatio: 0.78,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final tileWidth = width / 11;
            final edge = math.min(34.0, tileWidth * 1.25);
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

                    return Positioned(
                      left: position.left,
                      top: position.top,
                      width: position.width,
                      height: position.height,
                      child: Semantics(
                        label: 'Casillero sintético ${index + 1}',
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: index == 0
                                ? AppPalette.ritual
                                : AppPalette.surface,
                            border: Border.all(
                              color: AppPalette.ink,
                              width: 0.6,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.all(edge + AppSpacing.x2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.casino_outlined,
                            size: 34,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: AppSpacing.x2),
                          Text(
                            'BOARD COMO CONTEXTO',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
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
