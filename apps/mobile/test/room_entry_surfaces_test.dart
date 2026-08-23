import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/ui/room_entry/create_room_screen.dart';
import 'package:board_mobile/ui/room_entry/join_room_screen.dart';
import 'package:board_mobile/ui/room_entry/lobby_screen.dart';
import 'package:board_mobile/ui/room_entry/room_entry_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const expressPreset = PresetViewData(
  id: 'express',
  title: 'Express',
  durationLabel: 'Objetivo: partida corta',
  endConditionLabel: 'Cierre: configuración resuelta por la sala',
  differenceSummary: 'Resumen sintético; sin caps finales hardcodeados.',
  tone: PresetTone.experimental,
);

const classicPreset = PresetViewData(
  id: 'classic',
  title: 'Clásica',
  durationLabel: 'Objetivo: partida larga',
  endConditionLabel: 'Cierre: condición configurada',
  differenceSummary: 'Baseline de presentación para el checkpoint UX.',
);

void main() {
  testWidgets('create room selects preset without inventing resolved rules', (
    tester,
  ) async {
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CreateRoomScreen(
          presets: const [expressPreset, classicPreset],
          selectedPresetId: 'classic',
          onSelectPreset: (value) => selected = value,
          onCreateRoom: () {},
        ),
      ),
    );

    await tester.tap(find.text('Express'));
    expect(selected, 'express');
    expect(
      find.textContaining('sin caps finales hardcodeados'),
      findsOneWidget,
    );
  });

  testWidgets(
    'join room keeps code after recoverable error and normalizes it',
    (tester) async {
      String? submitted;

      Widget build({String? errorMessage}) {
        return MaterialApp(
          theme: AppTheme.light,
          home: JoinRoomScreen(
            onJoinRoom: (code) => submitted = code,
            errorMessage: errorMessage,
          ),
        );
      }

      await tester.pumpWidget(build());
      await tester.enterText(find.byType(TextField), 'ab12cd');
      await tester.pump();
      await tester.tap(find.text('Unirse a sala'));
      expect(submitted, 'AB12CD');

      await tester.pumpWidget(
        build(errorMessage: 'Esa sala no está disponible.'),
      );
      await tester.pump();

      expect(find.text('ab12cd'), findsOneWidget);
      expect(find.text('Esa sala no está disponible.'), findsOneWidget);
    },
  );

  testWidgets('lobby groups six-character code and explains disabled start', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LobbyScreen(
          roomCode: 'abc123',
          seats: const [
            LobbySeatViewData(
              id: 'self',
              displayName: 'Vos',
              isReady: true,
              isHost: true,
              isSelf: true,
            ),
            LobbySeatViewData(
              id: 'bot',
              displayName: 'Bot balanced',
              isReady: true,
              isBot: true,
            ),
          ],
          preset: expressPreset,
          isHost: true,
          isSelfReady: true,
          canStart: false,
          onStartGame: () {},
        ),
      ),
    );

    expect(find.text('ABC 123'), findsOneWidget);
    final startButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Empezar partida'),
    );
    expect(startButton.onPressed, isNull);
    expect(
      find.textContaining('cuando el estado de la sala lo permita'),
      findsOneWidget,
    );
  });

  testWidgets('room entry surfaces tolerate 360dp and 130 percent text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Center(
          child: SizedBox(
            width: 360,
            height: 800,
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.3),
              ),
              child: LobbyScreen(
                roomCode: 'abc123',
                seats: const [
                  LobbySeatViewData(
                    id: 'self',
                    displayName: 'Nombre de jugador bastante largo',
                    isReady: false,
                    isSelf: true,
                  ),
                ],
                preset: expressPreset,
                isHost: false,
                isSelfReady: false,
                canStart: false,
                onToggleReady: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Estoy listo'), findsOneWidget);
  });
}
