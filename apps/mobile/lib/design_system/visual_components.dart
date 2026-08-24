import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

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
  Widget build(BuildContext context) {
    final panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor, width: 1.4),
        borderRadius: BorderRadius.circular(AppRadius.sign),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            offset: Offset(3, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: child,
    );

    if (rotation == 0) {
      return panel;
    }

    return Transform.rotate(angle: rotation, child: panel);
  }
}

class AlmacenSign extends StatelessWidget {
  const AlmacenSign({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: 'Monopoly de Romina',
      child: Transform.rotate(
        angle: -0.018,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x4,
            AppSpacing.x3,
            AppSpacing.x4,
            AppSpacing.x3,
          ),
          decoration: BoxDecoration(
            color: AppPalette.primary,
            border: Border.all(color: AppPalette.burgundy, width: 2),
            borderRadius: BorderRadius.circular(AppRadius.sign),
            boxShadow: const [
              BoxShadow(
                color: Color(0x30000000),
                offset: Offset(4, 5),
                blurRadius: 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MONOPOLY',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppPalette.surface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  height: 0.95,
                ),
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(
                'DE ROMINA',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppPalette.surface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                ),
              ),
            ],
          ),
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
    this.angle = 0.035,
  });

  final String label;
  final Color color;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x3,
          vertical: AppSpacing.x2,
        ),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: AppPalette.ink, width: 1.2),
          borderRadius: BorderRadius.circular(AppRadius.sign),
        ),
        child: Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppPalette.surface,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

class TapeMark extends StatelessWidget {
  const TapeMark({super.key, this.width = 48, this.angle = -0.08});

  final double width;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Transform.rotate(
        angle: angle,
        child: Container(
          width: width,
          height: 14,
          decoration: BoxDecoration(
            color: AppPalette.tape.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(2),
          ),
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
      child: CustomPaint(
        size: Size.square(size),
        painter: _InkDoodlePainter(),
      ),
    );
  }
}

class _InkDoodlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppPalette.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.2;
    canvas.drawCircle(center, radius, paint);

    for (var i = 0; i < 8; i += 1) {
      final angle = (math.pi * 2 * i) / 8;
      final start = Offset(
        center.dx + math.cos(angle) * radius * 1.5,
        center.dy + math.sin(angle) * radius * 1.5,
      );
      final end = Offset(
        center.dx + math.cos(angle) * radius * 2.15,
        center.dy + math.sin(angle) * radius * 2.15,
      );
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
