import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/ui/feedback/system_event_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('confirmed_event_renders_caller_supplied_summary_only', (
    tester,
  ) async {
    await tester.pumpWidget(
      _toast(
        title: 'EVENTO PLACEHOLDER',
        detail: 'Detalle confirmado PLACEHOLDER.',
      ),
    );

    expect(find.text('EVENTO CONFIRMADO'), findsOneWidget);
    expect(find.text('EVENTO PLACEHOLDER'), findsOneWidget);
    expect(find.text('Detalle confirmado PLACEHOLDER.'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.textContaining('Alquiler'), findsNothing);
    expect(find.textContaining('Contribución'), findsNothing);
  });

  testWidgets('economy_receipt_uses_exact_confirmed_caller_values', (
    tester,
  ) async {
    await tester.pumpWidget(
      _toast(
        title: 'MOVIMIENTO PLACEHOLDER',
        detail: 'La autoridad confirmó el movimiento.',
        economyDelta: -75,
        economySummary: 'Concepto PLACEHOLDER confirmado',
        resultingBalanceLabel: r'Saldo confirmado $925 PLACEHOLDER',
      ),
    );

    expect(find.text(r'-$75'), findsOneWidget);
    expect(find.text('Concepto PLACEHOLDER confirmado'), findsOneWidget);
    expect(find.text(r'Saldo confirmado $925 PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('confirmed_event_exposes_one_composed_live_region', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _toast(
        title: 'EVENTO PLACEHOLDER',
        detail: 'Detalle confirmado.',
        economyDelta: 120,
        economySummary: 'Ingreso PLACEHOLDER',
      ),
    );

    expect(
      find.bySemanticsLabel(
        RegExp(
          r'EVENTO CONFIRMADO.*EVENTO PLACEHOLDER.*Detalle confirmado.*Cambio confirmado: \+\$120.*Ingreso PLACEHOLDER',
        ),
      ),
      findsOneWidget,
    );

    semantics.dispose();
  });

  testWidgets('acknowledgement_is_explicit_optional_and_min_44dp', (
    tester,
  ) async {
    var acknowledged = false;

    await tester.pumpWidget(
      _toast(
        title: 'EVENTO PLACEHOLDER',
        detail: 'Detalle confirmado.',
        acknowledgementLabel: 'Entendido',
        onAcknowledge: () => acknowledged = true,
      ),
    );

    final button = find.widgetWithText(OutlinedButton, 'Entendido');
    expect(button, findsOneWidget);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));

    await tester.tap(button);
    await tester.pump();
    expect(acknowledged, isTrue);
  });

  testWidgets('presentation_is_static_without_internal_motion_or_timer', (
    tester,
  ) async {
    await tester.pumpWidget(
      _toast(
        title: 'EVENTO PLACEHOLDER',
        detail: 'Detalle confirmado.',
        mediaQueryData: const MediaQueryData(disableAnimations: true),
      ),
    );

    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    expect(find.byType(AnimatedSwitcher), findsNothing);
    expect(find.byType(AnimatedOpacity), findsNothing);
  });

  testWidgets('compact_toast_renders_at_360dp_and_130_percent_text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _toast(
        title: 'EVENTO CONFIRMADO PLACEHOLDER CON TÍTULO LARGO',
        detail:
            'Resumen factual PLACEHOLDER suficientemente largo para probar el reflow mobile sin esconder información crítica.',
        economyDelta: -240,
        economySummary:
            'Movimiento económico confirmado PLACEHOLDER con explicación larga',
        resultingBalanceLabel:
            r'Saldo confirmado largo $1.010 PLACEHOLDER DESPUÉS DEL EVENTO',
        acknowledgementLabel: 'Entendido',
        onAcknowledge: () {},
        mediaQueryData: const MediaQueryData(
          size: Size(360, 720),
          textScaler: TextScaler.linear(1.3),
          disableAnimations: true,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('EVENTO CONFIRMADO PLACEHOLDER CON TÍTULO LARGO'), findsOneWidget);
    expect(find.text(r'-$240'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Entendido'), findsOneWidget);
  });
}

Widget _toast({
  required String title,
  required String detail,
  int? economyDelta,
  String? economySummary,
  String? resultingBalanceLabel,
  String? acknowledgementLabel,
  VoidCallback? onAcknowledge,
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SystemEventToast.confirmed(
                title: title,
                detail: detail,
                economyDelta: economyDelta,
                economySummary: economySummary,
                resultingBalanceLabel: resultingBalanceLabel,
                acknowledgementLabel: acknowledgementLabel,
                onAcknowledge: onAcknowledge,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
