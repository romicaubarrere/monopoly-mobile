import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/ui/events/free_parking_event_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('confirmed_event_shows_authoritative_pot_receipt', (tester) async {
    await tester.pumpWidget(
      _surface(
        confirmedAmount: 240,
        resultingBalanceLabel: r'Saldo confirmado $1.490 PLACEHOLDER',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ESTACIONAMIENTO LIBRE'), findsOneWidget);
    expect(find.text('CONFIRMADO'), findsOneWidget);
    expect(find.text('COBRO DEL POZO'), findsOneWidget);
    expect(find.text(r'+$240'), findsOneWidget);
    expect(find.text(r'Te llevaste $240 del pozo'), findsOneWidget);
    expect(
      find.text(r'Saldo confirmado $1.490 PLACEHOLDER'),
      findsOneWidget,
    );
    expect(find.text('Sin acción pendiente'), findsOneWidget);
  });

  testWidgets('event_has_no_claim_or_gameplay_action', (tester) async {
    await tester.pumpWidget(_surface(confirmedAmount: 240));
    await tester.pumpAndSettle();

    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.textContaining('COBRAR'), findsNothing);
    expect(find.textContaining('RECLAMAR'), findsNothing);
  });

  testWidgets('empty_breakdown_does_not_invent_tax_sources', (tester) async {
    await tester.pumpWidget(_surface(confirmedAmount: 180));
    await tester.pumpAndSettle();

    expect(find.text('DETALLE CONFIRMADO'), findsNothing);
    expect(find.textContaining('Contribución'), findsNothing);
    expect(find.textContaining('Patente'), findsNothing);
  });

  testWidgets('breakdown_renders_only_caller_supplied_confirmed_events', (
    tester,
  ) async {
    await tester.pumpWidget(
      _surface(
        confirmedAmount: 180,
        breakdown: const [
          FreeParkingBreakdownItem(
            label: 'FUENTE A PLACEHOLDER',
            amountLabel: r'$100 PLACEHOLDER',
          ),
          FreeParkingBreakdownItem(
            label: 'FUENTE B PLACEHOLDER',
            amountLabel: r'$80 PLACEHOLDER',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DETALLE CONFIRMADO'), findsOneWidget);
    expect(find.text('FUENTE A PLACEHOLDER'), findsOneWidget);
    expect(find.text(r'$100 PLACEHOLDER'), findsOneWidget);
    expect(find.text('FUENTE B PLACEHOLDER'), findsOneWidget);
    expect(find.text(r'$80 PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('confirmed_event_exposes_one_factual_live_region', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _surface(
        confirmedAmount: 180,
        breakdown: const [
          FreeParkingBreakdownItem(
            label: 'FUENTE PLACEHOLDER',
            amountLabel: r'$180 PLACEHOLDER',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(
        RegExp(
          r'Estacionamiento Libre.*Cobro confirmado.*Te llevaste \$180 del pozo.*FUENTE PLACEHOLDER',
        ),
      ),
      findsOneWidget,
    );

    semantics.dispose();
  });

  testWidgets('reduced_motion_removes_receipt_scale_duration', (tester) async {
    await tester.pumpWidget(
      _surface(
        confirmedAmount: 180,
        mediaQueryData: const MediaQueryData(disableAnimations: true),
      ),
    );

    final animation = tester.widget<TweenAnimationBuilder<double>>(
      find.byType(TweenAnimationBuilder<double>),
    );
    expect(animation.duration, Duration.zero);
  });

  testWidgets('compact_event_renders_at_360dp_and_130_percent_text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _surface(
        confirmedAmount: 240,
        resultingBalanceLabel:
            r'Saldo confirmado largo $1.490 PLACEHOLDER DESPUÉS DEL COBRO',
        breakdown: const [
          FreeParkingBreakdownItem(
            label: 'FUENTE CONFIRMADA PLACEHOLDER CON ETIQUETA LARGA',
            amountLabel: r'$240 PLACEHOLDER',
          ),
        ],
        mediaQueryData: const MediaQueryData(
          size: Size(360, 720),
          textScaler: TextScaler.linear(1.3),
          disableAnimations: true,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('ESTACIONAMIENTO LIBRE'), findsOneWidget);
    expect(find.text(r'Te llevaste $240 del pozo'), findsOneWidget);
    expect(find.text('DETALLE CONFIRMADO'), findsOneWidget);
  });
}

Widget _surface({
  required int confirmedAmount,
  String? resultingBalanceLabel,
  List<FreeParkingBreakdownItem> breakdown = const [],
  MediaQueryData mediaQueryData = const MediaQueryData(),
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: mediaQueryData.size.width == 0
              ? 390
              : mediaQueryData.size.width,
          height: mediaQueryData.size.height == 0
              ? 844
              : mediaQueryData.size.height,
          child: MediaQuery(
            data: mediaQueryData,
            child: FreeParkingEventSurface.confirmed(
              confirmedAmount: confirmedAmount,
              resultingBalanceLabel: resultingBalanceLabel,
              breakdown: breakdown,
            ),
          ),
        ),
      ),
    ),
  );
}
