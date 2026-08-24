import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';
import '../feedback/interaction_feedback_state.dart';
import '../feedback/interaction_status_layer.dart';

enum DebtResolutionSurfaceState {
  available,
  pending,
  rejected,
  stale,
  uncertain,
  offline,
  autoResolving,
  covered,
  insolvent,
}

class DebtLiquidationActionView {
  const DebtLiquidationActionView({
    required this.id,
    required this.assetLabel,
    required this.actionLabel,
    required this.cashGainLabel,
    this.detail,
    this.enabled = true,
    this.disabledReason,
  });

  final String id;
  final String assetLabel;
  final String actionLabel;
  final String cashGainLabel;
  final String? detail;
  final bool enabled;
  final String? disabledReason;
}

class DebtAuditEntryView {
  const DebtAuditEntryView({
    required this.label,
    required this.cashDeltaLabel,
    this.detail,
  });

  final String label;
  final String cashDeltaLabel;
  final String? detail;
}

class DebtResolutionSurface extends StatelessWidget {
  const DebtResolutionSurface({
    required this.amountDueLabel,
    required this.confirmedCashLabel,
    required this.missingAmountLabel,
    required this.projectedCashLabel,
    required this.actions,
    required this.auditTrail,
    required this.state,
    this.deadlineLabel,
    this.pendingActionId,
    this.statusMessage,
    this.payActionId,
    this.canPayAndContinue = false,
    this.payDisabledReason,
    this.insolvencyMessage,
    this.onAction,
    super.key,
  });

  final String amountDueLabel;
  final String confirmedCashLabel;
  final String missingAmountLabel;
  final String projectedCashLabel;
  final String? deadlineLabel;
  final List<DebtLiquidationActionView> actions;
  final List<DebtAuditEntryView> auditTrail;
  final DebtResolutionSurfaceState state;
  final String? pendingActionId;
  final String? statusMessage;
  final String? payActionId;
  final bool canPayAndContinue;
  final String? payDisabledReason;
  final String? insolvencyMessage;
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
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Resolución de deuda. Tenés que pagar $amountDueLabel.',
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.x4,
                  AppSpacing.x3,
                  AppSpacing.x4,
                  0,
                ),
                child: _DebtHeader(
                  amountDueLabel: amountDueLabel,
                  confirmedCashLabel: confirmedCashLabel,
                  missingAmountLabel: missingAmountLabel,
                  projectedCashLabel: projectedCashLabel,
                  deadlineLabel: deadlineLabel,
                ),
              ),
              if (feedbackState != null) ...[
                const SizedBox(height: AppSpacing.x3),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x4,
                  ),
                  child: InteractionStatusLayer(
                    state: feedbackState,
                    message: statusMessage ?? _defaultStatusMessage,
                  ),
                ),
              ],
              if (state == DebtResolutionSurfaceState.autoResolving) ...[
                const SizedBox(height: AppSpacing.x3),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.x4),
                  child: _AutomaticResolutionBanner(),
                ),
              ],
              if (state == DebtResolutionSurfaceState.covered) ...[
                const SizedBox(height: AppSpacing.x3),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.x4),
                  child: _OutcomeBanner(
                    icon: Icons.check_circle_outline_rounded,
                    borderColor: AppPalette.bottleGreen,
                    message: 'Deuda cubierta. Esperando el estado confirmado para continuar.',
                  ),
                ),
              ],
              if (state == DebtResolutionSurfaceState.insolvent) ...[
                const SizedBox(height: AppSpacing.x3),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x4,
                  ),
                  child: _OutcomeBanner(
                    icon: Icons.warning_amber_rounded,
                    borderColor: AppPalette.burgundy,
                    message:
                        insolvencyMessage ??
                        'La partida confirmó que no hay una solución manual disponible en este estado.',
                  ),
                ),
              ],
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.x4,
                    AppSpacing.x4,
                    AppSpacing.x4,
                    AppSpacing.x4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionLabel(
                        title: 'ACTIVOS Y ACCIONES',
                        subtitle:
                            'La partida decide qué opciones son válidas y cuánto aportan.',
                      ),
                      const SizedBox(height: AppSpacing.x3),
                      if (actions.isEmpty)
                        const _EmptyActions()
                      else
                        for (var index = 0; index < actions.length; index++) ...[
                          _DebtActionCard(
                            action: actions[index],
                            state: state,
                            pendingActionId: pendingActionId,
                            onAction: onAction,
                          ),
                          if (index != actions.length - 1)
                            const SizedBox(height: AppSpacing.x3),
                        ],
                      const SizedBox(height: AppSpacing.x5),
                      const _SectionLabel(
                        title: 'MOVIMIENTOS CONFIRMADOS',
                        subtitle:
                            'Solo entra acá lo que ya confirmó la partida.',
                      ),
                      const SizedBox(height: AppSpacing.x3),
                      if (auditTrail.isEmpty)
                        const _EmptyAuditTrail()
                      else
                        _AuditTrail(entries: auditTrail),
                    ],
                  ),
                ),
              ),
              _DebtFooter(
                state: state,
                canPayAndContinue: canPayAndContinue,
                payActionId: payActionId,
                payDisabledReason: payDisabledReason,
                onAction: onAction,
              ),
            ],
          ),
        ),
      ),
    );
  }

  InteractionFeedbackState? get _feedbackState => switch (state) {
    DebtResolutionSurfaceState.pending => InteractionFeedbackState.pending,
    DebtResolutionSurfaceState.rejected => InteractionFeedbackState.rejected,
    DebtResolutionSurfaceState.stale => InteractionFeedbackState.stale,
    DebtResolutionSurfaceState.uncertain => InteractionFeedbackState.uncertain,
    DebtResolutionSurfaceState.offline => InteractionFeedbackState.offline,
    _ => null,
  };

  String get _defaultStatusMessage => switch (state) {
    DebtResolutionSurfaceState.pending =>
      'Esperando confirmación. El efectivo confirmado todavía no cambia.',
    DebtResolutionSurfaceState.rejected =>
      'La partida rechazó esa acción. Conservamos el último saldo confirmado.',
    DebtResolutionSurfaceState.stale =>
      'La deuda cambió mientras mirabas. Reconstruyendo desde el estado más reciente.',
    DebtResolutionSurfaceState.uncertain =>
      'Confirmando qué pasó antes de permitir otra acción equivalente.',
    DebtResolutionSurfaceState.offline =>
      'Reconectando. La deuda y el último saldo confirmado siguen visibles.',
    _ => '',
  };
}

class _DebtHeader extends StatelessWidget {
  const _DebtHeader({
    required this.amountDueLabel,
    required this.confirmedCashLabel,
    required this.missingAmountLabel,
    required this.projectedCashLabel,
    required this.deadlineLabel,
  });

  final String amountDueLabel;
  final String confirmedCashLabel;
  final String missingAmountLabel;
  final String projectedCashLabel;
  final String? deadlineLabel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        PaperPanel(
          background: AppPalette.surface,
          borderColor: AppPalette.burgundy,
          padding: const EdgeInsets.all(AppSpacing.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: StampBadge(
                      label: 'RESOLVER DEUDA',
                      color: AppPalette.burgundy,
                      angle: -0.018,
                    ),
                  ),
                  if (deadlineLabel != null &&
                      deadlineLabel!.trim().isNotEmpty) ...[
                    const SizedBox(width: AppSpacing.x3),
                    Flexible(
                      child: Semantics(
                        label: 'Tiempo restante: $deadlineLabel',
                        excludeSemantics: true,
                        child: Text(
                          deadlineLabel!,
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: AppPalette.wornBlue,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.x3),
              Text(
                'Tenés que pagar $amountDueLabel',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppPalette.ink,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: AppSpacing.x3),
              _MoneyRow(
                label: 'Efectivo confirmado',
                value: confirmedCashLabel,
                valueColor: AppPalette.ink,
              ),
              const SizedBox(height: AppSpacing.x2),
              _MoneyRow(
                label: 'Falta',
                value: missingAmountLabel,
                valueColor: AppPalette.burgundy,
              ),
              const SizedBox(height: AppSpacing.x3),
              Semantics(
                container: true,
                label: 'Efectivo proyectado: $projectedCashLabel. No confirmado.',
                excludeSemantics: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x3,
                    vertical: AppSpacing.x2,
                  ),
                  decoration: BoxDecoration(
                    color: AppPalette.kraft,
                    border: Border.all(
                      color: AppPalette.mustard,
                      width: 1.2,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Proyectado',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        projectedCashLabel,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: AppPalette.inkSecondary,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Positioned(
          right: 44,
          top: -7,
          child: TapeMark(width: 58, angle: 0.045),
        ),
      ],
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: valueColor,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppPalette.wornBlue,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppPalette.inkSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DebtActionCard extends StatelessWidget {
  const _DebtActionCard({
    required this.action,
    required this.state,
    required this.pendingActionId,
    required this.onAction,
  });

  final DebtLiquidationActionView action;
  final DebtResolutionSurfaceState state;
  final String? pendingActionId;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) {
    final isPending =
        state == DebtResolutionSurfaceState.pending &&
        pendingActionId == action.id;
    final surfaceAllowsManualAction =
        state == DebtResolutionSurfaceState.available;
    final actionable =
        surfaceAllowsManualAction && action.enabled && onAction != null;
    final reason = _disabledReason;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      container: true,
      button: true,
      enabled: actionable,
      label: actionable
          ? '${action.assetLabel}. ${action.actionLabel}. ${action.cashGainLabel}.'
          : isPending
          ? '${action.assetLabel}. ${action.actionLabel}. Esperando confirmación.'
          : '${action.assetLabel}. ${action.actionLabel}. No disponible: $reason',
      excludeSemantics: true,
      child: PaperPanel(
        background: action.enabled ? AppPalette.surface : AppPalette.kraft,
        borderColor: isPending ? AppPalette.mustard : AppPalette.ink,
        rotation: action.enabled ? -0.003 : 0.002,
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    action.assetLabel,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.x3),
                Text(
                  action.cashGainLabel,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: action.enabled
                        ? AppPalette.bottleGreen
                        : AppPalette.inkSecondary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            if (action.detail != null && action.detail!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.x2),
              Text(
                action.detail!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppPalette.inkSecondary,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.x3),
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSizes.minTouchTarget,
              ),
              child: OutlinedButton(
                onPressed: actionable ? () => onAction!(action.id) : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppPalette.ink,
                  backgroundColor: isPending
                      ? AppPalette.kraft
                      : AppPalette.surface,
                  side: BorderSide(
                    color: isPending ? AppPalette.mustard : AppPalette.ink,
                    width: isPending ? 1.8 : 1.2,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x3,
                    vertical: AppSpacing.x2,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isPending) ...[
                      SizedBox.square(
                        dimension: 18,
                        child: reduceMotion
                            ? const Icon(Icons.more_horiz_rounded, size: 18)
                            : const CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: AppSpacing.x2),
                    ],
                    Flexible(
                      child: Text(
                        isPending ? 'ESPERANDO CONFIRMACIÓN' : action.actionLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!actionable && !isPending) ...[
              const SizedBox(height: AppSpacing.x2),
              Text(
                reason,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

  String get _disabledReason {
    if (!action.enabled) {
      return action.disabledReason ?? 'La partida no permite esta acción ahora';
    }

    return switch (state) {
      DebtResolutionSurfaceState.pending =>
        'Otra acción está esperando confirmación',
      DebtResolutionSurfaceState.rejected =>
        'Esperando el estado actualizado de la deuda',
      DebtResolutionSurfaceState.stale => 'La deuda cambió',
      DebtResolutionSurfaceState.uncertain => 'Confirmando qué pasó',
      DebtResolutionSurfaceState.offline => 'Reconectando',
      DebtResolutionSurfaceState.autoResolving =>
        'La partida está resolviendo automáticamente',
      DebtResolutionSurfaceState.covered => 'La deuda ya quedó cubierta',
      DebtResolutionSurfaceState.insolvent =>
        'No hay una solución manual disponible',
      DebtResolutionSurfaceState.available => 'Acción no conectada',
    };
  }
}

class _AuditTrail extends StatelessWidget {
  const _AuditTrail({required this.entries});

  final List<DebtAuditEntryView> entries;

  @override
  Widget build(BuildContext context) {
    return PaperPanel(
      background: AppPalette.surface,
      borderColor: AppPalette.wornBlue,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < entries.length; index++) ...[
            Padding(
              padding: const EdgeInsets.all(AppSpacing.x3),
              child: Semantics(
                container: true,
                label:
                    '${entries[index].label}. ${entries[index].cashDeltaLabel}. Confirmado.',
                excludeSemantics: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      color: AppPalette.bottleGreen,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entries[index].label,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          if (entries[index].detail != null &&
                              entries[index].detail!.trim().isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.x1),
                            Text(
                              entries[index].detail!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppPalette.inkSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.x3),
                    Text(
                      entries[index].cashDeltaLabel,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppPalette.bottleGreen,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (index != entries.length - 1)
              const Divider(height: 1, color: AppPalette.paperEdge),
          ],
        ],
      ),
    );
  }
}

class _DebtFooter extends StatelessWidget {
  const _DebtFooter({
    required this.state,
    required this.canPayAndContinue,
    required this.payActionId,
    required this.payDisabledReason,
    required this.onAction,
  });

  final DebtResolutionSurfaceState state;
  final bool canPayAndContinue;
  final String? payActionId;
  final String? payDisabledReason;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) {
    final stateAllowsPay = state == DebtResolutionSurfaceState.available;
    final actionable =
        stateAllowsPay &&
        canPayAndContinue &&
        payActionId != null &&
        onAction != null;
    final reason = _disabledReason;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x4,
        AppSpacing.x3,
        AppSpacing.x4,
        AppSpacing.x4,
      ),
      decoration: const BoxDecoration(
        color: AppPalette.canvas,
        border: Border(top: BorderSide(color: AppPalette.paperEdge)),
      ),
      child: Semantics(
        button: true,
        enabled: actionable,
        label: actionable
            ? 'Pagar y continuar'
            : 'Pagar y continuar. No disponible: $reason',
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSizes.primaryControlHeight,
          ),
          child: FilledButton(
            onPressed: actionable ? () => onAction!(payActionId!) : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.bottleGreen,
              foregroundColor: AppPalette.surface,
              disabledBackgroundColor: AppPalette.kraft,
              disabledForegroundColor: AppPalette.inkSecondary,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x4,
                vertical: AppSpacing.x3,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'PAGAR Y CONTINUAR',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                if (!actionable) ...[
                  const SizedBox(height: AppSpacing.x1),
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
          ),
        ),
      ),
    );
  }

  String get _disabledReason {
    if (!canPayAndContinue) {
      return payDisabledReason ?? 'Todavía falta cubrir la deuda';
    }
    if (payActionId == null || onAction == null) {
      return 'Acción no conectada';
    }

    return switch (state) {
      DebtResolutionSurfaceState.pending => 'Esperando confirmación',
      DebtResolutionSurfaceState.rejected =>
        'Esperando el estado actualizado de la deuda',
      DebtResolutionSurfaceState.stale => 'La deuda cambió',
      DebtResolutionSurfaceState.uncertain => 'Confirmando qué pasó',
      DebtResolutionSurfaceState.offline => 'Reconectando',
      DebtResolutionSurfaceState.autoResolving =>
        'La partida está resolviendo automáticamente',
      DebtResolutionSurfaceState.covered => 'La deuda ya quedó cubierta',
      DebtResolutionSurfaceState.insolvent =>
        'No hay una solución manual disponible',
      DebtResolutionSurfaceState.available => 'Acción no disponible',
    };
  }
}

class _AutomaticResolutionBanner extends StatelessWidget {
  const _AutomaticResolutionBanner();

  @override
  Widget build(BuildContext context) {
    return const _OutcomeBanner(
      icon: Icons.autorenew_rounded,
      borderColor: AppPalette.mustard,
      message: 'Resolviendo automáticamente para que la partida continúe.',
    );
  }
}

class _OutcomeBanner extends StatelessWidget {
  const _OutcomeBanner({
    required this.icon,
    required this.borderColor,
    required this.message,
  });

  final IconData icon;
  final Color borderColor;
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
        borderColor: borderColor,
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: borderColor),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyActions extends StatelessWidget {
  const _EmptyActions();

  @override
  Widget build(BuildContext context) {
    return PaperPanel(
      background: AppPalette.surface,
      borderColor: AppPalette.inkSecondary,
      padding: const EdgeInsets.all(AppSpacing.x3),
      child: Text(
        'Esperando acciones válidas del estado confirmado de la deuda.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppPalette.inkSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyAuditTrail extends StatelessWidget {
  const _EmptyAuditTrail();

  @override
  Widget build(BuildContext context) {
    return PaperPanel(
      background: AppPalette.surface,
      borderColor: AppPalette.paperEdge,
      padding: const EdgeInsets.all(AppSpacing.x3),
      child: Text(
        'Todavía no hay movimientos de liquidación confirmados.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppPalette.inkSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
