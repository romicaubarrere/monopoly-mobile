import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/design_system/tokens.dart';
import 'package:board_mobile/ui/home_screen.dart';
import 'package:board_mobile/ui/resume/classic_resume_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _available = ClassicResumePresentation(
  progressLabel: 'Ronda de muestra · turno confirmado',
  savedAtLabel: 'Guardada · referencia de muestra',
);

void main() {
  testWidgets('Home hides Continue Classic when caller has no saved game', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );

    expect(find.text('PARTIDA GUARDADA'), findsNothing);
    expect(find.text('Continuar partida'), findsNothing);
  });

  testWidgets('available saved game stays caller-owned and emits continue', (
    tester,
  ) async {
    var continueCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(
          savedClassic: _available,
          onContinueClassic: () => continueCount += 1,
        ),
      ),
    );

    expect(find.text('PARTIDA GUARDADA'), findsOneWidget);
    expect(find.text('CLÁSICA'), findsOneWidget);
    expect(find.text(_available.progressLabel), findsOneWidget);
    expect(find.text(_available.savedAtLabel), findsOneWidget);

    await tester.ensureVisible(find.text('Continuar partida'));
    await tester.tap(find.text('Continuar partida'));
    await tester.pump();

    expect(continueCount, 1);
  });

  testWidgets('loading preserves confirmed summary and blocks second intent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const HomeScreen(
          savedClassic: ClassicResumePresentation(
            progressLabel: 'Estado confirmado de muestra',
            savedAtLabel: 'Guardada · referencia de muestra',
            state: ClassicResumeVisualState.loading,
            statusMessage: 'Validando el snapshot antes de volver a la mesa.',
          ),
        ),
      ),
    );

    expect(find.text('Estado confirmado de muestra'), findsOneWidget);
    expect(
      find.text('Validando el snapshot antes de volver a la mesa.'),
      findsOneWidget,
    );
    expect(find.text('Cargando partida…'), findsOneWidget);
    expect(find.text('Continuar partida'), findsNothing);
  });

  testWidgets('recovery error does not overwrite evidence and emits retry', (
    tester,
  ) async {
    var retryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(
          savedClassic: const ClassicResumePresentation(
            progressLabel: 'Último estado confirmado disponible',
            savedAtLabel: 'Guardada · referencia de muestra',
            state: ClassicResumeVisualState.recoveryError,
            statusMessage: 'No pudimos preparar esta partida para continuar.',
          ),
          onRetryClassic: () => retryCount += 1,
        ),
      ),
    );

    expect(
      find.text('No pudimos preparar esta partida para continuar.'),
      findsOneWidget,
    );
    expect(
      find.text('El estado guardado no se sobrescribe desde esta pantalla.'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Reintentar recuperación'));
    await tester.tap(find.text('Reintentar recuperación'));
    await tester.pump();

    expect(retryCount, 1);
  });

  testWidgets('Continue Classic remains usable at 360dp and 130 percent text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 360,
            height: 800,
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.3),
                disableAnimations: true,
              ),
              child: const HomeScreen(savedClassic: _available),
            ),
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Continuar partida'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    final continueSize = tester.getSize(
      find.widgetWithText(FilledButton, 'Continuar partida'),
    );
    expect(continueSize.height, greaterThanOrEqualTo(AppSizes.minTouchTarget));
  });
}
