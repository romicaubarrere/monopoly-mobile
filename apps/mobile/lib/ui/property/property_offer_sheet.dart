import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../feedback/async_action_button.dart';
import '../feedback/interaction_feedback_state.dart';
import '../feedback/interaction_status_layer.dart';

enum PropertyOfferDecisionState {
  available,
  insufficientFunds,
  pendingBuy,
  pendingDecline,
  stale,
  rejected,
  uncertain,
  offline,
}

class PropertyOfferSheet extends StatelessWidget {
  const PropertyOfferSheet({
    required this.propertyLabel,
    required this.groupLabel,
    required this.groupSignalColor,
    required this.priceLabel,
    required this.baseRentLabel,
    required this.cashNowLabel,
    required this.cashAfterLabel,
    required this.groupProgressLabel,
    required this.state,
    this.onBuy,
    this.onDecline,
    this.buyDisabledReason,
    this.statusMessage,
    super.key,
  });

  final String propertyLabel;
  final String groupLabel;
  final Color groupSignalColor;
  final String priceLabel;
  final String baseRentLabel;
  final String cashNowLabel;
  final String cashAfterLabel;
  final String groupProgressLabel;
  final PropertyOfferDecisionState state;
  final VoidCallback? onBuy;
  final VoidCallback? onDecline;
  final String? buyDisabledReason;
  final String? statusMessage;

  @override
  Widget build(BuildContext context) {
    final buyState = _buyFeedbackState;
    final declineState = _declineFeedbackState;
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
            label: 'Oferta de propiedad',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _MandatoryHandle(),
                const SizedBox(height: AppSpacing.x4),
                _PropertyIdentity(
                  propertyLabel: propertyLabel,
                  groupLabel: groupLabel,
                  groupSignalColor: groupSignalColor,
                ),
                const SizedBox(height: AppSpacing.x4),
                _PrimaryEconomy(
                  priceLabel: priceLabel,
                  baseRentLabel: baseRentLabel,
                ),
                const SizedBox(height: AppSpacing.x4),
                _CashConsequence(
                  cashNowLabel: cashNowLabel,
                  cashAfterLabel: cashAfterLabel,
                ),
                const SizedBox(height: AppSpacing.x3),
                _GroupProgress(label: groupProgressLabel),
                if (statusState != null) ...[
                  const SizedBox(height: AppSpacing.x4),
                  InteractionStatusLayer(
                    state: statusState,
                    message: statusMessage ?? _defaultStatusMessage,
                  ),
                ],
                const SizedBox(height: AppSpacing.x5),
                AsyncActionButton(
                  label: 'Comprar $priceLabel',
                  pendingLabel: 'Comprando…',
                  state: buyState,
                  onPressed: onBuy,
                  disabledReason: _buyDisabledReason,
                ),
                const SizedBox(height: AppSpacing.x3),
                _DeclineButton(
                  state: declineState,
                  onPressed: onDecline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InteractionFeedbackState get _buyFeedbackState => switch (state) {
    PropertyOfferDecisionState.available => InteractionFeedbackState.idle,
    PropertyOfferDecisionState.insufficientFunds =>
      InteractionFeedbackState.disabled,
    PropertyOfferDecisionState.pendingBuy => InteractionFeedbackState.pending,
    PropertyOfferDecisionState.pendingDecline =>
      InteractionFeedbackState.disabled,
    PropertyOfferDecisionState.stale => InteractionFeedbackState.disabled,
    PropertyOfferDecisionState.rejected => InteractionFeedbackState.disabled,
    PropertyOfferDecisionState.uncertain =>
      InteractionFeedbackState.uncertain,
    PropertyOfferDecisionState.offline => InteractionFeedbackState.offline,
  };

  InteractionFeedbackState get _declineFeedbackState => switch (state) {
    PropertyOfferDecisionState.available ||
    PropertyOfferDecisionState.insufficientFunds => InteractionFeedbackState.idle,
    PropertyOfferDecisionState.pendingBuy => InteractionFeedbackState.disabled,
    PropertyOfferDecisionState.pendingDecline =>
      InteractionFeedbackState.pending,
    PropertyOfferDecisionState.stale => InteractionFeedbackState.disabled,
    PropertyOfferDecisionState.rejected => InteractionFeedbackState.disabled,
    PropertyOfferDecisionState.uncertain =>
      InteractionFeedbackState.uncertain,
    PropertyOfferDecisionState.offline => InteractionFeedbackState.offline,
  };

  InteractionFeedbackState? get _statusFeedbackState => switch (state) {
    PropertyOfferDecisionState.available ||
    PropertyOfferDecisionState.insufficientFunds => null,
    PropertyOfferDecisionState.pendingBuy ||
    PropertyOfferDecisionState.pendingDecline =>
      InteractionFeedbackState.pending,
    PropertyOfferDecisionState.stale => InteractionFeedbackState.stale,
    PropertyOfferDecisionState.rejected => InteractionFeedbackState.rejected,
    PropertyOfferDecisionState.uncertain =>
      InteractionFeedbackState.uncertain,
    PropertyOfferDecisionState.offline => InteractionFeedbackState.offline,
  };

  String? get _defaultStatusMessage => switch (state) {
    PropertyOfferDecisionState.pendingBuy => 'Confirmando compra…',
    PropertyOfferDecisionState.pendingDecline => 'Abriendo subasta…',
    PropertyOfferDecisionState.stale => 'La situación cambió.',
    PropertyOfferDecisionState.rejected =>
      'La compra no fue aplicada. Revisando el estado confirmado.',
    PropertyOfferDecisionState.uncertain =>
      'Confirmando qué pasó antes de permitir otra decisión.',
    PropertyOfferDecisionState.offline =>
      'Reconectando antes de habilitar esta decisión.',
    _ => null,
  };

  String? get _buyDisabledReason => switch (state) {
    PropertyOfferDecisionState.insufficientFunds =>
      buyDisabledReason ?? 'No tenés efectivo suficiente',
    PropertyOfferDecisionState.pendingDecline => 'Abriendo subasta',
    PropertyOfferDecisionState.stale ||
    PropertyOfferDecisionState.rejected => 'La situación cambió',
    _ => buyDisabledReason,
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

class _PropertyIdentity extends StatelessWidget {
  const _PropertyIdentity({
    required this.propertyLabel,
    required this.groupLabel,
    required this.groupSignalColor,
  });

  final String propertyLabel;
  final String groupLabel;
  final Color groupSignalColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$propertyLabel. Grupo $groupLabel.',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 46,
            decoration: BoxDecoration(
              color: groupSignalColor,
              border: Border.all(color: AppPalette.ink, width: 1.2),
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  propertyLabel,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  groupLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppPalette.inkSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryEconomy extends StatelessWidget {
  const _PrimaryEconomy({required this.priceLabel, required this.baseRentLabel});

  final String priceLabel;
  final String baseRentLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Metric(label: 'Precio', value: priceLabel, emphasized: true),
        ),
        const SizedBox(width: AppSpacing.x3),
        Expanded(
          child: _Metric(label: 'Alquiler base', value: baseRentLabel),
        ),
      ],
    );
  }
}

class _CashConsequence extends StatelessWidget {
  const _CashConsequence({
    required this.cashNowLabel,
    required this.cashAfterLabel,
  });

  final String cashNowLabel;
  final String cashAfterLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          'Efectivo confirmado: $cashNowLabel. Proyectado si comprás: $cashAfterLabel.',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.x3),
        decoration: BoxDecoration(
          color: AppPalette.canvas,
          border: Border.all(color: AppPalette.inkSecondary),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          children: [
            Expanded(
              child: _Metric(label: 'Confirmado', value: cashNowLabel),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.x2),
              child: Icon(Icons.arrow_forward_rounded, size: 18),
            ),
            Expanded(
              child: _Metric(
                label: 'Proyectado',
                value: cashAfterLabel,
                emphasized: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupProgress extends StatelessWidget {
  const _GroupProgress({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.grid_view_rounded, size: 18),
        const SizedBox(width: AppSpacing.x2),
        Expanded(
          child: Text(
            'Grupo: $label',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
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
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _DeclineButton extends StatelessWidget {
  const _DeclineButton({required this.state, this.onPressed});

  final InteractionFeedbackState state;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isPending = state == InteractionFeedbackState.pending;
    final isActionable = state == InteractionFeedbackState.idle && onPressed != null;
    final label = isPending ? 'Abriendo subasta…' : 'No comprar → subasta';
    final semanticLabel = switch (state) {
      InteractionFeedbackState.pending =>
        'Abriendo subasta. Esperando confirmación.',
      InteractionFeedbackState.uncertain =>
        'No comprar y abrir subasta. Confirmando qué pasó antes de continuar.',
      InteractionFeedbackState.offline =>
        'No comprar y abrir subasta. No disponible mientras se reconecta.',
      InteractionFeedbackState.disabled =>
        'No comprar y abrir subasta. No disponible mientras se confirma otra acción.',
      _ => 'No comprar y abrir subasta',
    };

    return Semantics(
      button: true,
      enabled: isActionable,
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: AppSizes.primaryControlHeight,
        child: OutlinedButton.icon(
          onPressed: isActionable ? onPressed : null,
          icon: isPending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.gavel_rounded),
          label: Text(label),
        ),
      ),
    );
  }
}
