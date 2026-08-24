import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/design_system/status_badges.dart';
import 'package:board_mobile/design_system/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('connection states expose explicit icon and text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Wrap(
            children: [
              ConnectionBadge(state: ConnectionBadgeState.online),
              ConnectionBadge(state: ConnectionBadgeState.unstable),
              ConnectionBadge(state: ConnectionBadgeState.reconnecting),
              ConnectionBadge(state: ConnectionBadgeState.offline),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Conectado'), findsOneWidget);
    expect(find.text('Conexión inestable'), findsOneWidget);
    expect(find.text('Reconectando'), findsOneWidget);
    expect(find.text('Sin conexión'), findsOneWidget);
    expect(find.byIcon(Icons.wifi), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off), findsOneWidget);
  });

  testWidgets('temporary bot identity is explicit', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: BotBadge(temporary: true)),
      ),
    );

    expect(find.text('Bot temporal'), findsOneWidget);
    expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
    expect(find.bySemanticsLabel('Bot temporal'), findsOneWidget);
  });

  testWidgets('interactive player chip meets target and emits tap', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PlayerChip(name: 'PLACEHOLDER', onTap: () => taps += 1),
        ),
      ),
    );

    final size = tester.getSize(find.byType(PlayerChip));
    expect(size.height, greaterThanOrEqualTo(AppSizes.minTouchTarget));

    await tester.tap(find.byType(PlayerChip));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('player and turn state remain explicit without color', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Column(
            children: [
              PlayerChip(name: 'Romina', isSelf: true, statusLabel: 'Lista'),
              TurnBadge(label: 'Romina', isCurrent: true),
            ],
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Romina, vos, Lista'), findsOneWidget);
    expect(find.bySemanticsLabel('Turno actual, Romina'), findsOneWidget);
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.byIcon(Icons.casino), findsOneWidget);
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
            height: 500,
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 500),
                textScaler: TextScaler.linear(1.3),
              ),
              child: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(AppSpacing.x3),
                  child: Wrap(
                    spacing: AppSpacing.x2,
                    runSpacing: AppSpacing.x2,
                    children: [
                      PlayerChip(
                        name: 'JUGADOR PLACEHOLDER CON NOMBRE LARGO',
                        isSelf: true,
                        statusLabel: 'Esperando confirmación',
                      ),
                      TurnBadge(label: 'JUGADOR PLACEHOLDER', isCurrent: true),
                      ConnectionBadge(state: ConnectionBadgeState.unstable),
                      BotBadge(temporary: true),
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
    expect(find.text('Bot temporal'), findsOneWidget);
  });
}
