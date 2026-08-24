import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../feedback/interaction_feedback_state.dart';
import '../feedback/interaction_status_layer.dart';

enum PropertyManagementViewState {
  available,
  pending,
  confirmed,
  stale,
  rejected,
  uncertain,
  offline,
}

enum PropertyManagementActionKind {
  addMani,
  sellImprovement,
  mortgage,
  unmortgage,
}

class PropertyManagementActionView {
  const PropertyManagementActionView({
    required this.kind,
    required this.label,
    required this.consequenceLabel,
    required this.pendingLabel,
    required this.enabled,
    this.disabledReason,
  });

  final PropertyManagementActionKind kind;
  final String label;
  final String consequenceLabel;
  final String pendingLabel;
  final bool enabled;
  final String? disabledReason;
}

class PropertyManagementSurface extends StatelessWidget {
  const PropertyManagementSurface({
    required this.propertyLabel,
    required this.ownerLabel,
    required this.groupLabel,
    required this.groupStatusLabel,
    required this.groupSignalColor,
    required this.improvementLevel,
    required this.rentLabel,
    required this.mortgageStatusLabel,
    required this.mortgageValueLabel,
    required this.confirmedCashLabel,
    required this.actions,
    required this.state,
    this.nextImprovementLabel,
    this.nextImprovementCostLabel,
    this.projectedCashLabel,
    this.projectedCashContextLabel,
    this.pendingAction,
    this.confirmationMessage,
    this.statusMessage,
    this.onAction,
    super.key,
  }) : assert(improvementLevel >= 0 && improvementLevel <= 5);

  final String propertyLabel;
  final String ownerLabel;
  final String groupLabel;
  final String groupStatusLabel;
  final Color groupSignalColor;
  final int improvementLevel;
  final String rentLabel;
  final String mortgageStatusLabel;
  final String mortgageValueLabel;
  final String confirmedCashLabel;
  final String? nextImprovementLabel;
  final String? nextImprovementCostLabel;
  final String? projectedCashLabel;
  final String? projectedCashContextLabel;
  final List<PropertyManagementActionView> actions;
  final PropertyManagementViewState state;
  final PropertyManagementActionKind? pendingAction;
  final String? confirmationMessage;
  final String? statusMessage;
  final ValueChanged<PropertyManagementActionKind>? onAction;

  @override
  Widget build(BuildContext context) {
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
            label: 'Gestión de propiedad',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SheetHandle(),
                const SizedBox(height: AppSpacing.x4),
                _PropertyIdentity(
                  propertyLabel: propertyLabel,
                  ownerLabel: ownerLabel,
                  groupLabel: groupLabel,
                  groupStatusLabel: groupStatusLabel,
                  groupSignalColor: groupSignalColor,
                ),
                const SizedBox(height: AppSpacing.x4),
                _ImprovementPanel(
                  improvementLevel: improvementLevel,
                  nextImprovementLabel: nextImprovementLabel,
                  nextImprovementCostLabel: nextImprovementCostLabel,
                ),
                const SizedBox(height: AppSpacing.x3),
                _EconomyPanel(
                  rentLabel: rentLabel,
                  mortgageStatusLabel: mortgageStatusLabel,
                  mortgageValueLabel: mortgageValueLabel,
                ),
                const SizedBox(height: AppSpacing.x3),
                _CashPanel(
                  confirmedCashLabel: confirmedCashLabel,
                  projectedCashLabel: projectedCashLabel,
                  projectedCashContextLabel: projectedCashContextLabel,
                ),
                if (statusState != null) ...[
                  const SizedBox(height: AppSpacing.x4),
                  InteractionStatusLayer(
                    state: statusState,
                    message: statusMessage ?? _defaultStatusMessage,
                  ),
                ],
                if (state == PropertyManagementViewState.confirmed) ...[
                  const SizedBox(height: AppSpacing.x4),
                  _ConfirmationNotice(
                    message:
                        confirmationMessage ??
                        'Acción confirmada. Esperando el estado actualizado.',
                  ),
                ],
                const SizedBox(height: AppSpacing.x5),
                Text(
                  'ACCIONES',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppPalette.primary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.x2),
                if (actions.isEmpty)
                  const _NoActionsMessage()
                else
                  for (var index = 0; index < actions.length; index++) ...[
                    _PropertyActionTile(
                      action: actions[index],
                      feedbackState: _feedbackStateFor(actions[index]),
                      disabledReason: _disabledReasonFor(actions[index]),
                      onPressed: onAction == null
                          ? null
                          : () => onAction!(actions[index].kind),
                    ),
                    if (index != actions.length - 1)
                      const SizedBox(height: AppSpacing.x3),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  InteractionFeedbackState? get _statusFeedbackState => switch (state) {
    PropertyManagementViewState.available ||
    PropertyManagementViewState.confirmed => null,
    PropertyManagementViewState.pending => InteractionFeedbackState.pending,
    PropertyManagementViewState.stale => InteractionFeedbackState.stale,
    PropertyManagementViewState.rejected => InteractionFeedbackState.rejected,
    PropertyManagementViewState.uncertain => InteractionFeedbackState.uncertain,
    PropertyManagementViewState.offline => InteractionFeedbackState.offline,
  };

  String get _defaultStatusMessage => switch (state) {
    PropertyManagementViewState.pending => 'Esperando confirmación. Efectivo y mejoras siguen mostrando el último estado confirmado.',
    PropertyManagementViewState.stale =>
      'Esto cambió mientras mirabas. Actualizando acciones disponibles.',
    PropertyManagementViewState.rejected =>
      'La acción no fue aplicada. Conservamos el último estado confirmado.',
    PropertyManagementViewState.uncertain =>
      'Confirmando qué pasó antes de permitir otra acción equivalente.',
    PropertyManagementViewState.offline =>
      'Reconectando antes de habilitar cambios sobre esta propiedad.',
    _ => '',
  };

  InteractionFeedbackState _feedbackStateFor(
    PropertyManagementActionView action,
  ) {
    return switch (state) {
      PropertyManagementViewState.available =>
        action.enabled
            ? InteractionFeedbackState.idle
            : InteractionFeedbackState.disabled,
      PropertyManagementViewState.pending when pendingAction == action.kind =>
        InteractionFeedbackState.pending,
      PropertyManagementViewState.pending => InteractionFeedbackState.disabled,
      PropertyManagementViewState.confirmed ||
      PropertyManagementViewState.stale ||
      PropertyManagementViewState.rejected => InteractionFeedbackState.disabled,
      PropertyManagementViewState.uncertain =>
        InteractionFeedbackState.uncertain,
      PropertyManagementViewState.offline => InteractionFeedbackState.offline,
    };
  }

  String? _disabledReasonFor(PropertyManagementActionView action) {
    return switch (state) {
      PropertyManagementViewState.available =>
        action.enabled ? null : action.disabledReason,
      PropertyManagementViewState.pending when pendingAction == action.kind =>
        null,
      PropertyManagementViewState.pending =>
        'Esperando confirmación de otra acción',
      PropertyManagementViewState.confirmed => 'Esperando estado actualizado',
      PropertyManagementViewState.stale ||
      PropertyManagementViewState.rejected => 'La situación cambió',
      PropertyManagementViewState.uncertain ||
      PropertyManagementViewState.offline => null,
    };
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

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
    required this.ownerLabel,
    required this.groupLabel,
    required this.groupStatusLabel,
    required this.groupSignalColor,
  });

  final String propertyLabel;
  final String ownerLabel;
  final String groupLabel;
  final String groupStatusLabel;
  final Color groupSignalColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          '$propertyLabel. Propietario: $ownerLabel. Grupo $groupLabel. $groupStatusLabel.',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 58,
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
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  '$groupLabel · $groupStatusLabel',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppPalette.inkSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Propietario: $ownerLabel',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppPalette.inkSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImprovementPanel extends StatelessWidget {
  const _ImprovementPanel({
    required this.improvementLevel,
    this.nextImprovementLabel,
    this.nextImprovementCostLabel,
  });

  final int improvementLevel;
  final String? nextImprovementLabel;
  final String? nextImprovementCostLabel;

  String get _levelLabel => switch (improvementLevel) {
    0 => 'Sin Manís',
    5 => 'Popón',
    1 => '1 Maní',
    _ => '$improvementLevel Manís',
  };

  @override
  Widget build(BuildContext context) {
    final next = [?nextImprovementLabel, ?nextImprovementCostLabel].join(' · ');

    return Semantics(
      container: true,
      label:
          'Nivel de mejoras: $_levelLabel.${next.isEmpty ? '' : ' Próxima mejora: $next.'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.x3),
        decoration: BoxDecoration(
          color: AppPalette.canvas,
          border: Border.all(color: AppPalette.ink.withValues(alpha: 0.16)),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Mejoras',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  _levelLabel,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x3),
            if (improvementLevel == 5)
              const _PoponMarker()
            else
              _ManiMarkers(level: improvementLevel),
            if (next.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.x3),
              Text(
                'Próxima: $next',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppPalette.inkSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ManiMarkers extends StatelessWidget {
  const _ManiMarkers({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        children: List.generate(4, (index) {
          final active = index < level;
          return Padding(
            padding: EdgeInsets.only(right: index == 3 ? 0 : AppSpacing.x2),
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppPalette.ritual : Colors.transparent,
                border: Border.all(
                  color: active ? AppPalette.ink : AppPalette.inkSecondary,
                  width: 1.4,
                ),
                shape: BoxShape.circle,
              ),
              child: Text(
                'M',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _PoponMarker extends StatelessWidget {
  const _PoponMarker();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x3,
          vertical: AppSpacing.x2,
        ),
        decoration: BoxDecoration(
          color: AppPalette.ritual.withValues(alpha: 0.2),
          border: Border.all(color: AppPalette.ink, width: 1.4),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pets_rounded, size: 20),
            const SizedBox(width: AppSpacing.x2),
            Text(
              'POPÓN',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 0.8),
            ),
          ],
        ),
      ),
    );
  }
}

class _EconomyPanel extends StatelessWidget {
  const _EconomyPanel({
    required this.rentLabel,
    required this.mortgageStatusLabel,
    required this.mortgageValueLabel,
  });

  final String rentLabel;
  final String mortgageStatusLabel;
  final String mortgageValueLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          'Alquiler actual: $rentLabel. Hipoteca: $mortgageStatusLabel. $mortgageValueLabel.',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.x3),
        decoration: BoxDecoration(
          border: Border.all(color: AppPalette.ink.withValues(alpha: 0.16)),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          children: [
            _EconomyRow(
              icon: Icons.receipt_long_outlined,
              label: 'Alquiler actual',
              value: rentLabel,
            ),
            const SizedBox(height: AppSpacing.x3),
            _EconomyRow(
              icon: Icons.lock_outline_rounded,
              label: mortgageStatusLabel,
              value: mortgageValueLabel,
            ),
          ],
        ),
      ),
    );
  }
}

class _EconomyRow extends StatelessWidget {
  const _EconomyRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppPalette.inkSecondary),
        const SizedBox(width: AppSpacing.x3),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppPalette.inkSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.x3),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _CashPanel extends StatelessWidget {
  const _CashPanel({
    required this.confirmedCashLabel,
    this.projectedCashLabel,
    this.projectedCashContextLabel,
  });

  final String confirmedCashLabel;
  final String? projectedCashLabel;
  final String? projectedCashContextLabel;

  @override
  Widget build(BuildContext context) {
    final projectedContext = projectedCashContextLabel ?? 'tras esta acción';
    final semanticsLabel = projectedCashLabel == null
        ? 'Efectivo confirmado: $confirmedCashLabel.'
        : 'Efectivo confirmado: $confirmedCashLabel. Proyectado $projectedContext: $projectedCashLabel.';

    return Semantics(
      container: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.x3),
            decoration: BoxDecoration(
              color: AppPalette.info.withValues(alpha: 0.06),
              border: Border.all(
                color: AppPalette.info.withValues(alpha: 0.35),
              ),
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: _CashLine(
              label: 'Efectivo confirmado',
              value: confirmedCashLabel,
              emphasized: true,
            ),
          ),
          if (projectedCashLabel != null) ...[
            const SizedBox(height: AppSpacing.x2),
            Container(
              padding: const EdgeInsets.all(AppSpacing.x3),
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppPalette.inkSecondary.withValues(alpha: 0.3),
                ),
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: _CashLine(
                label: 'Proyectado $projectedContext',
                value: projectedCashLabel!,
                emphasized: false,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CashLine extends StatelessWidget {
  const _CashLine({
    required this.label,
    required this.value,
    required this.emphasized,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: emphasized ? AppPalette.ink : AppPalette.inkSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.x3),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _PropertyActionTile extends StatelessWidget {
  const _PropertyActionTile({
    required this.action,
    required this.feedbackState,
    required this.disabledReason,
    required this.onPressed,
  });

  final PropertyManagementActionView action;
  final InteractionFeedbackState feedbackState;
  final String? disabledReason;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final actionable =
        feedbackState == InteractionFeedbackState.idle && onPressed != null;
    final pending = feedbackState == InteractionFeedbackState.pending;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final semanticState = switch (feedbackState) {
      InteractionFeedbackState.pending =>
        '${action.pendingLabel}. Esperando confirmación.',
      InteractionFeedbackState.disabled when disabledReason != null =>
        'No disponible: $disabledReason.',
      InteractionFeedbackState.uncertain =>
        'No disponible mientras se confirma qué pasó.',
      InteractionFeedbackState.offline =>
        'No disponible mientras se reconecta.',
      _ => '',
    };
    final semanticLabel = [
      action.label,
      action.consequenceLabel,
      if (semanticState.isNotEmpty) semanticState,
    ].join('. ');

    return Semantics(
      button: true,
      enabled: actionable,
      label: semanticLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSizes.primaryControlHeight,
            ),
            child: OutlinedButton.icon(
              onPressed: actionable ? onPressed : null,
              icon: pending
                  ? SizedBox.square(
                      dimension: 18,
                      child: reduceMotion
                          ? const Icon(Icons.more_horiz_rounded, size: 18)
                          : const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_iconFor(action.kind), size: 20),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pending ? action.pendingLabel : action.label),
                    Text(
                      action.consequenceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (feedbackState == InteractionFeedbackState.disabled &&
              disabledReason != null) ...[
            const SizedBox(height: AppSpacing.x2),
            Text(
              disabledReason!,
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

  IconData _iconFor(PropertyManagementActionKind kind) => switch (kind) {
    PropertyManagementActionKind.addMani => Icons.add_home_work_outlined,
    PropertyManagementActionKind.sellImprovement =>
      Icons.remove_circle_outline_rounded,
    PropertyManagementActionKind.mortgage => Icons.lock_outline_rounded,
    PropertyManagementActionKind.unmortgage => Icons.lock_open_rounded,
  };
}

class _ConfirmationNotice extends StatelessWidget {
  const _ConfirmationNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.x3),
        decoration: BoxDecoration(
          color: AppPalette.info.withValues(alpha: 0.08),
          border: Border.all(color: AppPalette.info),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              color: AppPalette.info,
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppPalette.info,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoActionsMessage extends StatelessWidget {
  const _NoActionsMessage();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x3),
      decoration: BoxDecoration(
        color: AppPalette.canvas,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: const Text('No hay acciones disponibles en este estado.'),
    );
  }
}
