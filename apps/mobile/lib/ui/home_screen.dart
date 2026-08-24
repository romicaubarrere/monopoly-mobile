import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design_system/tokens.dart';
import '../design_system/visual_components.dart';

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
                  const _TopBar(),
                  const SizedBox(height: AppSpacing.x5),
                  const _HomeHero(),
                  const SizedBox(height: AppSpacing.x6),
                  const _PlayActions(),
                  const SizedBox(height: AppSpacing.x8),
                  const _BoardPreviewSection(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'ALMACÉN DE JUEGO',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.x3),
        Semantics(
          label: 'Estado de conexión: prototipo local',
          child: Container(
            width: AppSizes.minTouchTarget,
            height: AppSizes.minTouchTarget,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppPalette.surface,
              border: Border.all(color: AppPalette.ink, width: 1.2),
              borderRadius: BorderRadius.circular(AppRadius.sign),
            ),
            child: const Icon(Icons.wifi_tethering_rounded, semanticLabel: null),
          ),
        ),
      ],
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        PaperPanel(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x4,
            AppSpacing.x5,
            AppSpacing.x4,
            AppSpacing.x5,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AlmacenSign(),
              const SizedBox(height: AppSpacing.x6),
              Semantics(
                header: true,
                child: Text(
                  'Mesa chica.\nRivalidad grande.',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 0.98,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.x3),
              Text(
                'Una partida mobile con olor a papel impreso, carteles de almacén y caos familiar en la medida justa.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppPalette.inkSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AppSpacing.x5),
              Row(
                children: [
                  const StampBadge(label: 'hecho para picarse'),
                  const Spacer(),
                  const InkDoodle(),
                ],
              ),
            ],
          ),
        ),
        const Positioned(top: -7, left: 34, child: TapeMark(width: 64)),
        const Positioned(
          right: 12,
          top: 82,
          child: StampBadge(
            label: 'hoy se juega',
            color: AppPalette.wornBlue,
            angle: -0.045,
          ),
        ),
      ],
    );
  }
}

class _PlayActions extends StatelessWidget {
  const _PlayActions();

  @override
  Widget build(BuildContext context) {
    final primaryStyle = FilledButton.styleFrom(
      backgroundColor: AppPalette.primary,
      foregroundColor: AppPalette.surface,
      side: const BorderSide(color: AppPalette.burgundy, width: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sign),
      ),
      textStyle: const TextStyle(
        fontWeight: FontWeight.w900,
        letterSpacing: 0.7,
      ),
    );
    final secondaryStyle = OutlinedButton.styleFrom(
      foregroundColor: AppPalette.ink,
      backgroundColor: AppPalette.surface,
      side: const BorderSide(color: AppPalette.ink, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sign),
      ),
      textStyle: const TextStyle(
        fontWeight: FontWeight.w900,
        letterSpacing: 0.4,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          style: primaryStyle,
          onPressed: () {},
          child: const Text('Crear partida'),
        ),
        const SizedBox(height: AppSpacing.x3),
        OutlinedButton(
          style: secondaryStyle,
          onPressed: () {},
          child: const Text('Unirse con código'),
        ),
        const SizedBox(height: AppSpacing.x3),
        Text(
          'Crear primero. Unirse rápido. Nada de navegación que compita con la partida.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppPalette.inkSecondary,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _BoardPreviewSection extends StatelessWidget {
  const _BoardPreviewSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'UNA MESA, EN EL BOLSILLO',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const StampBadge(
              label: '40 casilleros',
              color: AppPalette.bottleGreen,
              angle: 0.02,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x2),
        Text(
          'Checkpoint estructural con 40 posiciones sintéticas. No contiene mapa, economía ni cartas DEC-065.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppPalette.inkSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: AppSpacing.x4),
        const _GameShellPreview(),
      ],
    );
  }
}

class _GameShellPreview extends StatelessWidget {
  const _GameShellPreview();

  @override
  Widget build(BuildContext context) {
    return PaperPanel(
      padding: const EdgeInsets.all(AppSpacing.x4),
      background: AppPalette.kraft,
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
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          const _BoardContextPreview(),
          const SizedBox(height: AppSpacing.x4),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.ink,
              foregroundColor: AppPalette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sign),
              ),
            ),
            onPressed: null,
            child: const Text('Tirar dados'),
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            'Disponible cuando exista una partida confirmada.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.inkSecondary,
            ),
          ),
        ],
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
          color: AppPalette.bottleGreen,
          border: Border.all(color: AppPalette.ink, width: 1.2),
          borderRadius: BorderRadius.circular(AppRadius.sign),
        ),
        child: Text(
          'TU TURNO · DEMO',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppPalette.surface,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
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
                    final color = switch (index % 8) {
                      0 => AppPalette.mustard,
                      1 => AppPalette.wornBlue,
                      2 => AppPalette.bottleGreen,
                      3 => AppPalette.primary,
                      _ => AppPalette.surface,
                    };

                    return Positioned(
                      left: position.left,
                      top: position.top,
                      width: position.width,
                      height: position.height,
                      child: Semantics(
                        label: 'Casillero sintético ${index + 1}',
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: index == 0 ? AppPalette.ritual : color,
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
                          const SizedBox(height: AppSpacing.x2),
                          Text(
                            'datos de muestra',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppPalette.inkSecondary,
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
