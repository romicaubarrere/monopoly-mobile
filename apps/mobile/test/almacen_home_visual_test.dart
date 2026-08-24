import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/design_system/tokens.dart';
import 'package:board_mobile/ui/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home exposes the approved almacen visual hierarchy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );

    expect(find.text('MONOPOLY'), findsOneWidget);
    expect(find.text('DE ROMINA'), findsOneWidget);
    expect(find.text('Mesa chica.\nRivalidad grande.'), findsOneWidget);
    expect(find.text('Crear partida'), findsOneWidget);
    expect(find.text('Unirse con código'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Monopoly de Romina',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Home keeps the DEC-065 boundary explicit', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );

    expect(find.textContaining('40 posiciones sintéticas'), findsOneWidget);
    expect(find.text('datos de muestra'), findsOneWidget);
  });

  testWidgets('Almacen Home remains usable at 360dp and 130 percent text', (
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
