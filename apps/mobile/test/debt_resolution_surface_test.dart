import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/ui/debt/debt_resolution_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('debt_surface_distinguishes_confirmed_and_projected_cash', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(_surface());

    expect(find.text('Efectivo confirmado'), findsOneWidget);
    expect(find.text(r'$120'), findsOneWidget);
    expect(find.text('Proyectado'), findsOneWidget);
    expect(find.text(r'$260'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        r'Efectivo proyectado: $260. No confirmado.',
      ),
      findsOneWidget,
    );

    semantics.dispose();
  });

  testWidgets('debt_liquidation_emits_only_caller_action_id', (tester) async {
    String? selectedAction;

    await tester.pumpWidget(
      _surface(onAction: (id) => selectedAction = id),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'HIPOTECAR'));
    await tester.pump();

    expect(selectedAction, 'mortgage:placeholder-01');
    expect(find.text('Esperando confirmación…'), findsNothing);
    expect(find.text(r'$120'), findsOneWidget);
  });

  testWidgets(
    'debt_pending_freezes_conflicting_actions_and_keeps_confirmed_cash',
    (tester) async {
      var emitted = 0;

      await tester.pumpWidget(
        _surface(
          state: DebtResolutionSurfaceState.pending,
          pendingActionId: 'mortgage:placeholder-01',
          onAction: (_) => emitted += 1,
        ),
      );

      expect(find.text('ESPERANDO CONFIRMACIÓN'), findsOneWidget);
      expect(find.text(r'$120'), findsOneWidget);
      expect(
        find.text(
          'Esperando confirmación. El efectivo confirmado todavía no cambia.',
        ),
        findsOneWidget,
      );

      for (final button in tester.widgetList<OutlinedButton>(
        find.byType(OutlinedButton),
      )) {
        expect(button.onPressed, isNull);
      }
      expect(emitted, 0);
    },
  );

  testWidgets('debt_caller_disabled_reason_is_visible_and_semantic', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _surface(
        actions: const [
          DebtLiquidationActionView(
            id: 'sell-improvement:placeholder-01',
            assetLabel: 'PROPIEDAD PLACEHOLDER 01',
            actionLabel: 'VENDER MEJORA',
            cashGainLabel: r'+$70',
            enabled: false,
            disabledReason: 'Primero vendé las mejoras incompatibles',
          ),
        ],
      ),
    );

    expect(
      find.text('Primero vendé las mejoras incompatibles'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'PROPIEDAD PLACEHOLDER 01. VENDER MEJORA. No disponible: Primero vendé las mejoras incompatibles',
      ),
      findsOneWidget,
    );

    semantics.dispose();
  });

  testWidgets(
    'debt_auto_resolution_blocks_manual_controls_and_keeps_audit_trail',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _surface(
          state: DebtResolutionSurfaceState.autoResolving,
          auditTrail: const [
            DebtAuditEntryView(
              label: 'HIPOTECA PLACEHOLDER 01',
              cashDeltaLabel: r'+$140',
              detail: 'Movimiento confirmado por la partida.',
            ),
          ],
          onAction: (_) {},
        ),
      );

      expect(
        find.text(
          'Resolviendo automáticamente para que la partida continúe.',
        ),
        findsOneWidget,
      );
      expect(find.text('HIPOTECA PLACEHOLDER 01'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          r'HIPOTECA PLACEHOLDER 01. +$140. Confirmado.',
        ),
        findsOneWidget,
      );

      for (final button in tester.widgetList<OutlinedButton>(
        find.byType(OutlinedButton),
      )) {
        expect(button.onPressed, isNull);
      }

      semantics.dispose();
    },
  );

  testWidgets('debt_pay_cta_is_caller_gated_and_emits_pay_id', (
    tester,
  ) async {
    String? selectedAction;

    await tester.pumpWidget(
      _surface(
        confirmedCashLabel: r'$320',
        missingAmountLabel: r'$0',
        projectedCashLabel: r'$320',
        canPayAndContinue: true,
        payActionId: 'pay-debt:placeholder-01',
        onAction: (id) => selectedAction = id,
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'PAGAR Y CONTINUAR'));
    await tester.pump();

    expect(selectedAction, 'pay-debt:placeholder-01');

    await tester.pumpWidget(
      _surface(
        canPayAndContinue: false,
        payDisabledReason: 'Todavía faltan fondos confirmados',
        onAction: (_) {},
      ),
    );

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('Todavía faltan fondos confirmados'), findsOneWidget);
  });

  testWidgets('debt_uncertain_exposes_status_and_disables_actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _surface(
        state: DebtResolutionSurfaceState.uncertain,
        onAction: (_) {},
      ),
    );

    expect(
      find.text(
        'Confirmando qué pasó antes de permitir otra acción equivalente.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'PROPIEDAD PLACEHOLDER 01. HIPOTECAR. No disponible: Confirmando qué pasó',
      ),
      findsOneWidget,
    );

    semantics.dispose();
  });

  testWidgets(
    'compact_debt_surface_remains_renderable_at_360dp_and_130_percent_text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                height: 720,
                child: MediaQuery(
                  data: const MediaQueryData(
                    size: Size(360, 720),
                    textScaler: TextScaler.linear(1.3),
                    disableAnimations: true,
                  ),
                  child: DebtResolutionSurface(
                    amountDueLabel: r'$300',
                    confirmedCashLabel: r'$120',
                    missingAmountLabel: r'$180',
                    projectedCashLabel: r'$260',
                    deadlineLabel: '00:42',
                    actions: _actions,
                    auditTrail: const [],
                    state: DebtResolutionSurfaceState.available,
                    canPayAndContinue: false,
                    payDisabledReason: 'Todavía falta cubrir la deuda',
                    onAction: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('RESOLVER DEUDA'), findsOneWidget);
      expect(find.text('Tenés que pagar \$300'), findsOneWidget);
      expect(find.text('PAGAR Y CONTINUAR'), findsOneWidget);
    },
  );
}

const _actions = <DebtLiquidationActionView>[
  DebtLiquidationActionView(
    id: 'mortgage:placeholder-01',
    assetLabel: 'PROPIEDAD PLACEHOLDER 01',
    actionLabel: 'HIPOTECAR',
    cashGainLabel: r'+$140',
    detail: 'Valor provisto por el estado de presentación.',
  ),
  DebtLiquidationActionView(
    id: 'sell-improvement:placeholder-02',
    assetLabel: 'PROPIEDAD PLACEHOLDER 02',
    actionLabel: 'VENDER MEJORA',
    cashGainLabel: r'+$80',
    detail: 'La ganancia se confirma antes de entrar al saldo real.',
  ),
];

Widget _surface({
  String confirmedCashLabel = r'$120',
  String missingAmountLabel = r'$180',
  String projectedCashLabel = r'$260',
  List<DebtLiquidationActionView> actions = _actions,
  List<DebtAuditEntryView> auditTrail = const [],
  DebtResolutionSurfaceState state = DebtResolutionSurfaceState.available,
  String? pendingActionId,
  bool canPayAndContinue = false,
  String? payActionId,
  String? payDisabledReason,
  ValueChanged<String>? onAction,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: DebtResolutionSurface(
        amountDueLabel: r'$300',
        confirmedCashLabel: confirmedCashLabel,
        missingAmountLabel: missingAmountLabel,
        projectedCashLabel: projectedCashLabel,
        deadlineLabel: '00:42',
        actions: actions,
        auditTrail: auditTrail,
        state: state,
        pendingActionId: pendingActionId,
        canPayAndContinue: canPayAndContinue,
        payActionId: payActionId,
        payDisabledReason: payDisabledReason,
        onAction: onAction,
      ),
    ),
  );
}
