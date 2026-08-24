import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';

enum ReconnectPhase {
  networkUnstable,
  reconnecting,
  commandUncertain,
  graceExpiredNotBlocking,
  temporaryBotActive,
  reconnectedWaitingReclaim,
  reclaimConfirmed,
  offline,
}

class ReconnectEventView {
  const ReconnectEventView({required this.title, this.detail});

  final String title;
  final String? detail;
}

class ReconnectTakeoverSurface extends StatelessWidget {
  const ReconnectTakeoverSurface({
    required this.phase,
    required this.playerLabel,
    required this.confirmedContextLabel,
    super.key,
    this.authorityCountdownLabel,
    this.awayEvents = const [],
  });

  final ReconnectPhase phase;
  final String playerLabel;
  final String confirmedContextLabel;
  final String? authorityCountdownLabel;
  final List<ReconnectEventView> awayEvents;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 375;
          final gutter = compact ? AppSpacing.x3 : AppSpacing.x5;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              gutter,
              AppSpacing.x4,
              gutter,
              AppSpacing.x8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatusHeader(phase: phase),
                const SizedBox(height: AppSpacing.x4),
                _PhasePanel(
                  phase: phase,
                  playerLabel: playerLabel,
                  authorityCountdownLabel: authorityCountdownLabel,
                ),
                const SizedBox(height: AppSpacing.x4),
                _ConfirmedContext(label: confirmedContextLabel),
                if (awayEvents.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.x5),
                  _AwaySummary(events: awayEvents),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.phase});

  final ReconnectPhase phase;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            'CONTINUIDAD DE PARTIDA',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 1.2),
          ),
        ),
        const SizedBox(width: AppSpacing.x3),
        StampBadge(label: _badgeLabel(phase), color: _badgeColor(phase)),
      ],
    );
  }
}

class _PhasePanel extends StatelessWidget {
  const _PhasePanel({
    required this.phase,
    required this.playerLabel,
    required this.authorityCountdownLabel,
  });

  final ReconnectPhase phase;
  final String playerLabel;
  final String? authorityCountdownLabel;

  @override
  Widget build(BuildContext context) {
    final title = _phaseTitle(phase);
    final body = _phaseBody(phase, playerLabel);

    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $body',
      child: ExcludeSemantics(
        child: PaperPanel(
          rotation: phase == ReconnectPhase.temporaryBotActive ? -0.006 : 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900, height: 1.05),
              ),
              const SizedBox(height: AppSpacing.x3),
              Text(body),
              if (_showsCountdown(phase) &&
                  authorityCountdownLabel != null) ...[
                const SizedBox(height: AppSpacing.x4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.x3),
                  decoration: BoxDecoration(
                    color: AppPalette.kraft,
                    border: Border.all(color: AppPalette.ink, width: 1.2),
                    borderRadius: BorderRadius.circular(AppRadius.sign),
                  ),
                  child: Text(
                    'GRACIA INFORMADA POR SERVIDOR · $authorityCountdownLabel',
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
              if (phase == ReconnectPhase.temporaryBotActive ||
                  phase == ReconnectPhase.reconnectedWaitingReclaim) ...[
                const SizedBox(height: AppSpacing.x4),
                Wrap(
                  spacing: AppSpacing.x2,
                  runSpacing: AppSpacing.x2,
                  children: [
                    StampBadge(
                      label: playerLabel,
                      color: AppPalette.bottleGreen,
                      angle: -0.018,
                    ),
                    const StampBadge(
                      label: 'BOT TEMPORAL',
                      color: AppPalette.mustard,
                      angle: 0.018,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmedContext extends StatelessWidget {
  const _ConfirmedContext({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Último estado confirmado. $label. Solo lectura.',
      child: PaperPanel(
        background: AppPalette.canvas,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ÚLTIMO ESTADO CONFIRMADO',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppPalette.inkSecondary,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(
              'Solo lectura hasta que el estado autoritativo habilite una acción.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _AwaySummary extends StatelessWidget {
  const _AwaySummary({required this.events});

  final List<ReconnectEventView> events;

  @override
  Widget build(BuildContext context) {
    final visibleEvents = events.take(3).toList(growable: false);

    return PaperPanel(
      background: AppPalette.surface,
      rotation: 0.004,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MIENTRAS ESTABAS FUERA…',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppSpacing.x3),
          for (var index = 0; index < visibleEvents.length; index += 1) ...[
            _AwayEventRow(event: visibleEvents[index]),
            if (index < visibleEvents.length - 1)
              const Divider(height: AppSpacing.x5),
          ],
        ],
      ),
    );
  }
}

class _AwayEventRow extends StatelessWidget {
  const _AwayEventRow({required this.event});

  final ReconnectEventView event;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: event.detail == null
          ? event.title
          : '${event.title}. ${event.detail}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.receipt_long_outlined, size: 20),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (event.detail != null) ...[
                    const SizedBox(height: AppSpacing.x1),
                    Text(event.detail!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _badgeLabel(ReconnectPhase phase) {
  return switch (phase) {
    ReconnectPhase.networkUnstable => 'CONEXIÓN INESTABLE',
    ReconnectPhase.reconnecting => 'RECONECTANDO',
    ReconnectPhase.commandUncertain => 'CONFIRMANDO',
    ReconnectPhase.graceExpiredNotBlocking => 'ESPERANDO SERVIDOR',
    ReconnectPhase.temporaryBotActive => 'BOT TEMPORAL',
    ReconnectPhase.reconnectedWaitingReclaim => 'VOLVISTE',
    ReconnectPhase.reclaimConfirmed => 'CONTROL RECUPERADO',
    ReconnectPhase.offline => 'SIN CONEXIÓN',
  };
}

Color _badgeColor(ReconnectPhase phase) {
  return switch (phase) {
    ReconnectPhase.networkUnstable ||
    ReconnectPhase.reconnecting => AppPalette.wornBlue,
    ReconnectPhase.commandUncertain ||
    ReconnectPhase.graceExpiredNotBlocking ||
    ReconnectPhase.reconnectedWaitingReclaim => AppPalette.mustard,
    ReconnectPhase.temporaryBotActive => AppPalette.burgundy,
    ReconnectPhase.reclaimConfirmed => AppPalette.bottleGreen,
    ReconnectPhase.offline => AppPalette.danger,
  };
}

String _phaseTitle(ReconnectPhase phase) {
  return switch (phase) {
    ReconnectPhase.networkUnstable => 'CONEXIÓN INESTABLE',
    ReconnectPhase.reconnecting => 'RECONECTANDO…',
    ReconnectPhase.commandUncertain => 'CONFIRMANDO TU ACCIÓN…',
    ReconnectPhase.graceExpiredNotBlocking =>
      'TODAVÍA NO HAY BOT TEMPORAL CONFIRMADO',
    ReconnectPhase.temporaryBotActive => 'UN BOT ESTÁ CUBRIENDO TU LUGAR',
    ReconnectPhase.reconnectedWaitingReclaim => 'VOLVISTE',
    ReconnectPhase.reclaimConfirmed => 'VOLVISTE A CONTROLAR TU FICHA',
    ReconnectPhase.offline => 'NO PODEMOS CONFIRMAR CAMBIOS',
  };
}

String _phaseBody(ReconnectPhase phase, String playerLabel) {
  return switch (phase) {
    ReconnectPhase.networkUnstable => 'La partida sigue guardada en el servidor. Conservamos el último estado confirmado.',
    ReconnectPhase.reconnecting => 'Intentamos volver sin reiniciar decisiones ni deadlines. El contador es informativo.',
    ReconnectPhase.commandUncertain => 'Todavía no sabemos si la autoridad confirmó la acción. No mostramos éxito ni habilitamos acciones conflictivas.',
    ReconnectPhase.graceExpiredNotBlocking => 'La gracia terminó, pero la interfaz no afirma takeover hasta recibir un controller confirmado por autoridad.',
    ReconnectPhase.temporaryBotActive =>
      'Un bot está cubriendo el lugar de $playerLabel. Podés volver a conectarte; recuperás el control en un límite estable confirmado.',
    ReconnectPhase.reconnectedWaitingReclaim => 'El bot termina esta acción y después recuperás el control. No interrumpimos una transición autoritativa en curso.',
    ReconnectPhase.reclaimConfirmed => 'El control humano fue confirmado otra vez. Las acciones disponibles dependen del nuevo estado autoritativo.',
    ReconnectPhase.offline => 'No simulamos progreso ni takeover sin autoridad disponible. Conservamos el último estado confirmado.',
  };
}

bool _showsCountdown(ReconnectPhase phase) {
  return phase == ReconnectPhase.reconnecting;
}
