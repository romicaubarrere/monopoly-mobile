import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/design_system/visual_components.dart';
import 'package:board_mobile/ui/feedback/interaction_feedback_state.dart';
import 'package:board_mobile/ui/game_board/board_turn_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('board_turn_surface_renders_exactly_40_synthetic_positions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const BoardTurnSurface(
          currentPlayerLabel: 'Tu turno',
          roundLabel: 'Ronda sintética',
          cashLabel: r'$ —',
          connectionLabel: 'Conectado',
          currentPosition: 7,
          rollState: InteractionFeedbackState.disabled,
          rollDisabledReason: 'Esperando partida confirmada',
        ),
      ),
    );

    for (var index = 0; index < 40; index += 1) {
      expect(find.byKey(ValueKey('board-tile-$index')), findsOneWidget);
    }
  });

  testWidgets('board_almacen_visual_pass_reuses_shared_material_components', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const BoardTurnSurface(
          currentPlayerLabel: 'Tu turno',
          roundLabel: 'Ronda sintética',
          cashLabel: r'$ 1.250',
          connectionLabel: 'Conectado',
          currentPosition: 3,
          rollState: InteractionFeedbackState.idle,
        ),
      ),
    );

    expect(find.byType(PaperPanel), findsNWidgets(2));
    expect(find.byType(StampBadge), findsNWidgets(2));
    expect(find.byType(TapeMark), findsNWidgets(2));
    expect(find.text('TURNO EN EL MOSTRADOR'), findsOneWidget);
    expect(find.text('TABLERO\nEN JUEGO'), findsOneWidget);
    expect(find.text('40 posiciones · estado confirmado'), findsOneWidget);
  });

  testWidgets('dice_display_only_renders_confirmed_values_supplied_by_state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const BoardTurnSurface(
          currentPlayerLabel: 'Tu turno',
          roundLabel: 'Ronda 3',
          cashLabel: r'$ 1500',
          connectionLabel: 'Conectado',
          currentPosition: 8,
          firstDie: 4,
          secondDie: 3,
          highlightedPosition: 15,
          movementSummary: 'Resultado confirmado. Destino resaltado.',
          rollState: InteractionFeedbackState.idle,
        ),
      ),
    );

    expect(
      find.bySemanticsLabel('Dados confirmados: 4 y 3. Total 7.'),
      findsOneWidget,
    );
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('pending_roll_blocks_duplicate_intent_without_hiding_board', (
    tester,
  ) async {
    var calls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: BoardTurnSurface(
          currentPlayerLabel: 'Tu turno',
          roundLabel: 'Ronda 1',
          cashLabel: r'$ —',
          connectionLabel: 'Conectado',
          currentPosition: 0,
          rollState: InteractionFeedbackState.pending,
          onRoll: () => calls += 1,
        ),
      ),
    );

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(calls, 0);
    expect(find.byKey(const ValueKey('board-tile-0')), findsOneWidget);
  });

  testWidgets('board_summary_does_not_force_40_tile_labels_into_semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const BoardTurnSurface(
          currentPlayerLabel: 'Tu turno',
          roundLabel: 'Ronda 2',
          cashLabel: r'$ 900',
          connectionLabel: 'Conectado',
          currentPosition: 11,
          highlightedPosition: 18,
          rollState: InteractionFeedbackState.idle,
        ),
      ),
    );

    expect(
      find.bySemanticsLabel(
        'Tablero de 40 posiciones. Ficha actual en la posición 12. Destino resaltado: posición 19.',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Casillero sintético 1'), findsNothing);

    semantics.dispose();
  });

  testWidgets('compact_board_and_reduced_motion_keep_geometry_renderable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Center(
          child: SizedBox(
            width: 360,
            height: 800,
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.3),
                disableAnimations: true,
              ),
              child: const BoardTurnSurface(
                currentPlayerLabel: 'Turno de jugador con nombre largo',
                roundLabel: 'Ronda sintética de checkpoint',
                cashLabel: r'$ 12.345',
                connectionLabel: 'Reconectado',
                currentPosition: 39,
                highlightedPosition: 4,
                firstDie: 6,
                secondDie: 6,
                movementSummary:
                    'Destino confirmado en estado de presentación.',
                rollState: InteractionFeedbackState.disabled,
                rollDisabledReason: 'Esperando la próxima acción válida',
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final tile = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('board-tile-0')),
    );
    expect(tile.duration, Duration.zero);
  });
}
