import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

class GameCard extends StatelessWidget {
  const GameCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(AppSpacing.x4),
    this.background = AppPalette.surface,
    this.borderColor = AppPalette.primary,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color background;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F2F23),
            offset: Offset(0, 8),
            blurRadius: 22,
          ),
        ],
      ),
      child: child,
    );
  }
}

class GamePill extends StatelessWidget {
  const GamePill({
    required this.label,
    super.key,
    this.color = AppPalette.violet,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x3,
        vertical: AppSpacing.x2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: AppPalette.surface),
            const SizedBox(width: AppSpacing.x1),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppPalette.surface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum CharacterIdentity { mani, almendra, phillip, manis, popon }

class CharacterArtSlot extends StatelessWidget {
  const CharacterArtSlot({required this.identity, super.key, this.size = 88});

  final CharacterIdentity identity;
  final double size;

  @override
  Widget build(BuildContext context) {
    final data = switch (identity) {
      CharacterIdentity.mani => (
        'MANÍ',
        'Perra clara, cruza labradora, orejas canela',
        Icons.pets_rounded,
        AppPalette.coralSoft,
      ),
      CharacterIdentity.almendra => (
        'ALMENDRA',
        'Gata tuxedo',
        Icons.pets_rounded,
        AppPalette.violetSoft,
      ),
      CharacterIdentity.phillip => (
        'PHILLIP',
        'Gato naranja atigrado',
        Icons.pets_rounded,
        AppPalette.creamStrong,
      ),
      CharacterIdentity.manis => (
        'MANÍS 1–4',
        'Mejoras · arte final pendiente',
        Icons.home_work_rounded,
        AppPalette.greenSoft,
      ),
      CharacterIdentity.popon => (
        'POPÓN',
        'Quinta mejora máxima · no mascota',
        Icons.workspace_premium_rounded,
        AppPalette.coralSoft,
      ),
    };

    return Semantics(
      label: '${data.$1}. ${data.$2}. Ilustración pendiente de foto fuente.',
      child: Container(
        width: size,
        constraints: BoxConstraints(minHeight: size),
        padding: const EdgeInsets.all(AppSpacing.x2),
        decoration: BoxDecoration(
          color: data.$4,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppPalette.ink.withValues(alpha: 0.18)),
        ),
        child: ExcludeSemantics(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(data.$3, color: AppPalette.primaryDeep, size: size * 0.3),
              const SizedBox(height: AppSpacing.x1),
              Text(
                data.$1,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppPalette.primaryDeep,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'ARTE PENDIENTE',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: AppPalette.inkSecondary, fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Compatibility layer for already accepted Layer-U surfaces. Historical class
// names remain source-compatible while rendering Direction B primitives.
class PaperPanel extends StatelessWidget {
  const PaperPanel({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(AppSpacing.x4),
    this.background = AppPalette.surface,
    this.borderColor = AppPalette.ink,
    this.rotation = 0,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color background;
  final Color borderColor;
  final double rotation;

  @override
  Widget build(BuildContext context) => GameCard(
    padding: padding,
    background: background,
    borderColor: borderColor,
    child: child,
  );
}

class AlmacenSign extends StatelessWidget {
  const AlmacenSign({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: 'Identidad principal de La Vuelta',
      child: GameCard(
        background: AppPalette.greenSoft,
        borderColor: AppPalette.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LA VUELTA',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppPalette.primaryDeep,
                fontWeight: FontWeight.w900,
                height: 0.95,
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              'JUGAR NOS UNE',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppPalette.violet,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StampBadge extends StatelessWidget {
  const StampBadge({
    required this.label,
    super.key,
    this.color = AppPalette.wornBlue,
    this.angle = 0,
  });

  final String label;
  final Color color;
  final double angle;

  @override
  Widget build(BuildContext context) =>
      GamePill(label: label.toUpperCase(), color: color);
}

class TapeMark extends StatelessWidget {
  const TapeMark({super.key, this.width = 48, this.angle = 0});

  final double width;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: 8,
        decoration: BoxDecoration(
          color: AppPalette.violet.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class InkDoodle extends StatelessWidget {
  const InkDoodle({super.key, this.size = 38});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(size: Size.square(size), painter: _SparkPainter()),
    );
  }
}

class _SparkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppPalette.coral
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.16;

    for (var index = 0; index < 8; index += 1) {
      final angle = math.pi * 2 * index / 8;
      canvas.drawLine(
        Offset(
          center.dx + math.cos(angle) * radius,
          center.dy + math.sin(angle) * radius,
        ),
        Offset(
          center.dx + math.cos(angle) * radius * 2.25,
          center.dy + math.sin(angle) * radius * 2.25,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
