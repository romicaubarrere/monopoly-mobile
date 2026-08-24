import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/ui/bankruptcy/bankruptcy_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('insolvency_is_factual_and_hides_unconfirmed_transfers', (
    tester,
  ) async {
    await tester.pumpWidget(
      _surface(
        state: BankruptcySurfaceState.insolvent,
        transferSummary: _transfers,
      ),
    );

    expect(find.text('ESTADO DE INSOLVENCIA'), findsOneWidget);
    expect(find.text('BANCARROTA CONFIRMADA'), findsNothing);
    expect(find.textContaining('Perdiste'), findsNothing);
    expect(find.text('EFECTIVO PLACEHOLDER'), findsNothing);
    expect(find.text('TODAVÍA NO ES UN RESULTADO FINAL'), findsOneWidget);
  });

  testWidgets('confirmed_bankruptcy_shows_only_confirmed_outcome_summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      _surface(
        state: BankruptcySurfaceState.confirmed,
        creditorLabel: 'BANCO PLACEHOLDER',
        transferSummary: _transfers,
      ),
    );

    expect(find.text('BANCARROTA CONFIRMADA'), findsOneWidget);
    expect(find.text('BANCO PLACEHOLDER'), findsOneWidget);
    expect(find.text('EFECTIVO PLACEHOLDER'), findsOneWidget);
    expect(find.text(r'$PLACEHOLDER'), findsOneWidget);
    expect(find.text('Y AHORA'), findsOneWidget);
    expect(find.text('CONTINUIDAD PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('pre_confirmation_action_emits_only_caller_action_id', (
    tester,
  ) async {
    String? selectedAction;

    await tester.pumpWidget(
      _surface(
        actionId: 'bankruptcy-choice:placeholder-01',
        actionLabel: 'ACCIÓN PLACEHOLDER',
        onAction: (id) => selectedAction = id,
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'ACCIÓN PLACEHOLDER'));
    await tester.pump();

    expect(selectedAction, 'bankruptcy-choice:placeholder-01');
    expect(find.text('BANCARROTA CONFIRMADA'), findsNothing);
    expect(find.text('EFECTIVO PLACEHOLDER'), findsNothing);
  });

  testWidgets('uncertain_state_blocks_conflicting_action_and_explains_why', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var emitted = 0;

    await tester.pumpWidget(
      _surface(
        state: BankruptcySurfaceState.uncertain,
        actionId: 'bankruptcy-choice:placeholder-01',
        actionLabel: 'ACCIÓN PLACEHOLDER',
        onAction: (_) => emitted += 1,
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
        'ACCIÓN PLACEHOLDER. No disponible: Confirmando qué pasó',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(emitted, 0);

    semantics.dispose();
  });

  testWidgets('confirmed_bankruptcy_never_exposes_pre_confirmation_action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _surface(
        state: BankruptcySurfaceState.confirmed,
        actionId: 'bankruptcy-choice:placeholder-01',
        actionLabel: 'ACCIÓN PLACEHOLDER',
        onAction: (_) {},
      ),
    );

    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('ACCIÓN PLACEHOLDER'), findsNothing);
  });

  testWidgets('confirmed_transfer_row_has_confirmed_semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _surface(
        state: BankruptcySurfaceState.confirmed,
        transferSummary: _transfers,
      ),
    );

    expect(
      find.bySemanticsLabel(
        r'EFECTIVO PLACEHOLDER. $PLACEHOLDER. Transferencia provista por authority. Confirmado',
      ),
      findsOneWidget,
    );

    semantics.dispose();
  });

  testWidgets(
    'compact_bankruptcy_surface_renders_at_360dp_and_130_percent_text',
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
                  child: BankruptcySurface(
                    playerLabel: 'JUGADOR PLACEHOLDER CON NOMBRE LARGO',
                    state: BankruptcySurfaceState.confirmed,
                    reasonLabel:
                        'Razón factual PLACEHOLDER provista por la partida.',
                    creditorLabel: 'ACREEDOR PLACEHOLDER CON NOMBRE LARGO',
                    transferSummary: _transfers,
                    continuationMessage:
                        'La partida continúa según el estado confirmado PLACEHOLDER.',
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('BANCARROTA CONFIRMADA'), findsOneWidget);
      expect(find.text('JUGADOR PLACEHOLDER CON NOMBRE LARGO'), findsOneWidget);
    },
  );
}

const _transfers = <BankruptcyTransferView>[
  BankruptcyTransferView(
    label: 'EFECTIVO PLACEHOLDER',
    valueLabel: r'$PLACEHOLDER',
    detail: 'Transferencia provista por authority.',
  ),
  BankruptcyTransferView(
    label: 'ACTIVOS PLACEHOLDER',
    detail: 'Resumen provisto por el estado confirmado.',
  ),
];

Widget _surface({
  BankruptcySurfaceState state = BankruptcySurfaceState.insolvent,
  String? creditorLabel,
  List<BankruptcyTransferView> transferSummary = const [],
  String? actionId,
  String? actionLabel,
  ValueChanged<String>? onAction,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: BankruptcySurface(
        playerLabel: 'JUGADOR PLACEHOLDER',
        state: state,
        reasonLabel: 'Insolvencia factual PLACEHOLDER.',
        creditorLabel: creditorLabel,
        transferSummary: transferSummary,
        continuationMessage: 'CONTINUIDAD PLACEHOLDER',
        actionId: actionId,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
    ),
  );
}
