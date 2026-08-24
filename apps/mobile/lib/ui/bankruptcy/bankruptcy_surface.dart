import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';
import '../feedback/interaction_feedback_state.dart';
import '../feedback/interaction_status_layer.dart';

enum BankruptcySurfaceState {
  insolvent,
  pending,
  rejected,
  stale,
  uncertain,
  offline,
  confirmed,
}

class BankruptcyTransferView {
  const BankruptcyTransferView({
    required this.label,
    this.valueLabel,
    this.detail,
  });

  final String label;
  final String? valueLabel;
  final String? detail;
}

class BankruptcySurface extends StatelessWidget {
  const BankruptcySurface({
    required this.playerLabel,
    required this.state,
    required this.continuationMessage,
    this.reasonLabel,
    this.creditorLabel,
    this.transferSummary = const [],
    this.statusMessage,
    this.actionId,
    this.actionLabel,
    this.actionEnabled = true,
    this.actionDisabledReason,
    this.onAction,
    super.key,
  });

  final String playerLabel;
  final BankruptcySurfaceState state;
  final String continuationMessage;
  final String? reasonLabel;
  final String? creditorLabel;
  final List<BankruptcyTransferView> transferSummary;
  final String? statusMessage;
  final String? actionId;
  final String? actionLabel;
  final bool actionEnabled;
  final String? actionDisabledReason;
  final ValueChanged<String>? onAction;

  bool get _isConfirmed => state == BankruptcySurfaceState.confirmed;

  bool get _hasAction =>
      !_isConfirmed &&
      actionId != null &&
      actionId!.trim().isNotEmpty &&
      actionLabel != null &&
      actionLabel!.trim().isNotEmpty;

  bool get _blocksAction => switch (state) {
    BankruptcySurfaceState.pending ||
    BankruptcySurfaceState.stale ||
    BankruptcySurfaceState.uncertain ||
    BankruptcySurfaceState.offline => true,
    _ => false,
  };

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
          label: _isConfirmed
              ? 'Bancarrota confirmada para $playerLabel.'
              : 'Estado de insolvencia para $playerLabel. Bancarrota no confirmada.',
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.x4,
                    AppSpacing.x4,
                    AppSpacing.x4,
                    AppSpacing.x5,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _BankruptcyHeader(
                        playerLabel: playerLabel,
                        confirmed: _isConfirmed,
                        reasonLabel: reasonLabel,
                      ),
                      if (feedbackState != null) ...[
                        const SizedBox(height: AppSpacing.x4),
                        InteractionStatusLayer(
                          state: feedbackState,
                          message: statusMessage ?? _defaultStatusMessage,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.x5),
                      if (_isConfirmed)
                        _ConfirmedBankruptcySummary(
                          creditorLabel: creditorLabel,
                          transferSummary: transferSummary,
                          continuationMessage: continuationMessage,
                        )
                      else
                        _InsolvencySummary(
                          continuationMessage: continuationMessage,
                        ),
                    ],
                  ),
                ),
              ),
              if (_hasAction)
                _BankruptcyActionFooter(
                  actionId: actionId!,
                  actionLabel: actionLabel!,
                  actionEnabled: actionEnabled && !_blocksAction,
                  disabledReason: _actionDisabledReason,
                  onAction: onAction,
                ),
            ],
          ),
        ),
      ),
    );
  }

  InteractionFeedbackState? get _feedbackState => switch (state) {
    BankruptcySurfaceState.pending => InteractionFeedbackState.pending,
    BankruptcySurfaceState.rejected => InteractionFeedbackState.rejected,
    BankruptcySurfaceState.stale => InteractionFeedbackState.stale,
    BankruptcySurfaceState.uncertain => InteractionFeedbackState.uncertain,
    BankruptcySurfaceState.offline => InteractionFeedbackState.offline,
    _ => null,
  };

  String get _defaultStatusMessage => switch (state) {
    BankruptcySurfaceState.pending =>
      'Esperando confirmación. La bancarrota todavía no está confirmada.',
    BankruptcySurfaceState.rejected =>
      'La partida rechazó esa acción. Volvemos al último estado confirmado.',
    BankruptcySurfaceState.stale => 'La situación cambió mientras mirabas. Reconstruyendo desde el estado más reciente.',
    BankruptcySurfaceState.uncertain =>
      'Confirmando qué pasó antes de permitir otra acción equivalente.',
    BankruptcySurfaceState.offline =>
      'Reconectando. Conservamos el último estado confirmado.',
    _ => '',
  };

  String? get _actionDisabledReason {
    if (_blocksAction) {
      return switch (state) {
        BankruptcySurfaceState.pending => 'Esperando confirmación',
        BankruptcySurfaceState.stale => 'La situación cambió',
        BankruptcySurfaceState.uncertain => 'Confirmando qué pasó',
        BankruptcySurfaceState.offline => 'Reconectando',
        _ => actionDisabledReason,
      };
    }
    return actionEnabled ? null : actionDisabledReason;
  }
}

class _BankruptcyHeader extends StatelessWidget {
  const _BankruptcyHeader({
    required this.playerLabel,
    required this.confirmed,
    required this.reasonLabel,
  });

  final String playerLabel;
  final bool confirmed;
  final String? reasonLabel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        PaperPanel(
          background: AppPalette.surface,
          borderColor: confirmed ? AppPalette.burgundy : AppPalette.mustard,
          padding: const EdgeInsets.all(AppSpacing.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: StampBadge(
                  label: confirmed
                      ? 'BANCARROTA CONFIRMADA'
                      : 'ESTADO DE INSOLVENCIA',
                  color: confirmed ? AppPalette.burgundy : AppPalette.wornBlue,
                  angle: -0.018,
                ),
              ),
              const SizedBox(height: AppSpacing.x4),
              Text(
                playerLabel,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppPalette.ink,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              if (reasonLabel != null && reasonLabel!.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.x2),
                Text(
                  reasonLabel!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppPalette.inkSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.x3),
              Text(
                confirmed
                    ? 'La partida ya confirmó la transición. Este resumen muestra solo el resultado confirmado.'
                    : 'No declaramos una derrota antes de que la partida confirme la bancarrota.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppPalette.inkSecondary, height: 1.3),
              ),
            ],
          ),
        ),
        const Positioned(
          right: 42,
          top: -7,
          child: TapeMark(width: 60, angle: 0.05),
        ),
      ],
    );
  }
}

class _InsolvencySummary extends StatelessWidget {
  const _InsolvencySummary({required this.continuationMessage});

  final String continuationMessage;

  @override
  Widget build(BuildContext context) {
    return PaperPanel(
      background: AppPalette.kraft,
      borderColor: AppPalette.wornBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'TODAVÍA NO ES UN RESULTADO FINAL',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppPalette.wornBlue,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            continuationMessage,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppPalette.ink,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmedBankruptcySummary extends StatelessWidget {
  const _ConfirmedBankruptcySummary({
    required this.creditorLabel,
    required this.transferSummary,
    required this.continuationMessage,
  });

  final String? creditorLabel;
  final List<BankruptcyTransferView> transferSummary;
  final String continuationMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaperPanel(
          borderColor: AppPalette.burgundy,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'QUÉ PASÓ',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppPalette.burgundy,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
              if (creditorLabel != null &&
                  creditorLabel!.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.x3),
                _SummaryRow(label: 'Destino', value: creditorLabel!),
              ],
              const SizedBox(height: AppSpacing.x4),
              if (transferSummary.isEmpty)
                Text(
                  'La partida no entregó un desglose adicional para mostrar.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppPalette.inkSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                for (
                  var index = 0;
                  index < transferSummary.length;
                  index++
                ) ...[
                  _TransferRow(transfer: transferSummary[index]),
                  if (index != transferSummary.length - 1)
                    const Divider(height: AppSpacing.x5),
                ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x4),
        PaperPanel(
          background: AppPalette.kraft,
          borderColor: AppPalette.bottleGreen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Y AHORA',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppPalette.bottleGreen,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: AppSpacing.x2),
              Text(
                continuationMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppPalette.ink,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

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
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppPalette.ink, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({required this.transfer});

  final BankruptcyTransferView transfer;

  @override
  Widget build(BuildContext context) {
    final detail = transfer.detail?.trim();
    final semantics = <String>[
      transfer.label.trim(),
      if (transfer.valueLabel != null && transfer.valueLabel!.trim().isNotEmpty)
        transfer.valueLabel!.trim(),
      if (detail != null && detail.isNotEmpty)
        detail.endsWith('.')
            ? detail.substring(0, detail.length - 1)
            : detail,
      'Confirmado',
    ].join('. ');

    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  transfer.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppPalette.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (transfer.valueLabel != null &&
                  transfer.valueLabel!.trim().isNotEmpty) ...[
                const SizedBox(width: AppSpacing.x3),
                Text(
                  transfer.valueLabel!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppPalette.burgundy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ],
          ),
          if (transfer.detail != null &&
              transfer.detail!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.x1),
            Text(
              transfer.detail!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppPalette.inkSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _BankruptcyActionFooter extends StatelessWidget {
  const _BankruptcyActionFooter({
    required this.actionId,
    required this.actionLabel,
    required this.actionEnabled,
    required this.disabledReason,
    required this.onAction,
  });

  final String actionId;
  final String actionLabel;
  final bool actionEnabled;
  final String? disabledReason;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) {
    final enabled = actionEnabled && onAction != null;
    final semanticLabel = enabled
        ? actionLabel
        : '$actionLabel. No disponible${disabledReason == null ? '' : ': $disabledReason'}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x4,
        AppSpacing.x3,
        AppSpacing.x4,
        AppSpacing.x4,
      ),
      decoration: const BoxDecoration(
        color: AppPalette.surface,
        border: Border(top: BorderSide(color: AppPalette.paperEdge)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            enabled: enabled,
            label: semanticLabel,
            excludeSemantics: true,
            child: SizedBox(
              height: AppSizes.primaryControlHeight,
              child: FilledButton(
                onPressed: enabled ? () => onAction!(actionId) : null,
                child: Text(actionLabel.toUpperCase()),
              ),
            ),
          ),
          if (!enabled &&
              disabledReason != null &&
              disabledReason!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.x2),
            Text(
              disabledReason!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.inkSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}