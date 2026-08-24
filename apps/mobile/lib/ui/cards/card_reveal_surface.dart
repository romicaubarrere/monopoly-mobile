import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';
import '../feedback/interaction_feedback_state.dart';
import '../feedback/interaction_status_layer.dart';

enum CardDeckKind { deArriba, deGarron }

enum CardEffectCategory {
  money,
  movement,
  cucha,
  transport,
  interaction,
  improvements,
  pot,
  keepCard,
}

enum CardRevealState {
  available,
  pending,
  confirmed,
  rejected,
  stale,
  uncertain,
  offline,
}

class CardRevealActionView {
  const CardRevealActionView({
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

class CardRevealSurface extends StatelessWidget {
  const CardRevealSurface({
    required this.deck,
    required this.cardId,
    required this.copy,
    required this.category,
    required this.state,
    super.key,
    this.impactSummary,
    this.actions = const [],
    this.pendingActionId,
    this.keepCardConfirmed = false,
    this.statusMessage,
    this.characterArtwork,
    this.reducedMotion = false,
    this.onAction,
  });

  final CardDeckKind deck;
  final String cardId;
  final String copy;
  final CardEffectCategory category;
  final CardRevealState state;
  final String? impactSummary;
  final List<CardRevealActionView> actions;
  final String? pendingActionId;
  final bool keepCardConfirmed;
  final String? statusMessage;
  final Widget? characterArtwork;
  final bool reducedMotion;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) {
    final feedbackState = _feedbackState;
    final deckPresentation = _presentationForDeck(deck);

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
            label: '${deckPresentation.label}. Carta confirmada $cardId.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _MandatoryHandle(),
                const SizedBox(height: AppSpacing.x3),
                _DeckHeader(presentation: deckPresentation),
                const SizedBox(height: AppSpacing.x3),
                AnimatedContainer(
                  duration: reducedMotion ? Duration.zero : AppMotion.sheet,
                  curve: Curves.easeOutCubic,
                  child: _CardBody(
                    cardId: cardId,
                    copy: copy,
                    category: category,
                    accent: deckPresentation.color,
                    characterArtwork: characterArtwork,
                  ),
                ),
                if (impactSummary != null && impactSummary!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.x3),
                  _ImpactTicket(summary: impactSummary!),
                ],
                if (feedbackState != null) ...[
                  const SizedBox(height: AppSpacing.x3),
                  InteractionStatusLayer(
                    state: feedbackState,
                    message: statusMessage ?? _defaultStatusMessage,
                  ),
                ],
                if (keepCardConfirmed) ...[
                  const SizedBox(height: AppSpacing.x3),
                  const _KeepCardReceipt(),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.x4),
                  for (var index = 0; index < actions.length; index++) ...[
                    _CardActionButton(
                      action: actions[index],
                      surfaceState: state,
                      pendingActionId: pendingActionId,
                      onPressed: onAction,
                    ),
                    if (index != actions.length - 1)
                      const SizedBox(height: AppSpacing.x2),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  InteractionFeedbackState? get _feedbackState => switch (state) {
    CardRevealState.available || CardRevealState.confirmed => null,
    CardRevealState.pending => InteractionFeedbackState.pending,
    CardRevealState.rejected => InteractionFeedbackState.rejected,
    CardRevealState.stale => InteractionFeedbackState.stale,
    CardRevealState.uncertain => InteractionFeedbackState.uncertain,
    CardRevealState.offline => InteractionFeedbackState.offline,
  };

  String get _defaultStatusMessage => switch (state) {
    CardRevealState.pending =>
      'Esperando confirmación. La carta visible no ejecuta el efecto otra vez.',
    CardRevealState.rejected =>
      'La partida no confirmó esa elección. Conservamos el último estado confirmado.',
    CardRevealState.stale =>
      'La decisión cambió. Esperando el estado actualizado de la partida.',
    CardRevealState.uncertain =>
      'Confirmando qué pasó antes de permitir otra elección equivalente.',
    CardRevealState.offline =>
      'Reconectando antes de habilitar una nueva decisión.',
    _ => '',
  };
}

class _DeckPresentation {
  const _DeckPresentation({required this.label, required this.color});

  final String label;
  final Color color;
}

_DeckPresentation _presentationForDeck(CardDeckKind deck) => switch (deck) {
  CardDeckKind.deArriba => const _DeckPresentation(
    label: 'DE ARRIBA',
    color: AppPalette.wornBlue,
  ),
  CardDeckKind.deGarron => const _DeckPresentation(
    label: 'DE GARRÓN',
    color: AppPalette.burgundy,
  ),
};

class _MandatoryHandle extends StatelessWidget {
  const _MandatoryHandle();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Center(
        child: Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: AppPalette.inkSecondary,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );
  }
}

class _DeckHeader extends StatelessWidget {
  const _DeckHeader({required this.presentation});

  final _DeckPresentation presentation;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        PaperPanel(
          background: AppPalette.surface,
          borderColor: presentation.color,
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
                      presentation.label,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: presentation.color,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            height: 1,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.x2),
                    Text(
                      'La partida ya eligió esta carta. Acá solo mostramos su resultado o una decisión pendiente.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.inkSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              const InkDoodle(size: 32),
            ],
          ),
        ),
        const Positioned(
          right: 52,
          top: -6,
          child: TapeMark(width: 52, angle: 0.05),
        ),
      ],
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.cardId,
    required this.copy,
    required this.category,
    required this.accent,
    required this.characterArtwork,
  });

  final String cardId;
  final String copy;
  final CardEffectCategory category;
  final Color accent;
  final Widget? characterArtwork;

  @override
  Widget build(BuildContext context) {
    return PaperPanel(
      background: AppPalette.surface,
      borderColor: AppPalette.ink,
      rotation: -0.004,
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.x2,
                  runSpacing: AppSpacing.x2,
                  children: [
                    StampBadge(
                      label: cardId,
                      color: accent,
                      angle: -0.015,
                    ),
                    StampBadge(
                      label: _categoryLabel(category),
                      color: AppPalette.bottleGreen,
                      angle: 0.012,
                    ),
                  ],
                ),
              ),
              if (characterArtwork != null) ...[
                const SizedBox(width: AppSpacing.x3),
                ExcludeSemantics(
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: characterArtwork,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          Semantics(
            label: 'Texto de la carta: $copy',
            excludeSemantics: true,
            child: Text(
              copy,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppPalette.ink,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _categoryLabel(CardEffectCategory category) => switch (category) {
  CardEffectCategory.money => 'Dinero',
  CardEffectCategory.movement => 'Movimiento',
  CardEffectCategory.cucha => 'Cucha',
  CardEffectCategory.transport => 'Transporte',
  CardEffectCategory.interaction => 'Interacción',
  CardEffectCategory.improvements => 'Mejoras',
  CardEffectCategory.pot => 'Pozo',
  CardEffectCategory.keepCard => 'Guardable',
};

class _ImpactTicket extends StatelessWidget {
  const _ImpactTicket({required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Impacto confirmado: $summary',
      excludeSemantics: true,
      child: PaperPanel(
        background: AppPalette.kraft,
        borderColor: AppPalette.bottleGreen,
        rotation: 0.003,
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.receipt_long_rounded,
              color: AppPalette.bottleGreen,
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'IMPACTO CONFIRMADO',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppPalette.bottleGreen,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  Text(summary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeepCardReceipt extends StatelessWidget {
  const _KeepCardReceipt();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Carta guardada en tu inventario.',
      excludeSemantics: true,
      child: Align(
        alignment: Alignment.centerLeft,
        child: StampBadge(
          label: 'Guardada',
          color: AppPalette.bottleGreen,
          angle: -0.022,
        ),
      ),
    );
  }
}

class _CardActionButton extends StatelessWidget {
  const _CardActionButton({
    required this.action,
    required this.surfaceState,
    required this.pendingActionId,
    required this.onPressed,
  });

  final CardRevealActionView action;
  final CardRevealState surfaceState;
  final String? pendingActionId;
  final ValueChanged<String>? onPressed;

  @override
  Widget build(BuildContext context) {
    final isPending = surfaceState == CardRevealState.pending;
    final isThisPending = isPending && pendingActionId == action.id;
    final enabled = surfaceState == CardRevealState.available && onPressed != null;
    final label = isThisPending ? action.pendingLabel : action.label;

    return Semantics(
      button: true,
      enabled: enabled,
      label: action.detail == null ? label : '$label. ${action.detail}',
      excludeSemantics: true,
      child: FilledButton(
        onPressed: enabled ? () => onPressed!(action.id) : null,
        style: FilledButton.styleFrom(
          minimumSize: const Size(
            double.infinity,
            AppSizes.primaryControlHeight,
          ),
          backgroundColor: AppPalette.primary,
          disabledBackgroundColor: AppPalette.paperEdge,
          disabledForegroundColor: AppPalette.inkSecondary,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isThisPending) ...[
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.x2),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
