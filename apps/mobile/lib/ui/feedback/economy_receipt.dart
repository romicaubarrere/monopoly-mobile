import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';

class EconomyReceipt extends StatelessWidget {
  const EconomyReceipt.confirmed({
    required this.delta,
    required this.summary,
    this.resultingBalanceLabel,
    super.key,
  });

  final int delta;
  final String summary;
  final String? resultingBalanceLabel;

  String get _deltaLabel {
    if (delta > 0) return '+\$$delta';
    if (delta < 0) return '-\$${delta.abs()}';
    return '\$0';
  }

  @override
  Widget build(BuildContext context) {
    final deltaColor = delta < 0
        ? AppPalette.danger
        : delta > 0
        ? AppPalette.info
        : AppPalette.ink;
    final semanticLabel = [
      'Cambio confirmado: $_deltaLabel.',
      summary,
      ?resultingBalanceLabel,
    ].join(' ');

    return Semantics(
      container: true,
      liveRegion: true,
      label: semanticLabel,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.x3),
        decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: AppPalette.inkSecondary),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _deltaLabel,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: deltaColor,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (resultingBalanceLabel != null) ...[
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      resultingBalanceLabel!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.inkSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
