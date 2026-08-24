import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/ui/results/results_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unconfirmed_result_hides_ranking_and_exit_actions', (tester) async {
    await tester.pumpWidget(
      _surface(
        state: ResultsSurfaceState.pending,
        ranking: _ranking,
      ),
    );

    expect(find.text('CIERRE EN CURSO'), findsOneWidget);
    expect(find.text('TODAVÍA NO MOSTRAMOS GANADOR'), findsOneWidget);
    expect(find.text('ROMINA PLACEHOLDER'), findsNothing);
    expect(find.text('REVANCHA'), findsNothing);
    expect(find.text('NUEVA PARTIDA'), findsNothing);
    expect(find.text('SALIR'), findsNothing);
  });

  testWidgets('confirmed_result_renders_caller_owned_ranking_and_breakdown', (
    tester,
  ) async {
    await tester.pumpWidget(
      _surface(
        state: ResultsSurfaceState.confirmed,
        ranking: _ranking,
      ),
    );

    expect(find.text('RESULTADO CONFIRMADO'), findsOneWidget);
    expect(find.text('EXPRESS PLACEHOLDER'), findsOneWidget);
    expect(find.text('FIN DE RONDAS PLACEHOLDER'), findsOneWidget);
    expect(find.text('ROMINA PLACEHOLDER'), findsOneWidget);
    expect(find.text('LEO PLACEHOLDER'), findsOneWidget);
    expect(find.text(r'$1.250 PLACEHOLDER'), findsOneWidget);
    expect(find.text('POSICIÓN COMPARTIDA'), findsOneWidget);
    expect(find.text('Efectivo'), findsNWidgets(2));
    expect(find.text('Propiedades'), findsNWidgets(2));
    expect(find.text('Deuda hipotecaria'), findsNWidgets(2));
    expect(find.text('Mejoras'), findsNWidgets(2));
  });

  testWidgets('shared_place_is_exposed_without_local_tiebreak_copy', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _surface(
        state: ResultsSurfaceState.confirmed,
        ranking: _ranking,
      ),
    );

    expect(
      find.bySemanticsLabel(
        RegExp(
          r'2.º PLACEHOLDER.*LEO PLACEHOLDER.*Posición compartida.*Patrimonio',
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('desempate'), findsNothing);

    semantics.dispose();
  });

  testWidgets('confirmed_actions_delegate_navigation_intent_to_caller', (
    tester,
  ) async {
    var rematch = 0;
    var newGame = 0;
    var exit = 0;

    await tester.pumpWidget(
      _surface(
        state: ResultsSurfaceState.confirmed,
        ranking: _ranking,
        onRematch: () => rematch += 1,
        onNewGame: () => newGame += 1,
        onExit: () => exit += 1,
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'REVANCHA'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'NUEVA PARTIDA'));
    await tester.tap(find.widgetWithText(TextButton, 'SALIR'));
    await tester.pump();

    expect(rematch, 1);
    expect(newGame, 1);
    expect(exit, 1);
  });

  testWidgets('offline_result_keeps_confirmed_ranking_hidden', (tester) async {
    await tester.pumpWidget(
      _surface(
        state: ResultsSurfaceState.offline,
        ranking: _ranking,
      ),
    );

    expect(
      find.text('Reconectando. No mostramos un ranking nuevo sin confirmación.'),
      findsOneWidget,
    );
    expect(find.text('ROMINA PLACEHOLDER'), findsNothing);
    expect(find.text('RESULTADO CONFIRMADO'), findsNothing);
  });

  testWidgets('confirmed_empty_ranking_has_factual_fallback', (tester) async {
    await tester.pumpWidget(
      _surface(
        state: ResultsSurfaceState.confirmed,
        ranking: const [],
      ),
    );

    expect(
      find.text('La partida confirmó el cierre sin un ranking para mostrar.'),
      findsOneWidget,
    );
    expect(find.text('REVANCHA'), findsOneWidget);
  });

  testWidgets('compact_results_render_at_360dp_and_130_percent_text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 720,
              child: MediaQuery(
                data: const MediaQueryData(
                  size: Size(360, 720),
                  textScaler: TextScaler.linear(1.3),
                  disableAnimations: true,
                ),
                child: ResultsSurface(
                  state: ResultsSurfaceState.confirmed,
                  modeLabel: 'EXPRESS PLACEHOLDER CON ETIQUETA LARGA',
                  endReasonLabel: 'FIN CONFIRMADO PLACEHOLDER CON TEXTO LARGO',
                  ranking: _ranking,
                  onRematch: () {},
                  onNewGame: () {},
                  onExit: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('RESULTADO CONFIRMADO'), findsOneWidget);
    expect(find.text('ROMINA PLACEHOLDER'), findsOneWidget);
    expect(find.text('REVANCHA'), findsOneWidget);
  });
}

const _ranking = <ResultParticipantView>[
  ResultParticipantView(
    playerLabel: 'ROMINA PLACEHOLDER',
    placementLabel: '1.º PLACEHOLDER',
    netWorthLabel: r'$1.250 PLACEHOLDER',
    isWinner: true,
    breakdown: NetWorthBreakdownView(
      cashLabel: r'$500 PLACEHOLDER',
      propertiesLabel: r'$600 PLACEHOLDER',
      mortgageDebtLabel: r'-$100 PLACEHOLDER',
      improvementsLabel: r'$250 PLACEHOLDER',
    ),
  ),
  ResultParticipantView(
    playerLabel: 'LEO PLACEHOLDER',
    placementLabel: '2.º PLACEHOLDER',
    netWorthLabel: r'$980 PLACEHOLDER',
    isSharedPlace: true,
    breakdown: NetWorthBreakdownView(
      cashLabel: r'$320 PLACEHOLDER',
      propertiesLabel: r'$500 PLACEHOLDER',
      mortgageDebtLabel: r'-$40 PLACEHOLDER',
      improvementsLabel: r'$200 PLACEHOLDER',
    ),
  ),
];

Widget _surface({
  required ResultsSurfaceState state,
  List<ResultParticipantView> ranking = const [],
  VoidCallback? onRematch,
  VoidCallback? onNewGame,
  VoidCallback? onExit,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: ResultsSurface(
        state: state,
        modeLabel: 'EXPRESS PLACEHOLDER',
        endReasonLabel: 'FIN DE RONDAS PLACEHOLDER',
        ranking: ranking,
        onRematch: onRematch,
        onNewGame: onNewGame,
        onExit: onExit,
      ),
    ),
  );
}
