import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/design_system/tokens.dart';
import 'package:board_mobile/ui/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const viewports = <Size>[
    Size(360, 800),
    Size(390, 844),
    Size(412, 915),
    Size(430, 932),
  ];

  for (final viewport in viewports) {
    testWidgets(
      'home shell renders at ${viewport.width.toInt()}dp with 130% text scale',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: viewport.width,
                height: viewport.height,
                child: MediaQuery(
                  data: MediaQueryData(
                    size: viewport,
                    textScaler: const TextScaler.linear(1.3),
                  ),
                  child: const HomeScreen(),
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Crear partida'), findsOneWidget);
        expect(find.text('Unirse con código'), findsOneWidget);
        expect(find.textContaining('40 posiciones sintéticas'), findsOneWidget);

        final createSize = tester.getSize(
          find.widgetWithText(FilledButton, 'Crear partida'),
        );
        final joinSize = tester.getSize(
          find.widgetWithText(OutlinedButton, 'Unirse con código'),
        );

        expect(
          createSize.height,
          greaterThanOrEqualTo(AppSizes.minTouchTarget),
        );
        expect(joinSize.height, greaterThanOrEqualTo(AppSizes.minTouchTarget));
      },
    );
  }

  testWidgets('board preview exposes one structural semantics container', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );
    await tester.scrollUntilVisible(find.text('BOARD COMO CONTEXTO'), 300);
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(
        'Tablero estructural de demostración, 40 casilleros sintéticos',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Casillero sintético 1'), findsNothing);
  });

  testWidgets('disabled roll keeps an explicit visible reason', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );

    final roll = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Tirar dados'),
    );

    expect(roll.onPressed, isNull);
    expect(
      find.text('Disponible cuando exista una partida confirmada.'),
      findsOneWidget,
    );
  });
}
