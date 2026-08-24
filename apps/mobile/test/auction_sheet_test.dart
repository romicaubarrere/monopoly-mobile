import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/ui/auction/auction_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'auction_exposes_confirmed_bid_leader_deadline_and_participants',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = TextEditingController(text: '350');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(
          controller: controller,
          state: AuctionSurfaceState.waitingMySlot,
          onBid: () {},
          onPass: () {},
        ),
      );

      expect(
        find.bySemanticsLabel(r'Oferta actual: $ 300. Lidera: Rival A.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Tiempo para actuar: 00:08. El cierre lo confirma la partida.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          r'Rival A. Estado: liderando. Última oferta: $ 300.',
        ),
        findsOneWidget,
      );
      expect(find.text('Tu efectivo disponible'), findsOneWidget);

      semantics.dispose();
    },
  );

  testWidgets(
    'pending_bid_freezes_conflicting_controls_and_keeps_confirmed_bid',
    (tester) async {
      final controller = TextEditingController(text: '350');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(
          controller: controller,
          state: AuctionSurfaceState.pendingBid,
          onBid: () {},
          onPass: () {},
        ),
      );

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Pasar'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text(r'$ 300'), findsWidgets);
      expect(find.text('Enviando puja…'), findsOneWidget);
      expect(
        find.text(
          'Esperando confirmación. La oferta visible sigue siendo la última confirmada.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'rejected_bid_recomposes_from_confirmed_state_and_allows_new_input',
    (tester) async {
      var bidCalls = 0;
      final controller = TextEditingController(text: '350');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(
          controller: controller,
          state: AuctionSurfaceState.bidRejected,
          onBid: () => bidCalls += 1,
          onPass: () {},
        ),
      );

      final bid = tester.widget<FilledButton>(find.byType(FilledButton));
      final input = tester.widget<TextField>(
        find.byKey(const Key('auction-bid-input')),
      );

      expect(bid.onPressed, isNotNull);
      expect(input.enabled, isTrue);
      expect(
        find.text(
          'La puja no fue aplicada. Actualizá el monto sobre el estado confirmado.',
        ),
        findsOneWidget,
      );

      bid.onPressed!();
      expect(bidCalls, 1);
    },
  );

  testWidgets('passed_player_cannot_reenter_the_same_auction', (tester) async {
    final controller = TextEditingController(text: '350');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        controller: controller,
        state: AuctionSurfaceState.passed,
        onBid: () {},
        onPass: () {},
      ),
    );

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Pasar'))
          .onPressed,
      isNull,
    );
    expect(find.text('Ya pasaste en esta subasta'), findsOneWidget);
  });

  testWidgets(
    'compact_offline_auction_remains_renderable_and_non_mutating',
    (tester) async {
      final controller = TextEditingController(text: '350');
      addTearDown(controller.dispose);

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
                child: AuctionSheet(
                  propertyLabel:
                      'Propiedad sintética con nombre deliberadamente largo',
                  currentBidLabel: r'$ 300',
                  leaderLabel: 'Rival A',
                  cashAvailableLabel: r'$ 1.000',
                  deadlineLabel: '00:08',
                  deadlineProgress: 0.7,
                  participants: _participants,
                  bidController: controller,
                  state: AuctionSurfaceState.offline,
                  quickIncrementLabels: const [r'$ 10', r'$ 25', r'$ 50'],
                  onQuickIncrement: (_) {},
                  onBid: () {},
                  onPass: () {},
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
        find.text('Reconectando antes de habilitar controles de subasta.'),
        findsOneWidget,
      );
    },
  );
}

const _participants = <AuctionParticipantView>[
  AuctionParticipantView(
    label: 'Rival A',
    state: AuctionParticipantState.leader,
    bidLabel: r'$ 300',
  ),
  AuctionParticipantView(
    label: 'Vos',
    state: AuctionParticipantState.active,
  ),
  AuctionParticipantView(
    label: 'Rival B',
    state: AuctionParticipantState.passed,
  ),
];

Widget _app({
  required TextEditingController controller,
  required AuctionSurfaceState state,
  VoidCallback? onBid,
  VoidCallback? onPass,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: AuctionSheet(
      propertyLabel: 'Propiedad sintética',
      currentBidLabel: r'$ 300',
      leaderLabel: 'Rival A',
      cashAvailableLabel: r'$ 1.000',
      deadlineLabel: '00:08',
      deadlineProgress: 0.55,
      participants: _participants,
      bidController: controller,
      state: state,
      quickIncrementLabels: const [r'$ 10', r'$ 25', r'$ 50'],
      onQuickIncrement: (_) {},
      onBid: onBid,
      onPass: onPass,
    ),
  );
}
