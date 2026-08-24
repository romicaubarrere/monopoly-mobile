import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';
import '../feedback/async_action_button.dart';
import '../feedback/interaction_feedback_state.dart';
import '../feedback/interaction_status_layer.dart';

enum AuctionSurfaceState {
  waitingMySlot,
  leading,
  outbid,
  pendingBid,
  bidRejected,
  passed,
  slotExpired,
  hardCap,
  uncertain,
  offline,
}

enum AuctionParticipantState { active, leader, passed, timedOut }

class AuctionParticipantView {
  const AuctionParticipantView({
    required this.label,
    required this.state,
    this.bidLabel,
  });

  final String label;
  final AuctionParticipantState state;
  final String? bidLabel;
}

class AuctionSheet extends StatelessWidget {
  const AuctionSheet({
    required this.propertyLabel,
    required this.currentBidLabel,
    required this.leaderLabel,
    required this.cashAvailableLabel,
    required this.deadlineLabel,
    required this.deadlineProgress,
    required this.participants,
    required this.bidController,
    required this.state,
    this.quickIncrementLabels = const <String>[],
    this.onQuickIncrement,
    this.onBid,
    this.onPass,
    this.bidDisabledReason,
    this.statusMessage,
    super.key,
  });

  final String propertyLabel;
  final String currentBidLabel;
  final String leaderLabel;
  final String cashAvailableLabel;
  final String deadlineLabel;
  final double deadlineProgress;
  final List<AuctionParticipantView> participants;
  final TextEditingController bidController;
  final AuctionSurfaceState state;
  final List<String> quickIncrementLabels;
  final ValueChanged<String>? onQuickIncrement;
  final VoidCallback? onBid;
  final VoidCallback? onPass;
  final String? bidDisabledReason;
  final String? statusMessage;

  @override
  Widget build(BuildContext context) {
    final bidState = _bidFeedbackState;
    final passState = _passFeedbackState;
    final canEditBid = bidState == InteractionFeedbackState.idle;
    final statusState = _statusFeedbackState;

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
            label: 'Subasta de $propertyLabel',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _MandatoryHandle(),
                const SizedBox(height: AppSpacing.x4),
                _AuctionAlmacenHeader(propertyLabel: propertyLabel),
                const SizedBox(height: AppSpacing.x4),
                _AuctionHeadline(
                  currentBidLabel: currentBidLabel,
                  leaderLabel: leaderLabel,
                  isLeading: state == AuctionSurfaceState.leading,
                ),
                const SizedBox(height: AppSpacing.x4),
                _DeadlineIndicator(
                  label: deadlineLabel,
                  progress: deadlineProgress,
                ),
                const SizedBox(height: AppSpacing.x4),
                _ParticipantList(participants: participants),
                const SizedBox(height: AppSpacing.x4),
                _CashAvailable(label: cashAvailableLabel),
                const SizedBox(height: AppSpacing.x3),
                if (quickIncrementLabels.isNotEmpty)
                  _QuickIncrements(
                    labels: quickIncrementLabels,
                    enabled: canEditBid,
                    onSelected: onQuickIncrement,
                  ),
                if (quickIncrementLabels.isNotEmpty)
                  const SizedBox(height: AppSpacing.x3),
                TextField(
                  key: const Key('auction-bid-input'),
                  controller: bidController,
                  enabled: canEditBid,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppPalette.surface,
                    labelText: 'Tu puja',
                    hintText: 'Monto',
                    helperText: canEditBid
                        ? 'La partida valida el monto al confirmar.'
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      borderSide: const BorderSide(color: AppPalette.ink),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      borderSide: const BorderSide(color: AppPalette.ink),
                    ),
                  ),
                ),
                if (statusState != null) ...[
                  const SizedBox(height: AppSpacing.x4),
                  InteractionStatusLayer(
                    state: statusState,
                    message: statusMessage ?? _defaultStatusMessage,
                  ),
                ],
                const SizedBox(height: AppSpacing.x5),
                AsyncActionButton(
                  label: 'Pujar',
                  pendingLabel: 'Enviando puja…',
                  state: bidState,
                  onPressed: onBid,
                  disabledReason: _resolvedBidDisabledReason,
                ),
                const SizedBox(height: AppSpacing.x3),
                _PassButton(
                  state: passState,
                  disabledReason: _passDisabledReason,
                  onPressed: onPass,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InteractionFeedbackState get _bidFeedbackState => switch (state) {
    AuctionSurfaceState.waitingMySlot ||
    AuctionSurfaceState.leading ||
    AuctionSurfaceState.outbid ||
    AuctionSurfaceState.bidRejected => InteractionFeedbackState.idle,
    AuctionSurfaceState.pendingBid => InteractionFeedbackState.pending,
    AuctionSurfaceState.passed ||
    AuctionSurfaceState.slotExpired ||
    AuctionSurfaceState.hardCap => InteractionFeedbackState.disabled,
    AuctionSurfaceState.uncertain => InteractionFeedbackState.uncertain,
    AuctionSurfaceState.offline => InteractionFeedbackState.offline,
  };

  InteractionFeedbackState get _passFeedbackState => switch (state) {
    AuctionSurfaceState.waitingMySlot ||
    AuctionSurfaceState.leading ||
    AuctionSurfaceState.outbid ||
    AuctionSurfaceState.bidRejected => InteractionFeedbackState.idle,
    AuctionSurfaceState.pendingBid => InteractionFeedbackState.disabled,
    AuctionSurfaceState.passed ||
    AuctionSurfaceState.slotExpired ||
    AuctionSurfaceState.hardCap => InteractionFeedbackState.disabled,
    AuctionSurfaceState.uncertain => InteractionFeedbackState.uncertain,
    AuctionSurfaceState.offline => InteractionFeedbackState.offline,
  };

  InteractionFeedbackState? get _statusFeedbackState => switch (state) {
    AuctionSurfaceState.waitingMySlot ||
    AuctionSurfaceState.leading ||
    AuctionSurfaceState.outbid => null,
    AuctionSurfaceState.pendingBid => InteractionFeedbackState.pending,
    AuctionSurfaceState.bidRejected => InteractionFeedbackState.rejected,
    AuctionSurfaceState.passed ||
    AuctionSurfaceState.hardCap => InteractionFeedbackState.confirmed,
    AuctionSurfaceState.slotExpired => InteractionFeedbackState.stale,
    AuctionSurfaceState.uncertain => InteractionFeedbackState.uncertain,
    AuctionSurfaceState.offline => InteractionFeedbackState.offline,
  };

  String get _defaultStatusMessage => switch (state) {
    AuctionSurfaceState.pendingBid =>
      'Esperando confirmación. La oferta visible sigue siendo la última confirmada.',
    AuctionSurfaceState.bidRejected =>
      'La puja no fue aplicada. Actualizá el monto sobre el estado confirmado.',
    AuctionSurfaceState.passed =>
      'Ya pasaste; no podés volver a pujar en esta subasta.',
    AuctionSurfaceState.slotExpired =>
      'Tu turno de puja terminó según el estado confirmado.',
    AuctionSurfaceState.hardCap =>
      'La partida cerró la subasta. Esperando el resultado confirmado.',
    AuctionSurfaceState.uncertain =>
      'Confirmando qué pasó antes de permitir otra puja.',
    AuctionSurfaceState.offline =>
      'Reconectando antes de habilitar controles de subasta.',
    _ => '',
  };

  String? get _resolvedBidDisabledReason => switch (state) {
    AuctionSurfaceState.passed => 'Ya pasaste en esta subasta',
    AuctionSurfaceState.slotExpired => 'Tu turno de puja ya terminó',
    AuctionSurfaceState.hardCap => 'La subasta está cerrando',
    AuctionSurfaceState.pendingBid => 'Esperando confirmación de la puja',
    _ => bidDisabledReason,
  };

  String? get _passDisabledReason => switch (state) {
    AuctionSurfaceState.pendingBid => 'Esperando confirmación de la puja',
    AuctionSurfaceState.passed => 'Ya pasaste en esta subasta',
    AuctionSurfaceState.slotExpired => 'Tu turno de puja ya terminó',
    AuctionSurfaceState.hardCap => 'La subasta está cerrando',
    _ => null,
  };
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

class _AuctionAlmacenHeader extends StatelessWidget {
  const _AuctionAlmacenHeader({required this.propertyLabel});

  final String propertyLabel;

  @override
  Widget build(BuildContext context) {
    return Stack(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: StampBadge(
                  label: 'Remate de barrio',
                  color: AppPalette.wornBlue,
                  angle: -0.025,
                ),
              ),
              const SizedBox(height: AppSpacing.x3),
              Text(
                'SUBASTA',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppPalette.primary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(
                propertyLabel,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
            ],
          ),
        ),
        const Positioned(right: 18, top: -6, child: TapeMark(width: 58)),
      ],
    );
  }
}

class _AuctionHeadline extends StatelessWidget {
  const _AuctionHeadline({
    required this.currentBidLabel,
    required this.leaderLabel,
    required this.isLeading,
  });

  final String currentBidLabel;
  final String leaderLabel;
  final bool isLeading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Oferta actual: $currentBidLabel. Lidera: $leaderLabel.',
      excludeSemantics: true,
      child: PaperPanel(
        background: isLeading ? const Color(0xFFE7F0E6) : AppPalette.kraft,
        borderColor: isLeading ? AppPalette.bottleGreen : AppPalette.ink,
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: _Metric(
                label: 'Oferta actual',
                value: currentBidLabel,
                emphasized: true,
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              flex: 5,
              child: _Metric(
                label: isLeading ? 'Vas ganando' : 'Lidera',
                value: leaderLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeadlineIndicator extends StatelessWidget {
  const _DeadlineIndicator({required this.label, required this.progress});

  final String label;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0).toDouble();
    final icon = clamped >= 0.75
        ? Icons.timer_outlined
        : Icons.schedule_rounded;

    return Semantics(
      container: true,
      label: 'Tiempo para actuar: $label. El cierre lo confirma la partida.',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.x3),
        decoration: BoxDecoration(
          color: AppPalette.surface,
          border: Border.all(color: AppPalette.ink, width: 1.2),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Text(
                    'Tiempo para actuar',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppPalette.inkSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x2),
            LinearProgressIndicator(
              value: clamped,
              color: clamped >= 0.75 ? AppPalette.primary : AppPalette.wornBlue,
              backgroundColor: AppPalette.paperEdge,
              borderRadius: BorderRadius.circular(999),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParticipantList extends StatelessWidget {
  const _ParticipantList({required this.participants});

  final List<AuctionParticipantView> participants;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Participantes',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        for (final participant in participants)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.x2),
            child: _ParticipantRow(participant: participant),
          ),
      ],
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({required this.participant});

  final AuctionParticipantView participant;

  @override
  Widget build(BuildContext context) {
    final stateLabel = switch (participant.state) {
      AuctionParticipantState.active => 'activo',
      AuctionParticipantState.leader => 'liderando',
      AuctionParticipantState.passed => 'pasó',
      AuctionParticipantState.timedOut => 'tiempo agotado',
    };
    final icon = switch (participant.state) {
      AuctionParticipantState.active => Icons.circle_outlined,
      AuctionParticipantState.leader => Icons.emoji_events_outlined,
      AuctionParticipantState.passed => Icons.remove_circle_outline,
      AuctionParticipantState.timedOut => Icons.timer_off_outlined,
    };
    final bidSuffix = participant.bidLabel == null
        ? ''
        : '. Última oferta: ${participant.bidLabel}';
    final isLeader = participant.state == AuctionParticipantState.leader;

    return Semantics(
      container: true,
      label: '${participant.label}. Estado: $stateLabel$bidSuffix.',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x3,
          vertical: AppSpacing.x2,
        ),
        decoration: BoxDecoration(
          color: isLeader ? const Color(0xFFF5E7B9) : AppPalette.surface,
          border: Border.all(
            color: isLeader ? AppPalette.mustard : AppPalette.inkSecondary,
            width: isLeader ? 1.6 : 1,
          ),
          borderRadius: BorderRadius.circular(AppRadius.control),
          boxShadow: const [
            BoxShadow(
              color: Color(0x16000000),
              offset: Offset(2, 2),
              blurRadius: 0,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isLeader ? AppPalette.burgundy : AppPalette.ink,
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Text(
                participant.label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              stateLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.inkSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CashAvailable extends StatelessWidget {
  const _CashAvailable({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Tu efectivo disponible: $label.',
      excludeSemantics: true,
      child: PaperPanel(
        background: AppPalette.surface,
        borderColor: AppPalette.bottleGreen,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x3,
          vertical: AppSpacing.x3,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.account_balance_wallet_outlined,
              size: 18,
              color: AppPalette.bottleGreen,
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Text(
                'Tu efectivo disponible',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickIncrements extends StatelessWidget {
  const _QuickIncrements({
    required this.labels,
    required this.enabled,
    required this.onSelected,
  });

  final List<String> labels;
  final bool enabled;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Subir rápido',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppPalette.inkSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        Wrap(
          spacing: AppSpacing.x2,
          runSpacing: AppSpacing.x2,
          children: [
            for (final label in labels)
              SizedBox(
                height: AppSizes.minTouchTarget,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: enabled ? AppPalette.kraft : null,
                    foregroundColor: AppPalette.ink,
                    side: const BorderSide(color: AppPalette.ink),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sign),
                    ),
                  ),
                  onPressed: enabled && onSelected != null
                      ? () => onSelected!(label)
                      : null,
                  child: Text('+$label'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PassButton extends StatelessWidget {
  const _PassButton({
    required this.state,
    required this.disabledReason,
    this.onPressed,
  });

  final InteractionFeedbackState state;
  final String? disabledReason;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isActionable =
        state == InteractionFeedbackState.idle && onPressed != null;
    final semanticLabel = switch (state) {
      InteractionFeedbackState.uncertain =>
        'Pasar. Confirmando qué pasó antes de continuar.',
      InteractionFeedbackState.offline =>
        'Pasar. No disponible mientras se reconecta.',
      InteractionFeedbackState.disabled when disabledReason != null =>
        'Pasar. No disponible: $disabledReason',
      _ => 'Pasar',
    };

    return Semantics(
      button: true,
      enabled: isActionable,
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: AppSizes.primaryControlHeight,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            backgroundColor: AppPalette.surface,
            foregroundColor: AppPalette.ink,
            side: const BorderSide(color: AppPalette.ink, width: 1.2),
          ),
          onPressed: isActionable ? onPressed : null,
          icon: const Icon(Icons.flag_outlined),
          label: const Text('Pasar'),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppPalette.inkSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          value,
          style: (emphasized
                  ? Theme.of(context).textTheme.headlineSmall
                  : Theme.of(context).textTheme.titleMedium)
              ?.copyWith(
                color: emphasized ? AppPalette.burgundy : AppPalette.ink,
                fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1,
              ),
        ),
      ],
    );
  }
}
