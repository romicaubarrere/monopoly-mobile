import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/design_system/tokens.dart';
import 'package:board_mobile/ui/first_playable/first_playable_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const viewports = <Size>[
    Size(360, 800),
    Size(390, 844),
    Size(412, 915),
    Size(430, 932),
  ];

  const checkpoints = <FirstPlayableStep>[
    FirstPlayableStep.home,
    FirstPlayableStep.createRoom,
    FirstPlayableStep.lobby,
    FirstPlayableStep.board,
    FirstPlayableStep.propertyOffer,
    FirstPlayableStep.auction,
    FirstPlayableStep.reconnect,
  ];

  for (final viewport in viewports) {
    for (final checkpoint in checkpoints) {
      testWidgets(
        '${checkpoint.name} renders at ${viewport.width.toInt()}dp and 130%',
        (tester) async {
          await tester.binding.setSurfaceSize(viewport);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: MediaQuery(
                data: MediaQueryData(
                  size: viewport,
                  textScaler: const TextScaler.linear(1.3),
                  disableAnimations: true,
                ),
                child: FirstPlayableApp(initialStep: checkpoint),
              ),
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.byType(Scaffold), findsOneWidget);
        },
      );
    }
  }

  testWidgets('vertical board exposes one structural semantics summary', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const FirstPlayableApp(initialStep: FirstPlayableStep.board),
      ),
    );

    expect(
      find.bySemanticsLabel(
        'Tablero vertical de 40 posiciones PLACEHOLDER. Ficha en la posición 1.',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Casillero PLACEHOLDER 1'), findsNothing);

    semantics.dispose();
  });

  testWidgets('primary actions meet the 44dp minimum touch target', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const FirstPlayableApp()),
    );

    final createSize = tester.getSize(
      find.widgetWithText(FilledButton, 'Crear partida'),
    );
    final joinSize = tester.getSize(
      find.widgetWithText(OutlinedButton, 'Unirse con código'),
    );
    expect(createSize.height, greaterThanOrEqualTo(AppSizes.minTouchTarget));
    expect(joinSize.height, greaterThanOrEqualTo(AppSizes.minTouchTarget));
  });
}
