import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';
import '../feedback/interaction_feedback_state.dart';
import '../feedback/interaction_status_layer.dart';

enum ResultsSurfaceState { pending, stale, uncertain, offline, confirmed }

class NetWorthBreakdownView {
  const NetWorthBreakdownView({
    required this.cashLabel,
    required this.propertiesLabel,
    required this.mortgageDebtLabel,
    required this.improvementsLabel,
  });

  final String cashLabel;
  final String propertiesLabel;
  final String mortgageDebtLabel;
  final String improvementsLabel;
}

class ResultParticipantView {
  const ResultParticipantView({
    required this.playerLabel,
    required this.placementLabel,
    required this.netWorthLabel,
    required this.breakdown,
    this.isWinner = false,
    this.isSharedPlace = false,
  });

  final String playerLabel;
  final String placementLabel;
  final String netWorthLabel;
  final NetWorthBreakdownView breakdown;
  final bool isWinner;
  final bool isSharedPlace;
}

class ResultsSurface extends StatelessWidget {
  const ResultsSurface({
    required this.state,
    required this.modeLabel,
    required this.endReasonLabel,
    required this.ranking,
    this.statusMessage,
    this.onRematch,
    this.onNewGame,
    this.onExit,
    super.key,
  });

  final ResultsSurfaceState state;
  final String modeLabel;
  final String endReasonLabel;
  final List<ResultParticipantView> ranking;
  final String? statusMessage;
  final VoidCallback? onRematch;
  final VoidCallback? onNewGame;
  final VoidCallback? onExit;

  bool get _isConfirmed => state == ResultsSurfaceState.confirmed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.canvas,
      child: SafeArea(
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: _isConfirmed
              ? 'Resultados confirmados. $modeLabel. $endReasonLabel.'
              : 'Resultado todavía no confirmado. $modeLabel.',
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.x4,
                    AppSpacing.x4,
                    AppSpacing.x4,
                    AppSpacing.x6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ResultsHeader(
                        confirmed: _isConfirmed,
                        modeLabel: modeLabel,
                        endReasonLabel: endReasonLabel,
                      ),
                      if (!_isConfirmed) ...[
                        const SizedBox(height: AppSpacing.x4),
                        InteractionStatusLayer(
                          state: _feedbackState,
                          message: statusMessage ?? _defaultStatusMessage,
                        ),
                        const SizedBox(height: AppSpacing.x4),
                        const _UnconfirmedResultNotice(),
                      ],
                      if (_isConfirmed) ...[
                        const SizedBox(height: AppSpacing.x5),
                        _RankingSection(ranking: ranking),
                      ],
                    ],
                  ),
                ),
              ),
              if (_isConfirmed)
                _ResultsFooter(
                  onRematch: onRematch,
                  onNewGame: onNewGame,
                  onExit: onExit,
                ),
            ],
          ),
        ),
      ),
    );
  }

  InteractionFeedbackState get _feedbackState => switch (state) {
    ResultsSurfaceState.pending => InteractionFeedbackState.pending,
    ResultsSurfaceState.stale => InteractionFeedbackState.stale,
    ResultsSurfaceState.uncertain => InteractionFeedbackState.uncertain,
    ResultsSurfaceState.offline => InteractionFeedbackState.offline,
    ResultsSurfaceState.confirmed => InteractionFeedbackState.confirmed,
  };

  String get _defaultStatusMessage => switch (state) {
    ResultsSurfaceState.pending =>
      'Esperando el cierre confirmado de la partida antes de mostrar posiciones.',
    ResultsSurfaceState.stale =>
      'El estado cambió mientras mirabas. Actualizando el cierre confirmado.',
    ResultsSurfaceState.uncertain =>
      'Confirmando si la partida terminó antes de mostrar un resultado final.',
    ResultsSurfaceState.offline =>
      'Reconectando. No mostramos un ranking nuevo sin confirmación.',
    ResultsSurfaceState.confirmed => '',
  };
}

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({
    required this.confirmed,
    required this.modeLabel,
    required this.endReasonLabel,
  });

  final bool confirmed;
  final String modeLabel;
  final String endReasonLabel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        PaperPanel(
          background: AppPalette.surface,
          borderColor: confirmed ? AppPalette.bottleGreen : AppPalette.wornBlue,
          rotation: -0.006,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: StampBadge(
                  label: confirmed ? 'RESULTADO CONFIRMADO' : 'CIERRE EN CURSO',
                  color: confirmed
                      ? AppPalette.bottleGreen
                      : AppPalette.wornBlue,
                  angle: -0.018,
                ),
              ),
              const SizedBox(height: AppSpacing.x4),
              Text(
                'ASÍ QUEDÓ LA PARTIDA',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppPalette.ink,
                  fontWeight: FontWeight.w900,
                  height: 1.02,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: AppSpacing.x3),
              Wrap(
                spacing: AppSpacing.x2,
                runSpacing: AppSpacing.x2,
                children: [
                  StampBadge(label: modeLabel, color: AppPalette.burgundy),
                  if (confirmed)
                    StampBadge(
                      label: endReasonLabel,
                      color: AppPalette.mustard,
                      angle: 0.012,
                    ),
                ],
              ),
            ],
          ),
        ),
        const Positioned(
          right: 34,
          top: -7,
          child: TapeMark(width: 58, angle: 0.05),
        ),
      ],
    );
  }
}

class _UnconfirmedResultNotice extends StatelessWidget {
  const _UnconfirmedResultNotice();

  @override
  Widget build(BuildContext context) {
    return PaperPanel(
      background: AppPalette.kraft,
      borderColor: AppPalette.wornBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'TODAVÍA NO MOSTRAMOS GANADOR',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppPalette.wornBlue,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            'El ranking y el patrimonio aparecen únicamente cuando la partida confirma el cierre.',
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

class _RankingSection extends StatelessWidget {
  const _RankingSection({required this.ranking});

  final List<ResultParticipantView> ranking;

  @override
  Widget build(BuildContext context) {
    if (ranking.isEmpty) {
      return const PaperPanel(
        borderColor: AppPalette.wornBlue,
        child: Text('La partida confirmó el cierre sin un ranking para mostrar.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'RANKING CONFIRMADO',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppPalette.ink,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        for (var index = 0; index < ranking.length; index++) ...[
          _ResultRankingRow(
            key: ValueKey('result-ranking-$index'),
            participant: ranking[index],
          ),
          if (index != ranking.length - 1)
            const SizedBox(height: AppSpacing.x4),
        ],
      ],
    );
  }
}

class _ResultRankingRow extends StatelessWidget {
  const _ResultRankingRow({required this.participant, super.key});

  final ResultParticipantView participant;

  @override
  Widget build(BuildContext context) {
    final borderColor = participant.isWinner
        ? AppPalette.mustard
        : AppPalette.paperEdge;
    final semantics = <String>[
      participant.placementLabel,
      participant.playerLabel,
      if (participant.isSharedPlace) 'Posición compartida',
      'Patrimonio ${participant.netWorthLabel}',
      'Efectivo ${participant.breakdown.cashLabel}',
      'Propiedades ${participant.breakdown.propertiesLabel}',
      'Deuda hipotecaria ${participant.breakdown.mortgageDebtLabel}',
      'Mejoras ${participant.breakdown.improvementsLabel}',
      'Confirmado',
    ].join('. ');

    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: PaperPanel(
        background: participant.isWinner
            ? AppPalette.surface
            : AppPalette.kraft,
        borderColor: borderColor,
        rotation: participant.isWinner ? -0.004 : 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StampBadge(
                  label: participant.placementLabel,
                  color: participant.isWinner
                      ? AppPalette.bottleGreen
                      : AppPalette.wornBlue,
                  angle: participant.isWinner ? -0.02 : 0.01,
                ),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        participant.playerLabel,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppPalette.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (participant.isSharedPlace) ...[
                        const SizedBox(height: AppSpacing.x1),
                        Text(
                          'POSICIÓN COMPARTIDA',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppPalette.burgundy,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                Text(
                  participant.netWorthLabel,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppPalette.burgundy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x4),
            _BreakdownGrid(breakdown: participant.breakdown),
          ],
        ),
      ),
    );
  }
}

class _BreakdownGrid extends StatelessWidget {
  const _BreakdownGrid({required this.breakdown});

  final NetWorthBreakdownView breakdown;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.x3,
      runSpacing: AppSpacing.x3,
      children: [
        _BreakdownItem(label: 'Efectivo', value: breakdown.cashLabel),
        _BreakdownItem(label: 'Propiedades', value: breakdown.propertiesLabel),
        _BreakdownItem(
          label: 'Deuda hipotecaria',
          value: breakdown.mortgageDebtLabel,
        ),
        _BreakdownItem(label: 'Mejoras', value: breakdown.improvementsLabel),
      ],
    );
  }
}

class _BreakdownItem extends StatelessWidget {
  const _BreakdownItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 128),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppPalette.inkSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppPalette.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsFooter extends StatelessWidget {
  const _ResultsFooter({
    required this.onRematch,
    required this.onNewGame,
    required this.onExit,
  });

  final VoidCallback? onRematch;
  final VoidCallback? onNewGame;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
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
          SizedBox(
            height: AppSizes.primaryControlHeight,
            child: FilledButton(
              onPressed: onRematch,
              child: const Text('REVANCHA'),
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          SizedBox(
            height: AppSizes.primaryControlHeight,
            child: OutlinedButton(
              onPressed: onNewGame,
              child: const Text('NUEVA PARTIDA'),
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          SizedBox(
            height: AppSizes.minTouchTarget,
            child: TextButton(onPressed: onExit, child: const Text('SALIR')),
          ),
        ],
      ),
    );
  }
}
