import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/design_system/state_primitives.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loading_skeleton_is_static_and_semantically_composed', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(1.3),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: LoadingSkeleton(variant: LoadingSkeletonVariant.page),
            ),
          ),
        ),
      ),
    );

    final initialSize = tester.getSize(find.byType(LoadingSkeleton));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(LoadingSkeleton)), initialSize);
    expect(find.bySemanticsLabel('Cargando contenido'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    semantics.dispose();
  });

  testWidgets('inline_error_keeps_message_and_exposes_retry_target', (
    tester,
  ) async {
    var retries = 0;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: InlineError(
              message: 'PLACEHOLDER: no se pudo validar el dato.',
              kind: InlineErrorKind.retryable,
              onRetry: () => retries += 1,
            ),
          ),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel('Error: PLACEHOLDER: no se pudo validar el dato.'),
      findsOneWidget,
    );
    expect(
      find.text('PLACEHOLDER: no se pudo validar el dato.'),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.widgetWithText(OutlinedButton, 'Reintentar')).height,
      greaterThanOrEqualTo(44),
    );

    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(retries, 1);

    semantics.dispose();
  });

  testWidgets('inline_error_without_retry_does_not_invent_action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: InlineError(
            message: 'PLACEHOLDER: acción no disponible.',
            kind: InlineErrorKind.domain,
          ),
        ),
      ),
    );

    expect(find.text('PLACEHOLDER: acción no disponible.'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('empty_state_has_no_default_character_art', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: EmptyState(
            title: 'Todavía no hay nada acá',
            body: 'PLACEHOLDER contextual.',
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('empty-state-leading')), findsNothing);
    expect(find.text('Todavía no hay nada acá'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('empty_state_reflows_at_360_and_keeps_actions_touchable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(1.3),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: EmptyState(
                title: 'No hay elementos disponibles por ahora',
                body: 'PLACEHOLDER largo para validar reflow sin reducir tipografía.',
                leading: const Icon(Icons.inventory_2_outlined, size: 52),
                primaryLabel: 'Acción caller-owned',
                onPrimary: () {},
                secondaryLabel: 'Volver',
                onSecondary: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('empty-state-leading')), findsOneWidget);
    expect(
      tester
          .getSize(find.widgetWithText(FilledButton, 'Acción caller-owned'))
          .height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSize(find.widgetWithText(OutlinedButton, 'Volver')).height,
      greaterThanOrEqualTo(44),
    );
  });
}
