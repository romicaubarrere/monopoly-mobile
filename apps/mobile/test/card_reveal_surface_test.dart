import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/design_system/visual_components.dart';
import 'package:board_mobile/ui/cards/card_reveal_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('automatic_card_is_presentational_without_action_cta', (
    tester,
  ) async {
    await tester.pumpWidget(_surface());

    expect(find.text('DE ARRIBA'), findsOneWidget);
    expect(find.text('[COPY SINTÉTICA DE PRUEBA]'), findsOneWidget);
    expect(find.text('Impacto confirmado de prueba'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('choice_card_emits_only_caller_supplied_action_id', (
    tester,
  ) async {
    String? selectedAction;

    await tester.pumpWidget(
      _surface(actions: _actions, onAction: (id) => selectedAction = id),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Opción sintética A'));
    await tester.pump();

    expect(selectedAction, 'choice-a');
    expect(find.text('[COPY SINTÉTICA DE PRUEBA]'), findsOneWidget);
    expect(find.text('Esperando confirmación…'), findsNothing);
  });

  testWidgets('pending_card_freezes_choices_and_preserves_confirmed_copy', (
    tester,
  ) async {
    var emitted = 0;

    await tester.pumpWidget(
      _surface(
        state: CardRevealState.pending,
        actions: _actions,
        pendingActionId: 'choice-a',
        onAction: (_) => emitted += 1,
      ),
    );

    expect(find.text('Confirmando opción A…'), findsOneWidget);
    expect(find.text('[COPY SINTÉTICA DE PRUEBA]'), findsOneWidget);
    expect(
      find.text(
        'Esperando confirmación. La carta visible no ejecuta el efecto otra vez.',
      ),
      findsOneWidget,
    );

    for (final button in tester.widgetList<FilledButton>(
      find.byType(FilledButton),
    )) {
      expect(button.onPressed, isNull);
    }
    expect(emitted, 0);
  });

  testWidgets('keep_card_receipt_only_renders_after_confirmed_flag', (
    tester,
  ) async {
    await tester.pumpWidget(
      _surface(
        category: CardEffectCategory.keepCard,
        state: CardRevealState.confirmed,
        keepCardConfirmed: true,
      ),
    );

    expect(find.text('GUARDABLE'), findsOneWidget);
    expect(find.text('GUARDADA'), findsOneWidget);
  });

  testWidgets('uncertain_offline_and_stale_do_not_offer_new_intent', (
    tester,
  ) async {
    for (final state in const [
      CardRevealState.uncertain,
      CardRevealState.offline,
      CardRevealState.stale,
    ]) {
      await tester.pumpWidget(
        _surface(state: state, actions: _actions, onAction: (_) {}),
      );

      for (final button in tester.widgetList<FilledButton>(
        find.byType(FilledButton),
      )) {
        expect(button.onPressed, isNull);
      }
    }
  });

  testWidgets(
    'compact_card_reveal_remains_renderable_at_360dp_and_130_percent_text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Center(
            child: SizedBox(
              width: 360,
              height: 720,
              child: MediaQuery(
                data: const MediaQueryData(
                  size: Size(360, 720),
                  textScaler: TextScaler.linear(1.3),
                  disableAnimations: true,
                ),
                child: CardRevealSurface(
                  deck: CardDeckKind.deGarron,
                  cardId: 'CARD-PLACEHOLDER-02',
                  copy: '[COPY SINTÉTICA LARGA PARA VALIDAR REFLOW SIN CONVERTIRSE EN CONTENIDO CANÓNICO DEC-065]',
                  category: CardEffectCategory.interaction,
                  state: CardRevealState.available,
                  impactSummary: 'Resumen de impacto confirmado también sintético y deliberadamente largo.',
                  actions: _actions,
                  reducedMotion: true,
                  onAction: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('DE GARRÓN'), findsOneWidget);
      expect(find.text('Opción sintética A'), findsOneWidget);
      expect(find.text('Opción sintética B'), findsOneWidget);
    },
  );

  testWidgets('reduced_motion_preserves_content_with_zero_reveal_duration', (
    tester,
  ) async {
    await tester.pumpWidget(_surface(reducedMotion: true));

    final reveal = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(reveal.duration, Duration.zero);
    expect(find.text('[COPY SINTÉTICA DE PRUEBA]'), findsOneWidget);
    expect(find.byType(PaperPanel), findsAtLeastNWidgets(3));
    expect(find.byType(StampBadge), findsAtLeastNWidgets(2));
  });
}

const _actions = <CardRevealActionView>[
  CardRevealActionView(
    id: 'choice-a',
    label: 'Opción sintética A',
    pendingLabel: 'Confirmando opción A…',
    detail: 'La partida revalida esta elección.',
  ),
  CardRevealActionView(
    id: 'choice-b',
    label: 'Opción sintética B',
    pendingLabel: 'Confirmando opción B…',
  ),
];

Widget _surface({
  CardRevealState state = CardRevealState.available,
  CardEffectCategory category = CardEffectCategory.money,
  List<CardRevealActionView> actions = const [],
  String? pendingActionId,
  bool keepCardConfirmed = false,
  bool reducedMotion = false,
  ValueChanged<String>? onAction,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: CardRevealSurface(
      deck: CardDeckKind.deArriba,
      cardId: 'CARD-PLACEHOLDER-01',
      copy: '[COPY SINTÉTICA DE PRUEBA]',
      category: category,
      state: state,
      impactSummary: 'Impacto confirmado de prueba',
      actions: actions,
      pendingActionId: pendingActionId,
      keepCardConfirmed: keepCardConfirmed,
      reducedMotion: reducedMotion,
      onAction: onAction,
    ),
  );
}
