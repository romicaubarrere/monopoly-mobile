import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/design_system/tokens.dart';
import 'package:board_mobile/ui/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('primary controls meet minimum touch target', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );

    final createSize = tester.getSize(
      find.widgetWithText(FilledButton, 'Crear partida'),
    );
    final joinSize = tester.getSize(
      find.widgetWithText(OutlinedButton, 'Unirse con código'),
    );

    expect(createSize.height, greaterThanOrEqualTo(AppSizes.minTouchTarget));
    expect(joinSize.height, greaterThanOrEqualTo(AppSizes.minTouchTarget));
  });

  testWidgets(
    'compact width and 130 percent text scale keep shell renderable',
    (tester) async {
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
                ),
                child: const HomeScreen(),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('40 posiciones sintéticas'), findsOneWidget);
    },
  );

  testWidgets('theme exposes semantic Imprenta barrial colors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );

    final scaffold = tester.element(find.byType(Scaffold));
    final theme = Theme.of(scaffold);

    expect(theme.scaffoldBackgroundColor, AppPalette.canvas);
    expect(theme.colorScheme.primary, ApPalette.primary);
    expect(theme.colorScheme.secondary, AppPalette.info);
  });
}
