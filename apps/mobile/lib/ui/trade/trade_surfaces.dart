import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../feedback/async_action_button.dart';
import '../feedback/interaction_feedback_state.dart';
import '../feedback/interaction_status_layer.dart';

enum TradeBuilderState {
  draftEmpty,
  draftValid,
  pendingSend,
  sent,
  stale,
  expired,
  uncertain,
  offline,
}

enum TradeReviewState {
  available,
  pendingAccept,
  accepted,
  rejected,
  counter,
  stale,
  expired,
  uncertain,
  offline,
  waitingHuman,
}

class TradeAssetView {
  const TradeAssetView({
    required this.id,
    required this.label,
    required this.selected,
    this.detail,
    this.available = true,
    this.unavailableReason,
  });

  final String id;
  final String label;
  final String? detail;
  final bool selected;
  final bool available;
  final String? unavailableReason;
}

class TradeBuilderSurface extends StatelessWidget {
  const TradeBuilderSurface({
    required this.rivalLabel,
    required this.offeredAssets,
    required this.requestedAssets,
    required this.offeredCashController,
    required this.requestedCashController,
    required this.summaryGiveLabel,
    required this.summaryReceiveLabel,
    required this.state,
    this.onToggleOfferedAsset,
    this.onToggleRequestedAsset,
    this.onSend,
    this.statusMessage,
    super.key,
  });

  final String rivalLabel;
  final List<TradeAssetView> offeredAssets;
  final List<TradeAssetView> requestedAssets;
  final TextEditingController offeredCashController;
  final TextEditingController requestedCashController;
  final String summaryGiveLabel;
  final String summaryReceiveLabel;
  final TradeBuilderState state;
  final ValueChanged<String>? onToggleOfferedAsset;
  final ValueChanged<String>? onToggleRequestedAsset;
  final VoidCallback? onSend;
  final String? statusMessage;

  @override
  Widget build(BuildContext context) {
    final editable =
        state == TradeBuilderState.draftEmpty ||
        state == TradeBuilderState.draftValid;
    final sendState = _sendFeedbackState;
    final statusState = _statusFeedbackState;

    return Material(
      color: AppPalette.surface,
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
            explicitChildNodes: true,
            label: 'Negociación con $rivalLabel',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'NEGOCIAR',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppPalette.primary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  rivalLabel,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppSpacing.x5),
                _TradeSideSection(
                  title: 'Vos ofrecés',
                  cashLabel: 'Efectivo que entregás',
                  cashController: offeredCashController,
                  assets: offeredAssets,
                  editable: editable,
                  onToggleAsset: onToggleOfferedAsset,
                ),
                const SizedBox(height: AppSpacing.x5),
                _TradeSideSection(
                  title: 'Vos pedís',
                  cashLabel: 'Efectivo que pedís',
                  cashController: requestedCashController,
                  assets: requestedAssets,
                  editable: editable,
                  onToggleAsset: onToggleRequestedAsset,
                ),
                const SizedBox(height: AppSpacing.x5),
                _BilateralSummary(
                  giveLabel: summaryGiveLabel,
                  receiveLabel: summaryReceiveLabel,
                ),
                if (statusState != null) ...[
                  const SizedBox(height: AppSpacing.x4),
                  InteractionStatusLayer(
                    state: statusState,
                    message: statusMessage ?? _defaultStatusMessage,
                  ),
                ],
                if (state == TradeBuilderState.sent) ...[
                  const SizedBox(height: AppSpacing.x4),
                  const _TradeOutcome(
                    icon: Icons.schedule_send_outlined,
                    title: 'Propuesta enviada',
                    body: 'Volvé al tablero. La propuesta queda pendiente según el estado confirmado.',
                  ),
                ],
                const SizedBox(height: AppSpacing.x5),
                AsyncActionButton(
                  label: 'Enviar propuesta',
                  pendingLabel: 'Enviando…',
                  state: sendState,
                  onPressed: onSend,
                  disabledReason: _sendDisabledReason,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InteractionFeedbackState get _sendFeedbackState => switch (state) {
    TradeBuilderState.draftEmpty => InteractionFeedbackState.disabled,
    TradeBuilderState.draftValid => InteractionFeedbackState.idle,
    TradeBuilderState.pendingSend => InteractionFeedbackState.pending,
    TradeBuilderState.sent ||
    TradeBuilderState.stale ||
    TradeBuilderState.expired => InteractionFeedbackState.disabled,
    TradeBuilderState.uncertain => InteractionFeedbackState.uncertain,
    TradeBuilderState.offline => InteractionFeedbackState.offline,
  };

  InteractionFeedbackState? get _statusFeedbackState => switch (state) {
    TradeBuilderState.draftEmpty ||
    TradeBuilderState.draftValid ||
    TradeBuilderState.sent => null,
    TradeBuilderState.pendingSend => InteractionFeedbackState.pending,
    TradeBuilderState.stale => InteractionFeedbackState.stale,
    TradeBuilderState.expired => InteractionFeedbackState.stale,
    TradeBuilderState.uncertain => InteractionFeedbackState.uncertain,
    TradeBuilderState.offline => InteractionFeedbackState.offline,
  };

  String get _defaultStatusMessage => switch (state) {
    TradeBuilderState.pendingSend =>
      'Esperando confirmación. Todavía no se transfirió ningún activo.',
    TradeBuilderState.stale =>
      'La situación cambió. Revisá qué activos siguen disponibles.',
    TradeBuilderState.expired =>
      'Esta propuesta ya no es accionable. No se transfirió ningún activo.',
    TradeBuilderState.uncertain =>
      'Confirmando qué pasó antes de permitir otra propuesta equivalente.',
    TradeBuilderState.offline =>
      'Reconectando antes de habilitar cambios en la propuesta.',
    _ => '',
  };

  String? get _sendDisabledReason => switch (state) {
    TradeBuilderState.draftEmpty => 'Agregá algo para ofrecer o pedir',
    TradeBuilderState.pendingSend => 'Esperando confirmación',
    TradeBuilderState.sent => 'La propuesta ya fue enviada',
    TradeBuilderState.stale => 'La situación cambió',
    TradeBuilderState.expired => 'La propuesta venció',
    _ => null,
  };
}

class TradeReviewSurface extends StatelessWidget {
  const TradeReviewSurface({
    required this.proposerLabel,
    required this.receiveLabel,
    required this.giveLabel,
    required this.deadlineLabel,
    required this.deadlineProgress,
    required this.state,
    this.onAccept,
    this.onCounter,
    this.onReject,
    this.statusMessage,
    super.key,
  });

  final String proposerLabel;
  final String receiveLabel;
  final String giveLabel;
  final String deadlineLabel;
  final double deadlineProgress;
  final TradeReviewState state;
  final VoidCallback? onAccept;
  final VoidCallback? onCounter;
  final VoidCallback? onReject;
  final String? statusMessage;

  @override
  Widget build(BuildContext context) {
    final acceptState = _acceptFeedbackState;
    final secondaryEnabled = state == TradeReviewState.available;
    final statusState = _statusFeedbackState;

    return Material(
      color: AppPalette.surface,
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
            label: 'Propuesta de $proposerLabel',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _MandatoryHandle(),
                const SizedBox(height: AppSpacing.x4),
                Text(
                  'PROPUESTA',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppPalette.primary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  proposerLabel,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppSpacing.x4),
                _ReviewExchange(
                  receiveLabel: receiveLabel,
                  giveLabel: giveLabel,
                ),
                const SizedBox(height: AppSpacing.x4),
                _DeadlineIndicator(
                  label: deadlineLabel,
                  progress: deadlineProgress,
                ),
                if (statusState != null) ...[
                  const SizedBox(height: AppSpacing.x4),
                  InteractionStatusLayer(
                    state: statusState,
                    message: statusMessage ?? _defaultStatusMessage,
                  ),
                ],
                if (_outcome != null) ...[
                  const SizedBox(height: AppSpacing.x4),
                  _outcome!,
                ],
                const SizedBox(height: AppSpacing.x5),
                AsyncActionButton(
                  label: 'Aceptar',
                  pendingLabel: 'Aceptando…',
                  state: acceptState,
                  onPressed: onAccept,
                  disabledReason: _acceptDisabledReason,
                ),
                const SizedBox(height: AppSpacing.x3),
                _ReviewSecondaryAction(
                  label: 'Contraofertar',
                  icon: Icons.swap_horiz_rounded,
                  enabled: secondaryEnabled,
                  disabledReason: _secondaryDisabledReason,
                  onPressed: onCounter,
                ),
                const SizedBox(height: AppSpacing.x2),
                _ReviewSecondaryAction(
                  label: 'Rechazar',
                  icon: Icons.close_rounded,
                  enabled: secondaryEnabled,
                  disabledReason: _secondaryDisabledReason,
                  onPressed: onReject,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InteractionFeedbackState get _acceptFeedbackState => switch (state) {
    TradeReviewState.available => InteractionFeedbackState.idle,
    TradeReviewState.pendingAccept => InteractionFeedbackState.pending,
    TradeReviewState.accepted ||
    TradeReviewState.rejected ||
    TradeReviewState.counter ||
    TradeReviewState.stale ||
    TradeReviewState.expired ||
    TradeReviewState.waitingHuman => InteractionFeedbackState.disabled,
    TradeReviewState.uncertain => InteractionFeedbackState.uncertain,
    TradeReviewState.offline => InteractionFeedbackState.offline,
  };

  InteractionFeedbackState? get _statusFeedbackState => switch (state) {
    TradeReviewState.available ||
    TradeReviewState.accepted ||
    TradeReviewState.rejected ||
    TradeReviewState.counter => null,
    TradeReviewState.pendingAccept => InteractionFeedbackState.pending,
    TradeReviewState.stale => InteractionFeedbackState.stale,
    TradeReviewState.expired => InteractionFeedbackState.stale,
    TradeReviewState.uncertain => InteractionFeedbackState.uncertain,
    TradeReviewState.offline => InteractionFeedbackState.offline,
    TradeReviewState.waitingHuman => InteractionFeedbackState.disabled,
  };

  String get _defaultStatusMessage => switch (state) {
    TradeReviewState.pendingAccept => 'Esperando confirmación. Los activos todavía muestran el último estado confirmado.',
    TradeReviewState.stale =>
      'La propuesta ya no es válida. Reconciliando con el estado actual.',
    TradeReviewState.expired =>
      'La propuesta venció. Esto no se presenta como un rechazo manual.',
    TradeReviewState.uncertain =>
      'Confirmando qué pasó antes de habilitar otra respuesta.',
    TradeReviewState.offline =>
      'Reconectando antes de habilitar una respuesta.',
    TradeReviewState.waitingHuman => 'Esperando a que vuelva el jugador. El bot temporal no puede aceptar por él.',
    _ => '',
  };

  String? get _acceptDisabledReason => switch (state) {
    TradeReviewState.pendingAccept => 'Esperando confirmación',
    TradeReviewState.accepted => 'La propuesta ya fue aceptada',
    TradeReviewState.rejected => 'La propuesta ya fue rechazada',
    TradeReviewState.counter => 'La contraoferta se gestiona en el builder',
    TradeReviewState.stale => 'La propuesta ya no es válida',
    TradeReviewState.expired => 'La propuesta venció',
    TradeReviewState.waitingHuman => 'El bot temporal no puede aceptar',
    _ => null,
  };

  String? get _secondaryDisabledReason => switch (state) {
    TradeReviewState.pendingAccept => 'Esperando confirmación',
    TradeReviewState.waitingHuman => 'Esperando al jugador',
    TradeReviewState.expired => 'La propuesta venció',
    TradeReviewState.stale => 'La propuesta ya no es válida',
    _ => 'La propuesta no está disponible',
  };

  Widget? get _outcome => switch (state) {
    TradeReviewState.accepted => const _TradeOutcome(
      icon: Icons.check_circle_outline_rounded,
      title: 'Intercambio confirmado',
      body: 'Los cambios de efectivo y activos se muestran juntos desde el estado confirmado.',
    ),
    TradeReviewState.rejected => const _TradeOutcome(
      icon: Icons.cancel_outlined,
      title: 'Propuesta rechazada',
      body: 'No se transfirió ningún activo.',
    ),
    TradeReviewState.counter => const _TradeOutcome(
      icon: Icons.swap_horiz_rounded,
      title: 'Contraoferta',
      body: 'El builder puede abrirse prellenado; enviarla será una propuesta nueva.',
    ),
    _ => null,
  };
}

class _TradeSideSection extends StatelessWidget {
  const _TradeSideSection({
    required this.title,
    required this.cashLabel,
    required this.cashController,
    required this.assets,
    required this.editable,
    required this.onToggleAsset,
  });

  final String title;
  final String cashLabel;
  final TextEditingController cashController;
  final List<TradeAssetView> assets;
  final bool editable;
  final ValueChanged<String>? onToggleAsset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: AppSpacing.x3),
        TextField(
          controller: cashController,
          enabled: editable,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: cashLabel, hintText: '0'),
        ),
        const SizedBox(height: AppSpacing.x3),
        for (final asset in assets)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.x2),
            child: _TradeAssetRow(
              asset: asset,
              editable: editable,
              onToggle: onToggleAsset,
            ),
          ),
      ],
    );
  }
}

class _TradeAssetRow extends StatelessWidget {
  const _TradeAssetRow({
    required this.asset,
    required this.editable,
    required this.onToggle,
  });

  final TradeAssetView asset;
  final bool editable;
  final ValueChanged<String>? onToggle;

  @override
  Widget build(BuildContext context) {
    final actionable = editable && asset.available && onToggle != null;
    final stateLabel = asset.selected ? 'seleccionado' : 'no seleccionado';
    final availabilityLabel = asset.available
        ? ''
        : '. No disponible: ${asset.unavailableReason ?? 'estado actual'}';

    return Semantics(
      button: true,
      selected: asset.selected,
      enabled: actionable,
      label: '${asset.label}. $stateLabel$availabilityLabel.',
      excludeSemantics: true,
      child: SizedBox(
        height: AppSizes.primaryControlHeight,
        child: OutlinedButton(
          onPressed: actionable ? () => onToggle!(asset.id) : null,
          child: Row(
            children: [
              Icon(
                asset.selected
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (asset.detail != null)
                      Text(
                        asset.detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

class _BilateralSummary extends StatelessWidget {
  const _BilateralSummary({
    required this.giveLabel,
    required this.receiveLabel,
  });

  final String giveLabel;
  final String receiveLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Vos entregás: $giveLabel. Vos recibís: $receiveLabel.',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.x4),
        decoration: BoxDecoration(
          color: AppPalette.canvas,
          border: Border.all(color: AppPalette.inkSecondary),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SummaryLine(title: 'Vos entregás', body: giveLabel),
            const SizedBox(height: AppSpacing.x3),
            _SummaryLine(title: 'Vos recibís', body: receiveLabel),
          ],
        ),
      ),
    );
  }
}

class _ReviewExchange extends StatelessWidget {
  const _ReviewExchange({required this.receiveLabel, required this.giveLabel});

  final String receiveLabel;
  final String giveLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Recibís: $receiveLabel. Entregás: $giveLabel.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReviewBlock(
            icon: Icons.call_received_rounded,
            title: 'Recibís',
            body: receiveLabel,
          ),
          const SizedBox(height: AppSpacing.x3),
          _ReviewBlock(
            icon: Icons.call_made_rounded,
            title: 'Entregás',
            body: giveLabel,
          ),
        ],
      ),
    );
  }
}

class _ReviewBlock extends StatelessWidget {
  const _ReviewBlock({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x3),
      decoration: BoxDecoration(
        color: AppPalette.canvas,
        border: Border.all(color: AppPalette.inkSecondary),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: _SummaryLine(title: title, body: body),
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppPalette.inkSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          body,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
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

    return Semantics(
      container: true,
      label: 'Tiempo para responder: $label. El cierre lo confirma la partida.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 18),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                child: Text(
                  'Tiempo para responder',
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
          LinearProgressIndicator(value: clamped),
        ],
      ),
    );
  }
}

class _ReviewSecondaryAction extends StatelessWidget {
  const _ReviewSecondaryAction({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.disabledReason,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final String? disabledReason;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final actionable = enabled && onPressed != null;
    final semanticLabel = actionable
        ? label
        : '$label. No disponible: ${disabledReason ?? 'estado actual'}';

    return Semantics(
      button: true,
      enabled: actionable,
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: AppSizes.minTouchTarget,
        child: OutlinedButton.icon(
          onPressed: actionable ? onPressed : null,
          icon: Icon(icon),
          label: Text(label),
        ),
      ),
    );
  }
}

class _TradeOutcome extends StatelessWidget {
  const _TradeOutcome({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $body',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.x3),
        decoration: BoxDecoration(
          color: AppPalette.canvas,
          border: Border.all(color: AppPalette.inkSecondary),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  Text(body),
                ],
              ),
            ),
          ],
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
