import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/ui/emotes/emote_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _options = [
  EmoteOption(
    id: 'EMOTE_PLACEHOLDER_01',
    label: 'P1',
    semanticLabel: 'Reacción placeholder uno',
  ),
  EmoteOption(
    id: 'EMOTE_PLACEHOLDER_02',
    label: 'P2',
    semanticLabel: 'Reacción placeholder dos',
  ),
  EmoteOption(
    id: 'EMOTE_PLACEHOLDER_03',
    label: 'P3',
    semanticLabel: 'Reacción placeholder tres',
  ),
  EmoteOption(
    id: 'EMOTE_PLACEHOLDER_04',
    label: 'P4',
    semanticLabel: 'Reacción placeholder cuatro',
  ),
  EmoteOption(
    id: 'EMOTE_PLACEHOLDER_05',
    label: 'P5',
    semanticLabel: 'Reacción placeholder cinco',
  ),
  EmoteOption(
    id: 'EMOTE_PLACEHOLDER_06',
    label: 'P6',
    semanticLabel: 'Reacción placeholder seis',
  ),
];

void main() {
  testWidgets('emote_tray_is_curated_and_has_no_free_text_input', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: EmoteTray(options: _options, onSelected: (_) {}),
        ),
      ),
    );

    expect(find.byType(TextField), findsNothing);
    expect(find.byType(OutlinedButton), findsNWidgets(6));
    expect(find.text('Elegí una reacción rápida. No hay texto libre.'), findsOneWidget);
  });

  testWidgets('emote_selection_emits_only_the_caller_owned_id', (
    tester,
  ) async {
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: EmoteTray(
            options: _options,
            onSelected: (id) => selected = id,
          ),
        ),
      ),
    );

    await tester.tap(find.text('P3'));
    await tester.pump();

    expect(selected, 'EMOTE_PLACEHOLDER_03');
  });

  testWidgets('visual_cooldown_disables_send_and_keeps_reason_visible', (
    tester,
  ) async {
    var calls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: EmoteTray(
            options: _options,
            enabled: false,
            cooldownLabel: 'Esperá antes de reaccionar de nuevo',
            onSelected: (_) => calls += 1,
          ),
        ),
      ),
    );

    expect(find.text('Esperá antes de reaccionar de nuevo'), findsOneWidget);
    final buttons = tester.widgetList<OutlinedButton>(find.byType(OutlinedButton));
    expect(buttons.every((button) => button.onPressed == null), isTrue);
    expect(calls, 0);
  });

  testWidgets('board_emote_access_opens_secondary_tray_and_returns_selection', (
    tester,
  ) async {
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: BoardEmoteAccess(
              options: _options,
              onSelected: (id) => selected = id,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Reacciones'));
    await tester.pumpAndSettle();
    expect(find.text('REACCIONES DE LA MESA'), findsOneWidget);

    await tester.tap(find.text('P2'));
    await tester.pumpAndSettle();

    expect(selected, 'EMOTE_PLACEHOLDER_02');
    expect(find.text('REACCIONES DE LA MESA'), findsNothing);
  });

  testWidgets('emote_bubble_announces_sender_and_reaction_without_own_timer', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: EmoteBubble(senderLabel: 'Leo', option: _options.first),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel('Leo reaccionó: Reacción placeholder uno'),
      findsOneWidget,
    );
    expect(find.text('Leo'), findsOneWidget);
    expect(find.text('P1'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('compact_text_scale_and_reduced_motion_remain_renderable', (
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
                disableAnimations: true,
              ),
              child: Scaffold(
                body: Column(
                  children: [
                    Expanded(
                      child: EmoteTray(options: _options, onSelected: (_) {}),
                    ),
                    const EmoteBubble(
                      senderLabel: 'Jugador con nombre largo',
                      option: _options.first,
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
    final firstChoice = find.widgetWithText(OutlinedButton, 'P1');
    expect(tester.getSize(firstChoice).height, greaterThanOrEqualTo(44));
    final bubble = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(bubble.duration, Duration.zero);
  });
}
