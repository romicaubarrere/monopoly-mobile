import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';

class EmoteOption {
  const EmoteOption({
    required this.id,
    required this.label,
    required this.semanticLabel,
    this.artwork,
  });

  final String id;
  final String label;
  final String semanticLabel;
  final Widget? artwork;
}

class EmoteTray extends StatelessWidget {
  const EmoteTray({
    required this.options,
    required this.onSelected,
    super.key,
    this.enabled = true,
    this.disabledReason,
    this.cooldownLabel,
  }) : assert(options.length >= 6 && options.length <= 8);

  final List<EmoteOption> options;
  final ValueChanged<String> onSelected;
  final bool enabled;
  final String? disabledReason;
  final String? cooldownLabel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x4,
          AppSpacing.x4,
          AppSpacing.x4,
          AppSpacing.x6,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            PaperPanel(
              background: AppPalette.surface,
              borderColor: AppPalette.burgundy,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x4,
                AppSpacing.x5,
                AppSpacing.x4,
                AppSpacing.x4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'REACCIONES DE LA MESA',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppPalette.primary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  Text(
                    'Elegí una reacción rápida. No hay texto libre.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppPalette.inkSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (cooldownLabel != null || (!enabled && disabledReason != null)) ...[
                    const SizedBox(height: AppSpacing.x3),
                    _StatusNote(
                      label: cooldownLabel ?? disabledReason!,
                      icon: cooldownLabel != null
                          ? Icons.hourglass_bottom_rounded
                          : Icons.info_outline_rounded,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.x4),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth < 300 ? 2 : 3;
                      final spacing = AppSpacing.x2;
                      final itemWidth =
                          (constraints.maxWidth - spacing * (columns - 1)) /
                          columns;

                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: [
                          for (final option in options)
                            SizedBox(
                              width: itemWidth,
                              child: _EmoteChoice(
                                option: option,
                                enabled: enabled,
                                onPressed: enabled
                                    ? () => onSelected(option.id)
                                    : null,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const Positioned(right: 22, top: -5, child: TapeMark(width: 62)),
          ],
        ),
      ),
    );
  }
}

class BoardEmoteAccess extends StatelessWidget {
  const BoardEmoteAccess({
    required this.options,
    required this.onSelected,
    super.key,
    this.enabled = true,
    this.disabledReason,
    this.cooldownLabel,
  });

  final List<EmoteOption> options;
  final ValueChanged<String> onSelected;
  final bool enabled;
  final String? disabledReason;
  final String? cooldownLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: enabled
          ? 'Abrir reacciones rápidas'
          : 'Reacciones rápidas no disponibles. ${disabledReason ?? cooldownLabel ?? 'Esperá un momento'}',
      child: OutlinedButton.icon(
        onPressed: enabled
            ? () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: AppPalette.canvas,
                  builder: (context) => EmoteTray(
                    options: options,
                    onSelected: (id) {
                      Navigator.of(context).pop();
                      onSelected(id);
                    },
                    cooldownLabel: cooldownLabel,
                  ),
                )
            : null,
        icon: const Icon(Icons.chat_bubble_outline_rounded),
        label: const Text('Reacciones'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(AppSizes.minTouchTarget, AppSizes.minTouchTarget),
          foregroundColor: AppPalette.ink,
          side: const BorderSide(color: AppPalette.ink),
        ),
      ),
    );
  }
}

class EmoteBubble extends StatelessWidget {
  const EmoteBubble({
    required this.senderLabel,
    required this.option,
    super.key,
    this.visible = true,
  });

  final String senderLabel;
  final EmoteOption option;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        child: Semantics(
          liveRegion: true,
          label: '$senderLabel reaccionó: ${option.semanticLabel}',
          excludeSemantics: true,
          child: PaperPanel(
            background: AppPalette.kraft,
            borderColor: AppPalette.ink,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x3,
              vertical: AppSpacing.x2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (option.artwork != null) ...[
                  SizedBox.square(dimension: 28, child: option.artwork),
                  const SizedBox(width: AppSpacing.x2),
                ],
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        senderLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppPalette.inkSecondary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        option.label,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppPalette.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmoteChoice extends StatelessWidget {
  const _EmoteChoice({
    required this.option,
    required this.enabled,
    required this.onPressed,
  });

  final EmoteOption option;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: option.semanticLabel,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSizes.minTouchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x2,
            vertical: AppSpacing.x2,
          ),
          foregroundColor: AppPalette.ink,
          side: const BorderSide(color: AppPalette.ink),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (option.artwork != null) ...[
              SizedBox.square(dimension: 32, child: option.artwork),
              const SizedBox(height: AppSpacing.x1),
            ],
            Text(
              option.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusNote extends StatelessWidget {
  const _StatusNote({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x3,
        vertical: AppSpacing.x2,
      ),
      decoration: BoxDecoration(
        color: AppPalette.kraft,
        border: Border.all(color: AppPalette.paperEdge),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppPalette.inkSecondary),
          const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.inkSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
