import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/design_system/tokens.dart';
import 'package:board_mobile/design_system/visual_components.dart';
import 'package:board_mobile/ui/property/property_offer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'property_offer_exposes_economy_and_group_without_board_traversal',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _app(
          state: PropertyOfferDecisionState.available,
          onBuy: () {},
          onDecline: () {},
        ),
      );

      expect(
        find.bySemanticsLabel('Propiedad sintética. Grupo Grupo sintético.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          r'Efectivo confirmado: $ 1.000. Proyectado si comprás: $ 800.',
        ),
        findsOneWidget,
      );
      expect(find.text('Grupo: 2 de 3'), findsOneWidget);

      semantics.dispose();
    },
  );

  testWidgets('property_offer_uses_almazen_material_hierarchy', (tester) async {
    await tester.pumpWidget(
      _app(
        state: PropertyOfferDecisionState.available,
        onBuy: () {},
        onDecline: () {},
      ),
    );

    expect(find.byType(PaperPanel), findsNWidgets(4));
    expect(find.byType(StampBadge), findsOneWidget);
    expect(find.byType(TapeMark), findsOneWidget);
    expect(find.text('SE VENDE'), findsOneWidget);
    expect(find.text('TU CUENTA'), findsOneWidget);
    expect(find.text('Grupo Grupo sintético'), findsOneWidget);
  });

  testWidgets('insufficient_funds_disables_buy_but_keeps_decline_available', (
    tester,
  ) async {
    var declineCalls = 0;

    await tester.pumpWidget(
      _app(
        state: PropertyOfferDecisionState.insufficientFunds,
        onBuy: () {},
        onDecline: () => declineCalls += 1,
      ),
    );

    final buy = tester.widget<FilledButton>(find.byType(FilledButton));
    final decline = tester.widget<OutlinedButton>(find.byType(OutlinedButton));

    expect(buy.onPressed, isNull);
    expect(decline.onPressed, isNotNull);
    expect(find.text('No tenés efectivo suficiente'), findsOneWidget);

    decline.onPressed!();
    expect(declineCalls, 1);
  });

  testWidgets(
    'pending_buy_blocks_conflicting_decline_and_keeps_offer_context',
    (tester) async {
      await tester.pumpWidget(
        _app(
          state: PropertyOfferDecisionState.pendingBuy,
          onBuy: () {},
          onDecline: () {},
        ),
      );

      final buy = tester.widget<FilledButton>(find.byType(FilledButton));
      final decline = tester.widget<OutlinedButton>(
        find.byType(OutlinedButton),
      );

      expect(buy.onPressed, isNull);
      expect(decline.onPressed, isNull);
      expect(find.text('Comprando…'), findsOneWidget);
      expect(find.text('Confirmando compra…'), findsOneWidget);
      expect(find.text('Propiedad sintética'), findsOneWidget);
    },
  );

  testWidgets(
    'pending_decline_says_auction_is_opening_without_opening_it_locally',
    (tester) async {
      await tester.pumpWidget(
        _app(
          state: PropertyOfferDecisionState.pendingDecline,
          onBuy: () {},
          onDecline: () {},
        ),
      );

      final buy = tester.widget<FilledButton>(find.byType(FilledButton));
      final decline = tester.widget<OutlinedButton>(
        find.byType(OutlinedButton),
      );

      expect(buy.onPressed, isNull);
      expect(decline.onPressed, isNull);
      expect(find.text('Abriendo subasta…'), findsWidgets);
    },
  );

  testWidgets(
    'uncertain_compact_offer_freezes_actions_and_remains_renderable',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Center(
            child: SizedBox(
              width: 360,
              height: 700,
              child: MediaQuery(
                data: const MediaQueryData(
                  size: Size(360, 700),
                  textScaler: TextScaler.linear(1.3),
                  disableAnimations: true,
                ),
                child: PropertyOfferSheet(
                  propertyLabel: 'Propiedad sintética con nombre largo',
                  groupLabel: 'Grupo sintético',
                  groupSignalColor: AppPalette.ritual,
                  priceLabel: r'$ 200',
                  baseRentLabel: r'$ 20',
                  cashNowLabel: r'$ 1.000',
                  cashAfterLabel: r'$ 800',
                  groupProgressLabel: '2 de 3',
                  state: PropertyOfferDecisionState.uncertain,
                  onBuy: () {},
                  onDecline: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(
        find.text('Confirmando qué pasó antes de permitir otra decisión.'),
        findsOneWidget,
      );
    },
  );
}

Widget _app({
  required PropertyOfferDecisionState state,
  VoidCallback? onBuy,
  VoidCallback? onDecline,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: PropertyOfferSheet(
      propertyLabel: 'Propiedad sintética',
      groupLabel: 'Grupo sintético',
      groupSignalColor: AppPalette.ritual,
      priceLabel: r'$ 200',
      baseRentLabel: r'$ 20',
      cashNowLabel: r'$ 1.000',
      cashAfterLabel: r'$ 800',
      groupProgressLabel: '2 de 3',
      state: state,
      onBuy: onBuy,
      onDecline: onDecline,
    ),
  );
}
