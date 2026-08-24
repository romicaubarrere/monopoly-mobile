import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';
import 'economy_receipt.dart';

enum SystemEventTone { neutral, positive, warning, info }

class SystemEventToast extends StatelessWidget {
  const SystemEventToast.confirmed({
    required this.title,
    required this.detail,
    this.categoryLabel = 'EVENTO CONFIRMADO',
    this.tone = SystemEventTone.neutral,
    this.economyDelta,
    this.economySummary,
    this.resultingBalanceLabel,
    this.acknowledgementLabel,
    this.onAcknowledge,
    super.key,
  }) : assert(
         (economyDelta == null) == (economySummary == null),
         'economyDelta and economySummary must be supplied together',
       ),
       assert(
         (acknowledgementLabel == null) == (onAcknowledge == null),
         'acknowledgementLabel and onAcknowledge must be supplied together',
       );

  final String title;
  final String detail;
  final String categoryLabel;
  final SystemEventTone tone;
  final int? economyDelta;
  final String? economySummary;
  final String? resultingBalanceLabel;
  final String? acknowledgementLabel;
  final VoidCallback? onAcknowledge;

  String? get _deltaLabel {
    final delta = economyDelta;
    if (delta == null) return null;
    if (delta > 0) return '+\$$delta';
    if (delta < 0) return '-\$${delta.abs()}';
    return '\$0';
  }

  String get _semanticLabel {
    return [
      categoryLabel,
      title,
      detail,
      if (_deltaLabel != null) 'Cambio confirmado: $_deltaLabel.',
      ?economySummary,
      ?resultingBalanceLabel,
      if (acknowledgementLabel != null)
        'Acción disponible: $acknowledgementLabel.',
    ].join(' ');
  }

  Color get _accentColor {
    return switch (tone) {
      SystemEventTone.neutral => AppPalette.ink,
      SystemEventTone.positive => AppPalette.bottleGreen,
      SystemEventTone.warning => AppPalette.burgundy,
      SystemEventTone.info => AppPalette.wornBlue,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: _semanticLabel,
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PaperPanel(
            background: AppPalette.canvas,
            padding: const EdgeInsets.all(AppSpacing.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.x3,
                  runSpacing: AppSpacing.x2,
                  children: [
                    StampBadge(
                      label: categoryLabel,
                      color: _accentColor,
                      angle: -0.018,
                    ),
                    const InkDoodle(size: 30),
                  ],
                ),
                const SizedBox(height: AppSpacing.x4),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900, height: 1.05),
                ),
                const SizedBox(height: AppSpacing.x2),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: AppPalette.inkSecondary, height: 1.35),
                ),
                if (economyDelta != null && economySummary != null) ...[
                  const SizedBox(height: AppSpacing.x4),
                  ExcludeSemantics(
                    child: EconomyReceipt.confirmed(
                      delta: economyDelta!,
                      summary: economySummary!,
                      resultingBalanceLabel: resultingBalanceLabel,
                    ),
                  ),
                ],
                if (onAcknowledge != null && acknowledgementLabel != null) ...[
                  const SizedBox(height: AppSpacing.x4),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(
                        double.infinity,
                        AppSizes.minTouchTarget,
                      ),
                      foregroundColor: AppPalette.ink,
                      side: const BorderSide(color: AppPalette.ink, width: 1.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sign),
                      ),
                    ),
                    onPressed: onAcknowledge,
                    child: Text(acknowledgementLabel!),
                  ),
                ],
              ],
            ),
          ),
          const Positioned(top: -6, right: 28, child: TapeMark(width: 54)),
        ],
      ),
    );
  }
}
