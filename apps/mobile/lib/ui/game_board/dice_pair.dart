import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';

class DicePair extends StatelessWidget {
  const DicePair({this.first, this.second, super.key});

  final int? first;
  final int? second;

  bool get _hasConfirmedResult => first != null && second != null;

  @override
  Widget build(BuildContext context) {
    final semanticLabel = _hasConfirmedResult
        ? 'Dados confirmados: $first y $second. Total ${first! + second!}.'
        : 'Dados listos para tirar.';

    return Semantics(
      container: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _DieFace(value: first, angle: -0.035),
          const SizedBox(width: AppSpacing.x3),
          _DieFace(value: second, angle: 0.028),
        ],
      ),
    );
  }
}

class _DieFace extends StatelessWidget {
  const _DieFace({required this.value, required this.angle});

  final int? value;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: 62,
        height: 62,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppPalette.surface,
          border: Border.all(color: AppPalette.ink, width: 1.8),
          borderRadius: BorderRadius.circular(AppRadius.control),
          boxShadow: const [
            BoxShadow(
              color: Color(0x30000000),
              offset: Offset(4, 4),
              blurRadius: 0,
            ),
          ],
        ),
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: AppPalette.paperEdge, width: 1),
            borderRadius: BorderRadius.circular(AppRadius.sign),
          ),
          child: Text(
            value?.toString() ?? '—',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppPalette.ink,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
