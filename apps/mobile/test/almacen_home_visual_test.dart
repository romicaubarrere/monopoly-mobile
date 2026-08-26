import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/design_system/tokens.dart';
import 'package:board_mobile/ui/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home exposes the approved Direction B hierarchy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );

    expect(find.text('LA VUELTA'), findsOneWidget);
    expect(find.text('Una vuelta más.\nUna historia nueva.'), findsOneWidget);
    expect(find.text('Crear partida'), findsOneWidget);
    expect(find.text('Unirse con código'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'MANÍ. Perra clara, cruza labradora, orejas canela. Ilustración pendiente de foto fuente.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('ALMACÉN'), findsNothing);
  });

  testWidgets('Home keeps the DEC-065 boundary explicit', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );

    expect(find.textContaining('PLACEHOLDER según DEC-065'), findsOneWidget);
  });

  testWidgets('Direction B Home remains usable at 360dp and 130% text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 360,
            height: 800,
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.3),
              ),
              child: const HomeScreen(),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    final createSize = tester.getSize(
      find.widgetWithText(FilledButton, 'Crear partida'),
    );
    final joinSize = tester.getSize(
      find.widgetWithText(OutlinedButton, 'Unirse con código'),
    );

    expect(createSize.height, greaterThanOrEqualTo(AppSizes.minTouchTarget));
    expect(joinSize.height, greaterThanOrEqualTo(AppSizes.minTouchTarget));
  });
}
