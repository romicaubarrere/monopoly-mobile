import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/ui/feedback/async_action_button.dart';
import 'package:board_mobile/ui/feedback/economy_receipt.dart';
import 'package:board_mobile/ui/feedback/interaction_feedback_state.dart';
import 'package:board_mobile/ui/feedback/interaction_status_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('async_cta_preserves_geometry_while_pending', (tester) async {
    Widget build(InteractionFeedbackState state) {
      return MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: AsyncActionButton(
                label: 'Comprar',
                pendingLabel: 'Confirmando…',
                state: state,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(build(InteractionFeedbackState.idle));
    final idleSize = tester.getSize(find.byType(FilledButton));

    await tester.pumpWidget(build(InteractionFeedbackState.pending));
    final pendingSize = tester.getSize(find.byType(FilledButton));

    expect(pendingSize, idleSize);
    expect(find.text('Confirmando…'), findsOneWidget);
  });

  testWidgets('disabled_action_exposes_reason_semantics', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: AsyncActionButton(
            label: 'Construir',
            pendingLabel: 'Confirmando…',
            state: InteractionFeedbackState.disabled,
            disabledReason: 'Falta completar el grupo',
          ),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel(
        'Construir. No disponible: Falta completar el grupo',
      ),
      findsOneWidget,
    );
    expect(find.text('Falta completar el grupo'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('economy_receipt_uses_confirmed_snapshot_only', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: EconomyReceipt.confirmed(
            delta: -200,
            summary: 'Alquiler cobrado.',
            resultingBalanceLabel: r'Saldo $800',
          ),
        ),
      ),
    );

    expect(find.text(r'-$200'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        r'Cambio confirmado: -$200. Alquiler cobrado. Saldo $800',
      ),
      findsOneWidget,
    );

    semantics.dispose();
  });

  testWidgets('lost_ack_uses_uncertain_not_success_or_error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: InteractionStatusLayer(
            state: InteractionFeedbackState.uncertain,
          ),
        ),
      ),
    );

    expect(find.text('Confirmando qué pasó…'), findsOneWidget);
    expect(find.byIcon(Icons.manage_search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
  });

  testWidgets('reduced_motion_keeps_final_geometry_and_state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(1.3),
            disableAnimations: true,
          ),
          child: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: AsyncActionButton(
                label: 'Comprar',
                pendingLabel: 'Confirmando…',
                state: InteractionFeedbackState.pending,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(44),
    );
  });
}
