import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/design_system/money_text.dart';
import 'package:board_mobile/design_system/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('money text uses caller-owned value and explicit semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: MoneyText(
            value: r'$ 1.250',
            semanticLabel: 'Saldo confirmado: 1.250',
          ),
        ),
      ),
    );

    expect(find.text(r'$ 1.250'), findsOneWidget);
    expect(find.bySemanticsLabel('Saldo confirmado: 1.250'), findsOneWidget);

    final text = tester.widget<Text>(find.text(r'$ 1.250'));
    expect(text.style?.fontFeatures, isNotEmpty);
    semantics.dispose();
  });

  testWidgets('delta tone has a non-color visual cue and semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Column(
            children: [
              MoneyDelta(
                value: r'+$ 50',
                semanticLabel: 'Cambio confirmado: más 50',
                tone: MoneyDeltaTone.positive,
              ),
              MoneyDelta(
                value: r'-$ 25',
                semanticLabel: 'Cambio confirmado: menos 25',
                tone: MoneyDeltaTone.negative,
              ),
              MoneyDelta(
                value: r'$ 0',
                semanticLabel: 'Cambio confirmado: sin cambio',
                tone: MoneyDeltaTone.neutral,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Cambio confirmado: más 50'), findsOneWidget);
    expect(find.bySemanticsLabel('Cambio confirmado: menos 25'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('emphasized money remains caller-owned presentation only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: MoneyText(
            value: r'PLACEHOLDER $ 999',
            semanticLabel: 'Valor placeholder 999',
            emphasized: true,
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text(r'PLACEHOLDER $ 999'));
    expect(text.style?.fontWeight, FontWeight.w900);
  });

  testWidgets('compact 360 width and 130 percent text reflow safely', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Center(
          child: SizedBox(
            width: 360,
            height: 320,
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 320),
                textScaler: TextScaler.linear(1.3),
              ),
              child: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(AppSpacing.x3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MoneyText(
                        value: r'PLACEHOLDER $ 1.234.567',
                        semanticLabel: 'Saldo placeholder 1.234.567',
                      ),
                      SizedBox(height: AppSpacing.x3),
                      MoneyDelta(
                        value: r'+$ 123.456',
                        semanticLabel: 'Cambio placeholder positivo 123.456',
                        tone: MoneyDeltaTone.positive,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(r'+$ 123.456'), findsOneWidget);
  });
}
