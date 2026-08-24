import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';
import '../feedback/economy_receipt.dart';

class FreeParkingBreakdownItem {
  const FreeParkingBreakdownItem({
    required this.label,
    required this.amountLabel,
  });

  final String label;
  final String amountLabel;
}

class FreeParkingEventSurface extends StatelessWidget {
  const FreeParkingEventSurface.confirmed({
    required this.confirmedAmount,
    super.key,
    this.resultingBalanceLabel,
    this.breakdown = const [],
  });

  final int confirmedAmount;
  final String? resultingBalanceLabel;
  final List<FreeParkingBreakdownItem> breakdown;

  String get _amountLabel => '\$$confirmedAmount';

  String get _summary => 'Te llevaste $_amountLabel del pozo';

  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final semanticDetails = breakdown
        .map((item) => '${item.label}: ${item.amountLabel}')
        .join('. ');
    final semanticLabel = [
      'Estacionamiento Libre.',
      'Cobro confirmado.',
      '$_summary.',
      ?resultingBalanceLabel,
      if (semanticDetails.isNotEmpty) semanticDetails,
    ].join(' ');

    return Material(
      color: AppPalette.canvas,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x4,
            AppSpacing.x4,
            AppSpacing.x4,
            AppSpacing.x6,
          ),
          child: Semantics(
            container: true,
            liveRegion: true,
            label: semanticLabel,
            excludeSemantics: true,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: reducedMotion ? 1 : 0.98, end: 1),
              duration: reducedMotion ? Duration.zero : AppMotion.receipt,
              curve: Curves.easeOutCubic,
              builder: (context, scale, child) => Transform.scale(
                scale: scale,
                alignment: Alignment.topCenter,
                child: child,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  PaperPanel(
                    background: AppPalette.surface,
                    borderColor: AppPalette.mustard,
                    rotation: -0.004,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: AppSpacing.x2,
                          runSpacing: AppSpacing.x2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: const [
                            StampBadge(
                              label: 'ESTACIONAMIENTO LIBRE',
                              color: AppPalette.bottleGreen,
                              angle: -0.018,
                            ),
                            StampBadge(
                              label: 'CONFIRMADO',
                              color: AppPalette.mustard,
                              angle: 0.014,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.x5),
                        Text(
                          'COBRO DEL POZO',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: AppPalette.ink,
                                fontWeight: FontWeight.w900,
                                height: 1.02,
                                letterSpacing: 0.6,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.x2),
                        Text(
                          'El movimiento ya fue confirmado. Este recibo muestra únicamente el resultado aplicado.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: AppPalette.inkSecondary,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.x4),
                        EconomyReceipt.confirmed(
                          delta: confirmedAmount,
                          summary: _summary,
                          resultingBalanceLabel: resultingBalanceLabel,
                        ),
                        if (breakdown.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.x4),
                          _ConfirmedBreakdown(items: breakdown),
                        ],
                        const SizedBox(height: AppSpacing.x3),
                        Text(
                          'Sin acción pendiente',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: AppPalette.bottleGreen,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.4,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const Positioned(
                    right: 30,
                    top: -7,
                    child: TapeMark(width: 62, angle: 0.06),
                  ),
                  const Positioned(
                    right: -5,
                    bottom: -10,
                    child: InkDoodle(size: 34),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmedBreakdown extends StatelessWidget {
  const _ConfirmedBreakdown({required this.items});

  final List<FreeParkingBreakdownItem> items;

  @override
  Widget build(BuildContext context) {
    return PaperPanel(
      background: AppPalette.kraft,
      borderColor: AppPalette.paperEdge,
      padding: const EdgeInsets.all(AppSpacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'DETALLE CONFIRMADO',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppPalette.burgundy,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          for (var index = 0; index < items.length; index++) ...[
            _BreakdownRow(item: items[index]),
            if (index != items.length - 1)
              const Divider(color: AppPalette.paperEdge, height: AppSpacing.x4),
          ],
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.item});

  final FreeParkingBreakdownItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            item.label,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppPalette.ink, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: AppSpacing.x3),
        Flexible(
          child: Text(
            item.amountLabel,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppPalette.ink,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
