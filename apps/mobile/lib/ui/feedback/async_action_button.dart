import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import 'interaction_feedback_state.dart';

class AsyncActionButton extends StatelessWidget {
  const AsyncActionButton({
    required this.label,
    required this.pendingLabel,
    required this.state,
    this.onPressed,
    this.disabledReason,
    super.key,
  });

  final String label;
  final String pendingLabel;
  final InteractionFeedbackState state;
  final VoidCallback? onPressed;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final isPending = state.isPending;
    final isActionable = state.isActionable && onPressed != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final reason = state == InteractionFeedbackState.disabled
        ? disabledReason
        : null;
    final semanticLabel = switch (state) {
      InteractionFeedbackState.pending =>
        '$pendingLabel. Esperando confirmación.',
      InteractionFeedbackState.disabled when reason != null =>
        '$label. No disponible: $reason',
      InteractionFeedbackState.uncertain =>
        '$label. Confirmando qué pasó antes de continuar.',
      InteractionFeedbackState.offline =>
        '$label. No disponible mientras se reconecta.',
      _ => label,
    };

    return Semantics(
      button: true,
      enabled: isActionable,
      label: semanticLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: AppSizes.primaryControlHeight,
            child: FilledButton(
              onPressed: isActionable ? onPressed : null,
              child: isPending
                  ? _PendingLabel(
                      label: pendingLabel,
                      reduceMotion: reduceMotion,
                    )
                  : Text(label),
            ),
          ),
          if (reason != null) ...[
            const SizedBox(height: AppSpacing.x2),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.inkSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PendingLabel extends StatelessWidget {
  const _PendingLabel({required this.label, required this.reduceMotion});

  final String label;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 18,
          child: reduceMotion
              ? const Icon(Icons.more_horiz_rounded, size: 18)
              : const CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: AppSpacing.x2),
        Flexible(child: Text(label)),
      ],
    );
  }
}
