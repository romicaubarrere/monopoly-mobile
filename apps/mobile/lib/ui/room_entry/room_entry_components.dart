import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
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
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.x3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
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
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${preset.title}. ${preset.durationLabel}. ${preset.endConditionLabel}',
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: AnimatedContainer(
          duration: AppMotion.press,
          padding: const EdgeInsets.all(AppSpacing.x4),
          decoration: BoxDecoration(
            color: AppPalette.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: isSelected ? scheme.primary : AppPalette.inkSecondary,
              width: isSelected ? 2 : 1,
            ),
          ),
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
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (preset.tone == PresetTone.experimental)
                          const _ExperimentalBadge(),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.x2),
                    Text(
                      preset.durationLabel,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppPalette.info,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x1),
                    Text(preset.endConditionLabel),
                    const SizedBox(height: AppSpacing.x2),
                    Text(
                      preset.differenceSummary,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: isSelected ? scheme.primary : AppPalette.inkSecondary,
                semanticLabel: null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExperimentalBadge extends StatelessWidget {
  const _ExperimentalBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: AppSpacing.x1,
      ),
      decoration: BoxDecoration(
        color: AppPalette.ritual.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'EXPERIMENTAL',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppPalette.ink,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
