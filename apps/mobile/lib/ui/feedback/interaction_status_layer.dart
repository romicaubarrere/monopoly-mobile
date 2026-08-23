import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import 'interaction_feedback_state.dart';

class InteractionStatusLayer extends StatelessWidget {
  const InteractionStatusLayer({required this.state, this.message, super.key});

  final InteractionFeedbackState state;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final presentation = _presentationFor(state);
    if (presentation == null) return const SizedBox.shrink();

    final text = message ?? presentation.message;

    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.x3),
        decoration: BoxDecoration(
          color: presentation.color.withValues(alpha: 0.08),
          border: Border.all(color: presentation.color),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              presentation.icon,
              color: presentation.color,
              semanticLabel: null,
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: presentation.color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _StatusPresentation? _presentationFor(InteractionFeedbackState state) {
    return switch (state) {
      InteractionFeedbackState.pending => const _StatusPresentation(
        message: 'Esperando confirmación…',
        icon: Icons.hourglass_top_rounded,
        color: AppPalette.info,
      ),
      InteractionFeedbackState.rejected => const _StatusPresentation(
        message: 'No se pudo aplicar esa acción.',
        icon: Icons.error_outline_rounded,
        color: AppPalette.danger,
      ),
      InteractionFeedbackState.stale => const _StatusPresentation(
        message: 'Esto cambió mientras mirabas.',
        icon: Icons.sync_problem_rounded,
        color: AppPalette.info,
      ),
      InteractionFeedbackState.uncertain => const _StatusPresentation(
        message: 'Confirmando qué pasó…',
        icon: Icons.manage_search_rounded,
        color: AppPalette.info,
      ),
      InteractionFeedbackState.offline => const _StatusPresentation(
        message: 'Reconectando…',
        icon: Icons.wifi_off_rounded,
        color: AppPalette.info,
      ),
      _ => null,
    };
  }
}

class _StatusPresentation {
  const _StatusPresentation({
    required this.message,
    required this.icon,
    required this.color,
  });

  final String message;
  final IconData icon;
  final Color color;
}
