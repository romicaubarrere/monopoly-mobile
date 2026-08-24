import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';
import 'room_entry_models.dart';

class InlineStatusMessage extends StatelessWidget {
  const InlineStatusMessage({
    required this.message,
    this.isError = false,
    super.key,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppPalette.danger : AppPalette.info;

    return Semantics(
      liveRegion: true,
      child: PaperPanel(
        background: color.withValues(alpha: 0.08),
        borderColor: color,
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class PresetOptionCard extends StatelessWidget {
  const PresetOptionCard({
    required this.preset,
    required this.isSelected,
    required this.onSelected,
    super.key,
  });

  final PresetViewData preset;
  final bool isSelected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onSelected != null,
      selected: isSelected,
      label:
          '${preset.title}. ${preset.durationLabel}. ${preset.endConditionLabel}',
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            PaperPanel(
              background: isSelected
                  ? const Color(0xFFE7F0E6)
                  : AppPalette.surface,
              borderColor: isSelected
                  ? AppPalette.bottleGreen
                  : AppPalette.inkSecondary,
              padding: const EdgeInsets.all(AppSpacing.x4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: AppSpacing.x2,
                          runSpacing: AppSpacing.x2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              preset.title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            if (preset.tone == PresetTone.experimental)
                              const _ExperimentalBadge(),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.x2),
                        Text(
                          preset.durationLabel,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: AppPalette.wornBlue,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.x1),
                        Text(preset.endConditionLabel),
                        const SizedBox(height: AppSpacing.x2),
                        Text(
                          preset.differenceSummary,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppPalette.inkSecondary,
                                height: 1.35,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x3),
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: isSelected
                        ? AppPalette.bottleGreen
                        : AppPalette.inkSecondary,
                    semanticLabel: null,
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Positioned(right: 22, top: -6, child: TapeMark(width: 54)),
          ],
        ),
      ),
    );
  }
}

class _ExperimentalBadge extends StatelessWidget {
  const _ExperimentalBadge();

  @override
  Widget build(BuildContext context) {
    return const StampBadge(
      label: 'Experimental',
      color: AppPalette.wornBlue,
      angle: -0.02,
    );
  }
}
