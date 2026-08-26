import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/ui/first_playable/first_playable_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Direction B vertical slice is navigable end to end', (
    tester,
  ) async {
    final intents = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: FirstPlayableApp(onIntent: intents.add),
      ),
    );

    await tester.tap(find.text('Crear partida'));
    await tester.pumpAndSettle();
    expect(find.text('Elegí cómo empieza esta vuelta'), findsOneWidget);

    await tester.tap(find.text('Crear sala'));
    await tester.pumpAndSettle();
    expect(find.text('La mesa está casi lista'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Estoy lista'), 200);
    await tester.tap(find.text('Estoy lista'));
    await tester.pump();
    expect(find.text('Lista'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Empezar partida'), 200);
    await tester.tap(find.text('Empezar partida'));
    await tester.pumpAndSettle();
    expect(find.text('El tablero vuelve al centro'), findsOneWidget);

    final boardAction = find.byKey(const ValueKey('fp-board-action')).last;
    await tester.scrollUntilVisible(
      boardAction,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(boardAction);
    await tester.pumpAndSettle();
    expect(find.textContaining('Movimiento confirmado'), findsOneWidget);

    final offerAction = find.byKey(const ValueKey('fp-board-action')).last;
    await tester.scrollUntilVisible(
      offerAction,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(offerAction);
    await tester.pumpAndSettle();
    expect(find.text('¿La sumás a tu vuelta?'), findsOneWidget);
    expect(find.text('Comprar'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('No comprar · abrir subasta'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('No comprar · abrir subasta'));
    await tester.pumpAndSettle();
    expect(find.text('La mesa se picó'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Pasar'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Pasar'));
    await tester.pumpAndSettle();
    expect(find.text('La señal se cortó'), findsOneWidget);

    await tester.tap(find.text('Reintentar conexión'));
    await tester.pump();
    expect(find.text('CONTROL RECUPERADO'), findsOneWidget);

    await tester.tap(find.text('Volver al tablero'));
    await tester.pumpAndSettle();
    expect(find.text('El tablero vuelve al centro'), findsOneWidget);

    expect(intents, [
      'open-create-room',
      'create-room',
      'set-ready',
      'start-game',
      'roll',
      'decline-property',
      'pass-auction',
      'retry-reconnect',
      'return-to-board',
    ]);
  });

  testWidgets('join path keeps a six-character room code entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const FirstPlayableApp()),
    );

    await tester.tap(find.text('Unirse con código'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.maxLength, 6);
    expect(find.text('Sumate a la mesa'), findsOneWidget);
  });

  testWidgets('visual identity names keep the approved anatomy', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const FirstPlayableApp()),
    );

    expect(
      find.bySemanticsLabel(
        'MANÍ. Perra clara, cruza labradora, orejas canela. Ilustración pendiente de foto fuente.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('ALMACÉN'), findsNothing);

    semantics.dispose();
  });
}
