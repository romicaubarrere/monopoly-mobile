import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';
import '../feedback/interaction_feedback_state.dart';
import '../feedback/interaction_status_layer.dart';

enum CuchaSurfaceState {
  available,
  pending,
  confirmed,
  rejected,
  stale,
  uncertain,
  offline,
}

class CuchaActionView {
  const CuchaActionView({
    required this.id,
    required this.label,
    required this.pendingLabel,
    this.detail,
  });

  final String id;
  final String label;
  final String pendingLabel;
  final String? detail;
}

class CuchaSurface extends StatelessWidget {
  const CuchaSurface({
    required this.statusLabel,
    required this.actions,
    required this.state,
    this.entryReason,
    this.pendingActionId,
    this.confirmedMessage,
    this.statusMessage,
    this.characterArtwork,
    this.onAction,
    super.key,
  });

  final String statusLabel;
  final String? entryReason;
  final List<CuchaActionView> actions;
  final CuchaSurfaceState state;
  final String? pendingActionId;
  final String? confirmedMessage;
  final String? statusMessage;
  final Widget? characterArtwork;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) {
    final feedbackState = _feedbackState;

    return Material(
      color: AppPalette.canvas,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x4,
            AppSpacing.x3,
            AppSpacing.x4,
            AppSpacing.x6,
          ),
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'A la Cucha. $statusLabel',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _MandatoryHandle(),
                const SizedBox(height: AppSpacing.x3),
                const _CuchaHeader(),
                const SizedBox(height: AppSpacing.x3),
                if (entryReason != null && entryReason!.trim().isNotEmpty) ...[
                  _EntryReason(reason: entryReason!),
                  const SizedBox(height: AppSpacing.x3),
                ],
                _CharacterSlot(artwork: characterArtwork),
                const SizedBox(height: AppSpacing.x3),
                _StatusTicket(statusLabel: statusLabel),
                if (feedbackState != null) ...[
                  const SizedBox(height: AppSpacing.x3),
                  InteractionStatusLayer(
                    state: feedbackState,
                    message: statusMessage ?? _defaultStatusMessage,
                  ),
                ],
                if (state == CuchaSurfaceState.confirmed) ...[
                  const SizedBox(height: AppSpacing.x3),
                  _ConfirmedTicket(
                    message:
                        confirmedMessage ??
                        'La salida quedó confirmada por la partida.',
                  ),
                ],
                const SizedBox(height: AppSpacing.x4),
                if (actions.isEmpty)
                  const _NoActionsPlaceholder()
                else
                  for (var index = 0; index < actions.length; index++) ...[
                    _CuchaActionButton(
                      action: actions[index],
                      surfaceState: state,
                      pendingActionId: pendingActionId,
                      onPressed: onAction,
                    ),
                    if (index != actions.length - 1)
                      const SizedBox(height: AppSpacing.x2),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  InteractionFeedbackState? get _feedbackState => switch (state) {
    CuchaSurfaceState.available || CuchaSurfaceState.confirmed => null,
    CuchaSurfaceState.pending => InteractionFeedbackState.pending,
    CuchaSurfaceState.rejected => InteractionFeedbackState.rejected,
    CuchaSurfaceState.stale => InteractionFeedbackState.stale,
    CuchaSurfaceState.uncertain => InteractionFeedbackState.uncertain,
    CuchaSurfaceState.offline => InteractionFeedbackState.offline,
  };

  String get _defaultStatusMessage => switch (state) {
    CuchaSurfaceState.pending => 'Esperando confirmación. Todavía no se consumió efectivo ni carta en esta presentación.',
    CuchaSurfaceState.rejected => 'La partida no confirmó esa opción. Conservamos el último estado confirmado.',
    CuchaSurfaceState.stale =>
      'Las opciones cambiaron. Esperando el estado actualizado de la partida.',
    CuchaSurfaceState.uncertain =>
      'Confirmando qué pasó antes de permitir otra opción equivalente.',
    CuchaSurfaceState.offline =>
      'Reconectando antes de habilitar una nueva decisión.',
    _ => '',
  };
}

class _CuchaHeader extends StatelessWidget {
  const _CuchaHeader();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        PaperPanel(
          background: AppPalette.surface,
          borderColor: AppPalette.wornBlue,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x4,
            AppSpacing.x4,
            AppSpacing.x4,
            AppSpacing.x3,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'A LA CUCHA',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: AppPalette.wornBlue,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            height: 1,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.x2),
                    Text(
                      'Elegí entre las opciones que la partida confirma como válidas.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.inkSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              const InkDoodle(size: 34),
            ],
          ),
        ),
        const Positioned(
          right: 54,
          top: -6,
          child: TapeMark(width: 54, angle: 0.06),
        ),
      ],
    );
  }
}

class _EntryReason extends StatelessWidget {
  const _EntryReason({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Motivo de entrada: $reason',
      excludeSemantics: true,
      child: Align(
        alignment: Alignment.centerLeft,
        child: StampBadge(
          label: reason,
          color: AppPalette.burgundy,
          angle: -0.018,
        ),
      ),
    );
  }
}

class _CharacterSlot extends StatelessWidget {
  const _CharacterSlot({required this.artwork});

  final Widget? artwork;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: PaperPanel(
        background: AppPalette.kraft,
        borderColor: AppPalette.ink,
        rotation: -0.006,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x4,
          vertical: AppSpacing.x3,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child:
              artwork ??
              Row(
                children: [
                  const Icon(
                    Icons.crop_original_rounded,
                    size: 30,
                    color: AppPalette.inkSecondary,
                  ),
                  const SizedBox(width: AppSpacing.x3),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LA MANÍ',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.x1),
                        Text(
                          'ILUSTRACIÓN PENDIENTE · usar foto fuente',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppPalette.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        ),
      ),
    );
  }
}

class _StatusTicket extends StatelessWidget {
  const _StatusTicket({required this.statusLabel});

  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Estado confirmado: $statusLabel',
      excludeSemantics: true,
      child: PaperPanel(
        background: AppPalette.surface,
        borderColor: AppPalette.mustard,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x3,
          vertical: AppSpacing.x2,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 20,
              color: AppPalette.burgundy,
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Text(
                statusLabel,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CuchaActionButton extends StatelessWidget {
  const _CuchaActionButton({
    required this.action,
    required this.surfaceState,
    required this.pendingActionId,
    required this.onPressed,
  });

  final CuchaActionView action;
  final CuchaSurfaceState surfaceState;
  final String? pendingActionId;
  final ValueChanged<String>? onPressed;

  @override
  Widget build(BuildContext context) {
    final isPending =
        surfaceState == CuchaSurfaceState.pending &&
        pendingActionId == action.id;
    final actionable =
        surfaceState == CuchaSurfaceState.available && onPressed != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final reason = _disabledReason;
    final semanticLabel = actionable
        ? '${action.label}. ${action.detail ?? ''}'.trim()
        : isPending
        ? '${action.pendingLabel}. Esperando confirmación.'
        : '${action.label}. No disponible: $reason';

    return Semantics(
      button: true,
      enabled: actionable,
      label: semanticLabel,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppSizes.primaryControlHeight,
        ),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: isPending ? AppPalette.kraft : AppPalette.surface,
            foregroundColor: AppPalette.ink,
            side: BorderSide(
              color: isPending ? AppPalette.mustard : AppPalette.ink,
              width: isPending ? 1.8 : 1.2,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x3,
              vertical: AppSpacing.x3,
            ),
          ),
          onPressed: actionable ? () => onPressed!(action.id) : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isPending) ...[
                SizedBox.square(
                  dimension: 18,
                  child: reduceMotion
                      ? const Icon(Icons.more_horiz_rounded, size: 18)
                      : const CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.x2),
              ] else ...[
                const Icon(Icons.arrow_forward_rounded, size: 18),
                const SizedBox(width: AppSpacing.x2),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPending ? action.pendingLabel : action.label,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (!isPending && action.detail != null) ...[
                      const SizedBox(height: AppSpacing.x1),
                      Text(
                        action.detail!,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: AppPalette.inkSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _disabledReason => switch (surfaceState) {
    CuchaSurfaceState.pending => 'Otra opción está esperando confirmación',
    CuchaSurfaceState.confirmed => 'La decisión ya fue confirmada',
    CuchaSurfaceState.rejected => 'Esperando el estado actualizado',
    CuchaSurfaceState.stale => 'Las opciones cambiaron',
    CuchaSurfaceState.uncertain => 'Confirmando qué pasó',
    CuchaSurfaceState.offline => 'Reconectando',
    CuchaSurfaceState.available => 'Acción no conectada',
  };
}

class _ConfirmedTicket extends StatelessWidget {
  const _ConfirmedTicket({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      excludeSemantics: true,
      child: PaperPanel(
        background: AppPalette.surface,
        borderColor: AppPalette.bottleGreen,
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              color: AppPalette.bottleGreen,
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoActionsPlaceholder extends StatelessWidget {
  const _NoActionsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return PaperPanel(
      background: AppPalette.surface,
      borderColor: AppPalette.inkSecondary,
      padding: const EdgeInsets.all(AppSpacing.x3),
      child: Text(
        'Esperando opciones válidas del estado confirmado.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppPalette.inkSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MandatoryHandle extends StatelessWidget {
  const _MandatoryHandle();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppPalette.inkSecondary.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}
