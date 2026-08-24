import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/ui/trade/trade_surfaces.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('trade_builder_exposes_bilateral_summary_in_mobile_order', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final offeredCash = TextEditingController(text: '100');
    final requestedCash = TextEditingController(text: '0');
    addTearDown(offeredCash.dispose);
    addTearDown(requestedCash.dispose);

    await tester.pumpWidget(
      _builder(
        offeredCash: offeredCash,
        requestedCash: requestedCash,
        state: TradeBuilderState.draftValid,
        onSend: () {},
      ),
    );

    expect(find.text('Vos ofrecés'), findsOneWidget);
    expect(find.text('Vos pedís'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        r'Vos entregás: $ 100 + Propiedad sintética A. Vos recibís: Propiedad sintética B.',
      ),
      findsOneWidget,
    );

    final offerY = tester.getTopLeft(find.text('Vos ofrecés')).dy;
    final requestY = tester.getTopLeft(find.text('Vos pedís')).dy;
    expect(offerY, lessThan(requestY));

    semantics.dispose();
  });

  testWidgets('draft_empty_disables_send_with_reason', (tester) async {
    final offeredCash = TextEditingController();
    final requestedCash = TextEditingController();
    addTearDown(offeredCash.dispose);
    addTearDown(requestedCash.dispose);

    await tester.pumpWidget(
      _builder(
        offeredCash: offeredCash,
        requestedCash: requestedCash,
        state: TradeBuilderState.draftEmpty,
        onSend: () {},
      ),
    );

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.text('Agregá algo para ofrecer o pedir'), findsOneWidget);
  });

  testWidgets('pending_send_freezes_asset_selection_and_preserves_summary', (
    tester,
  ) async {
    var toggles = 0;
    final offeredCash = TextEditingController(text: '100');
    final requestedCash = TextEditingController();
    addTearDown(offeredCash.dispose);
    addTearDown(requestedCash.dispose);

    await tester.pumpWidget(
      _builder(
        offeredCash: offeredCash,
        requestedCash: requestedCash,
        state: TradeBuilderState.pendingSend,
        onToggleOffered: (_) => toggles += 1,
        onSend: () {},
      ),
    );

    final offeredAsset = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Propiedad sintética A'),
    );
    expect(offeredAsset.onPressed, isNull);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      find.text(
        'Esperando confirmación. Todavía no se transfirió ningún activo.',
      ),
      findsOneWidget,
    );
    expect(toggles, 0);
  });

  testWidgets('trade_review_available_exposes_exchange_deadline_and_actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _review(
        state: TradeReviewState.available,
        onAccept: () {},
        onCounter: () {},
        onReject: () {},
      ),
    );

    expect(
      find.bySemanticsLabel(
        r'Recibís: Propiedad sintética B. Entregás: $ 100 + Propiedad sintética A.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Tiempo para responder: 00:30. El cierre lo confirma la partida.',
      ),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    expect(
      tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Contraofertar'),
      ).onPressed,
      isNotNull,
    );
    expect(
      tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Rechazar'),
      ).onPressed,
      isNotNull,
    );

    semantics.dispose();
  });

  testWidgets('temporary_bot_waiting_human_never_exposes_trade_consent', (
    tester,
  ) async {
    await tester.pumpWidget(
      _review(
        state: TradeReviewState.waitingHuman,
        onAccept: () {},
        onCounter: () {},
        onReject: () {},
      ),
    );

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Contraofertar'),
      ).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Rechazar'),
      ).onPressed,
      isNull,
    );
    expect(
      find.text(
        'Esperando a que vuelva el jugador. El bot temporal no puede aceptar por él.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('pending_accept_freezes_conflicting_trade_responses', (
    tester,
  ) async {
    await tester.pumpWidget(
      _review(
        state: TradeReviewState.pendingAccept,
        onAccept: () {},
        onCounter: () {},
        onReject: () {},
      ),
    );

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.text('Aceptando…'), findsOneWidget);
    expect(
      find.text(
        'Esperando confirmación. Los activos todavía muestran el último estado confirmado.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('compact_offline_trade_review_remains_renderable_and_safe', (
    tester,
  ) async {
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
              child: TradeReviewSurface(
                proposerLabel: 'Jugador con nombre largo',
                receiveLabel:
                    'Propiedad sintética B + carta sintética de conservación',
                giveLabel: r'$ 100 + Propiedad sintética A',
                deadlineLabel: '00:30',
                deadlineProgress: 0.65,
                state: TradeReviewState.offline,
                onAccept: () {},
                onCounter: () {},
                onReject: () {},
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
      find.text('Reconectando antes de habilitar una respuesta.'),
      findsOneWidget,
    );
  });
}

const _offeredAssets = <TradeAssetView>[
  TradeAssetView(
    id: 'synthetic-a',
    label: 'Propiedad sintética A',
    detail: 'Hipotecada · dato sintético',
    selected: true,
  ),
  TradeAssetView(
    id: 'synthetic-card',
    label: 'Carta sintética',
    selected: false,
    available: false,
    unavailableReason: 'No elegible en el estado confirmado',
  ),
];

const _requestedAssets = <TradeAssetView>[
  TradeAssetView(
    id: 'synthetic-b',
    label: 'Propiedad sintética B',
    selected: true,
  ),
];

Widget _builder({
  required TextEditingController offeredCash,
  required TextEditingController requestedCash,
  required TradeBuilderState state,
  ValueChanged<String>? onToggleOffered,
  VoidCallback? onSend,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: TradeBuilderSurface(
      rivalLabel: 'Rival A',
      offeredAssets: _offeredAssets,
      requestedAssets: _requestedAssets,
      offeredCashController: offeredCash,
      requestedCashController: requestedCash,
      summaryGiveLabel: r'$ 100 + Propiedad sintética A',
      summaryReceiveLabel: 'Propiedad sintética B',
      state: state,
      onToggleOfferedAsset: onToggleOffered,
      onToggleRequestedAsset: (_) {},
      onSend: onSend,
    ),
  );
}

Widget _review({
  required TradeReviewState state,
  VoidCallback? onAccept,
  VoidCallback? onCounter,
  VoidCallback? onReject,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: TradeReviewSurface(
      proposerLabel: 'Rival A',
      receiveLabel: 'Propiedad sintética B',
      giveLabel: r'$ 100 + Propiedad sintética A',
      deadlineLabel: '00:30',
      deadlineProgress: 0.4,
      state: state,
      onAccept: onAccept,
      onCounter: onCounter,
      onReject: onReject,
    ),
  );
}
