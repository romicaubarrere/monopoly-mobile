import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/design_system/visual_components.dart';
import 'package:board_mobile/ui/cucha/cucha_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cucha_renders_only_caller_supplied_valid_actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _surface(
        actions: const [
          CuchaActionView(
            id: 'roll',
            label: 'Intentar dobles',
            pendingLabel: 'Tirando…',
          ),
          CuchaActionView(
            id: 'card',
            label: 'Usar carta',
            pendingLabel: 'Usando carta…',
          ),
        ],
      ),
    );

    expect(find.text('Intentar dobles'), findsOneWidget);
    expect(find.text('Usar carta'), findsOneWidget);
    expect(find.text(r'Pagar $50'), findsNothing);
  });

  testWidgets('cucha_action_emits_intent_without_local_consumption', (
    tester,
  ) async {
    String? selectedAction;

    await tester.pumpWidget(_surface(onAction: (id) => selectedAction = id));

    await tester.tap(find.widgetWithText(OutlinedButton, r'Pagar $50'));
    await tester.pump();

    expect(selectedAction, 'pay');
    expect(find.text(r'Pagar $50'), findsOneWidget);
    expect(find.text('Esperando confirmación…'), findsNothing);
  });

  testWidgets(
    'cucha_pending_blocks_conflicting_actions_and_preserves_context',
    (tester) async {
      var emitted = 0;

      await tester.pumpWidget(
        _surface(
          state: CuchaSurfaceState.pending,
          pendingActionId: 'pay',
          onAction: (_) => emitted += 1,
        ),
      );

      expect(find.text('Pagando…'), findsOneWidget);
      expect(find.text('CAÍSTE POR UNA CARTA SINTÉTICA'), findsOneWidget);
      expect(
        find.text(
          'Esperando confirmación. Todavía no se consumió efectivo ni carta en esta presentación.',
        ),
        findsOneWidget,
      );

      for (final button in tester.widgetList<OutlinedButton>(
        find.byType(OutlinedButton),
      )) {
        expect(button.onPressed, isNull);
      }
      expect(emitted, 0);
    },
  );

  testWidgets('cucha_uncertain_freezes_actions_and_exposes_status', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _surface(state: CuchaSurfaceState.uncertain, onAction: (_) {}),
    );

    expect(
      find.text(
        'Confirmando qué pasó antes de permitir otra opción equivalente.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Intentar dobles. No disponible: Confirmando qué pasó',
      ),
      findsOneWidget,
    );

    semantics.dispose();
  });

  testWidgets(
    'compact_cucha_remains_renderable_at_360dp_and_130_percent_text',
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
                child: CuchaSurface(
                  statusLabel: 'Seguís en la Cucha; elegí una salida confirmada por la partida.',
                  entryReason: 'Tercer doble confirmado',
                  actions: _actions,
                  state: CuchaSurfaceState.available,
                  onAction: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('A LA CUCHA'), findsOneWidget);
      expect(find.text('Intentar dobles'), findsOneWidget);
      expect(find.text(r'Pagar $50'), findsOneWidget);
      expect(find.text('Usar carta'), findsOneWidget);
    },
  );

  testWidgets('cucha_uses_explicit_source_photo_character_placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(_surface());

    expect(find.byType(PaperPanel), findsAtLeastNWidgets(3));
    expect(find.byType(StampBadge), findsOneWidget);
    expect(find.text('LA MANÍ'), findsOneWidget);
    expect(
      find.text('ILUSTRACIÓN PENDIENTE · usar foto fuente'),
      findsOneWidget,
    );
  });
}

const _actions = <CuchaActionView>[
  CuchaActionView(
    id: 'roll',
    label: 'Intentar dobles',
    pendingLabel: 'Tirando…',
    detail: 'La partida decide el resultado.',
  ),
  CuchaActionView(
    id: 'pay',
    label: r'Pagar $50',
    pendingLabel: 'Pagando…',
    detail: 'El efectivo cambia solo después de la confirmación.',
  ),
  CuchaActionView(
    id: 'card',
    label: 'Usar carta',
    pendingLabel: 'Usando carta…',
    detail: 'La carta se consume solo después de la confirmación.',
  ),
];

Widget _surface({
  List<CuchaActionView> actions = _actions,
  CuchaSurfaceState state = CuchaSurfaceState.available,
  String? pendingActionId,
  ValueChanged<String>? onAction,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: CuchaSurface(
      statusLabel: 'Estás en la Cucha.',
      entryReason: 'Caíste por una carta sintética',
      actions: actions,
      state: state,
      pendingActionId: pendingActionId,
      onAction: onAction,
    ),
  );
}
