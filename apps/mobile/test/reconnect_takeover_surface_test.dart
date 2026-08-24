import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/ui/reconnect/reconnect_takeover_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('network_unstable_preserves_last_confirmed_context', (
    tester,
  ) async {
    await tester.pumpWidget(_surface(phase: ReconnectPhase.networkUnstable));

    expect(find.text('CONEXIÓN INESTABLE'), findsWidgets);
    expect(find.text('TABLERO CONFIRMADO PLACEHOLDER'), findsOneWidget);
    expect(
      find.text(
        'Solo lectura hasta que el estado autoritativo habilite una acción.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('reconnecting_uses_caller_owned_authority_countdown', (
    tester,
  ) async {
    await tester.pumpWidget(
      _surface(
        phase: ReconnectPhase.reconnecting,
        authorityCountdownLabel: '00:18 PLACEHOLDER',
      ),
    );

    expect(find.text('RECONECTANDO…'), findsOneWidget);
    expect(
      find.text(
        'GRACIA INFORMADA POR SERVIDOR · 00:18 PLACEHOLDER',
      ),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('command_uncertain_never_claims_success', (tester) async {
    await tester.pumpWidget(_surface(phase: ReconnectPhase.commandUncertain));

    expect(find.text('CONFIRMANDO TU ACCIÓN…'), findsOneWidget);
    expect(find.textContaining('Todavía no sabemos'), findsOneWidget);
    expect(find.textContaining('éxito'), findsOneWidget);
    expect(find.text('TABLERO CONFIRMADO PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('grace_expired_does_not_invent_temporary_bot', (tester) async {
    await tester.pumpWidget(
      _surface(phase: ReconnectPhase.graceExpiredNotBlocking),
    );

    expect(
      find.text('TODAVÍA NO HAY BOT TEMPORAL CONFIRMADO'),
      findsOneWidget,
    );
    expect(find.textContaining('no afirma takeover'), findsOneWidget);
    expect(find.text('BOT TEMPORAL'), findsNothing);
  });

  testWidgets('temporary_bot_preserves_human_seat_identity', (tester) async {
    await tester.pumpWidget(
      _surface(phase: ReconnectPhase.temporaryBotActive),
    );

    expect(find.text('UN BOT ESTÁ CUBRIENDO TU LUGAR'), findsOneWidget);
    expect(find.text('ROMINA PLACEHOLDER'), findsOneWidget);
    expect(find.text('BOT TEMPORAL'), findsWidgets);
    expect(find.textContaining('límite estable confirmado'), findsOneWidget);
  });

  testWidgets('reconnected_waiting_reclaim_has_no_instant_reclaim_action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _surface(phase: ReconnectPhase.reconnectedWaitingReclaim),
    );

    expect(find.text('VOLVISTE'), findsWidgets);
    expect(find.textContaining('El bot termina esta acción'), findsOneWidget);
    expect(find.textContaining('Recuperar ahora'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('reclaim_confirmed_exposes_control_restored', (tester) async {
    await tester.pumpWidget(
      _surface(phase: ReconnectPhase.reclaimConfirmed),
    );

    expect(find.text('VOLVISTE A CONTROLAR TU FICHA'), findsOneWidget);
    expect(find.textContaining('nuevo estado autoritativo'), findsOneWidget);
    expect(find.text('TABLERO CONFIRMADO PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('away_summary_is_capped_at_three_confirmed_events', (
    tester,
  ) async {
    await tester.pumpWidget(
      _surface(
        phase: ReconnectPhase.reclaimConfirmed,
        awayEvents: const [
          ReconnectEventView(title: 'EVENTO 1 PLACEHOLDER'),
          ReconnectEventView(title: 'EVENTO 2 PLACEHOLDER'),
          ReconnectEventView(title: 'EVENTO 3 PLACEHOLDER'),
          ReconnectEventView(title: 'EVENTO 4 PLACEHOLDER'),
        ],
      ),
    );

    expect(find.text('MIENTRAS ESTABAS FUERA…'), findsOneWidget);
    expect(find.text('EVENTO 1 PLACEHOLDER'), findsOneWidget);
    expect(find.text('EVENTO 2 PLACEHOLDER'), findsOneWidget);
    expect(find.text('EVENTO 3 PLACEHOLDER'), findsOneWidget);
    expect(find.text('EVENTO 4 PLACEHOLDER'), findsNothing);
  });

  testWidgets('compact_reconnect_renders_at_360dp_and_130_percent_text', (
    tester,
  ) async {
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
                child: const ReconnectTakeoverSurface(
                  phase: ReconnectPhase.temporaryBotActive,
                  playerLabel: 'ROMINA PLACEHOLDER CON NOMBRE LARGO',
                  confirmedContextLabel:
                      'TABLERO CONFIRMADO PLACEHOLDER CON CONTEXTO LARGO',
                  awayEvents: [
                    ReconnectEventView(
                      title: 'ACCIÓN CONFIRMADA PLACEHOLDER CON TEXTO LARGO',
                      detail: 'DETALLE CONFIRMADO PLACEHOLDER CON TEXTO LARGO',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('UN BOT ESTÁ CUBRIENDO TU LUGAR'), findsOneWidget);
    expect(find.text('MIENTRAS ESTABAS FUERA…'), findsOneWidget);
  });
}

Widget _surface({
  required ReconnectPhase phase,
  String? authorityCountdownLabel,
  List<ReconnectEventView> awayEvents = const [],
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: ReconnectTakeoverSurface(
        phase: phase,
        playerLabel: 'ROMINA PLACEHOLDER',
        confirmedContextLabel: 'TABLERO CONFIRMADO PLACEHOLDER',
        authorityCountdownLabel: authorityCountdownLabel,
        awayEvents: awayEvents,
      ),
    ),
  );
}
