import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/design_system/tokens.dart';
import 'package:board_mobile/design_system/visual_components.dart';
import 'package:board_mobile/ui/property/property_management_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'property_management_exposes_confirmed_economy_group_and_improvements',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _app(state: PropertyManagementViewState.available),
      );

      expect(
        find.bySemanticsLabel(
          'Propiedad sintética. Propietario: Vos. Grupo Grupo sintético. Grupo completo.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          r'Nivel de mejoras: 2 Manís. Próxima mejora: Maní 3 · $ 100.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          r'Efectivo confirmado: $ 1.000. Proyectado si agregás un Maní: $ 900.',
        ),
        findsOneWidget,
      );
      expect(find.text('Alquiler actual'), findsOneWidget);
      expect(find.text('Hipoteca disponible'), findsOneWidget);

      semantics.dispose();
    },
  );

  testWidgets('property_management_uses_almazen_ledger_hierarchy', (
    tester,
  ) async {
    await tester.pumpWidget(_app(state: PropertyManagementViewState.available));

    expect(find.byType(PaperPanel), findsNWidgets(8));
    expect(find.byType(StampBadge), findsNWidgets(2));
    expect(find.byType(TapeMark), findsOneWidget);
    expect(find.text('EN TU LIBRETA'), findsOneWidget);
    expect(find.text('TU CUENTA'), findsOneWidget);
    expect(find.text('ACCIONES DE LA LIBRETA'), findsOneWidget);
  });

  testWidgets('available_actions_emit_intent_and_caller_disabled_reason_wins', (
    tester,
  ) async {
    PropertyManagementActionKind? intent;

    await tester.pumpWidget(
      _app(
        state: PropertyManagementViewState.available,
        onAction: (value) => intent = value,
      ),
    );

    final buildButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Agregar Maní'),
    );
    final mortgageButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Hipotecar'),
    );

    expect(buildButton.onPressed, isNotNull);
    expect(mortgageButton.onPressed, isNull);
    expect(
      find.text('Primero vendé las mejoras incompatibles'),
      findsOneWidget,
    );

    buildButton.onPressed!();
    expect(intent, PropertyManagementActionKind.addMani);
  });

  testWidgets(
    'pending_action_blocks_conflicts_and_preserves_confirmed_vs_projected_cash',
    (tester) async {
      await tester.pumpWidget(
        _app(
          state: PropertyManagementViewState.pending,
          pendingAction: PropertyManagementActionKind.mortgage,
        ),
      );

      final buttons = tester.widgetList<OutlinedButton>(
        find.byType(OutlinedButton),
      );
      expect(buttons, isNotEmpty);
      expect(buttons.every((button) => button.onPressed == null), isTrue);
      expect(find.text('Hipotecando…'), findsOneWidget);
      expect(
        find.textContaining(
          'Efectivo y mejoras siguen mostrando el último estado confirmado',
        ),
        findsOneWidget,
      );
      expect(find.text('Efectivo confirmado'), findsOneWidget);
      expect(find.text('Proyectado si agregás un Maní'), findsOneWidget);
    },
  );

  testWidgets('confirmed_state_waits_for_fresh_snapshot_before_new_action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        state: PropertyManagementViewState.confirmed,
        confirmationMessage: 'Hipoteca confirmada. Actualizando propiedad.',
      ),
    );

    expect(
      find.text('Hipoteca confirmada. Actualizando propiedad.'),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<OutlinedButton>(find.byType(OutlinedButton))
          .every((button) => button.onPressed == null),
      isTrue,
    );
    expect(find.text('Esperando estado actualizado'), findsWidgets);
  });

  testWidgets('uncertain_compact_property_management_freezes_and_renders', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Center(
          child: SizedBox(
            width: 360,
            height: 700,
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 700),
                textScaler: TextScaler.linear(1.3),
                disableAnimations: true,
              ),
              child: _surface(
                state: PropertyManagementViewState.uncertain,
                propertyLabel: 'Propiedad sintética con nombre bastante largo',
                improvementLevel: 5,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('POPÓN'), findsOneWidget);
    expect(
      tester
          .widgetList<OutlinedButton>(find.byType(OutlinedButton))
          .every((button) => button.onPressed == null),
      isTrue,
    );
    expect(
      find.text(
        'Confirmando qué pasó antes de permitir otra acción equivalente.',
      ),
      findsOneWidget,
    );
  });
}

Widget _app({
  required PropertyManagementViewState state,
  PropertyManagementActionKind? pendingAction,
  String? confirmationMessage,
  ValueChanged<PropertyManagementActionKind>? onAction,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: PropertyManagementSurface(
      propertyLabel: 'Propiedad sintética',
      ownerLabel: 'Vos',
      groupLabel: 'Grupo sintético',
      groupStatusLabel: 'Grupo completo',
      groupSignalColor: AppPalette.ritual,
      improvementLevel: 2,
      rentLabel: r'$ 80',
      nextImprovementLabel: 'Maní 3',
      nextImprovementCostLabel: r'$ 100',
      mortgageStatusLabel: 'Hipoteca disponible',
      mortgageValueLabel: r'Recibís $ 150',
      confirmedCashLabel: r'$ 1.000',
      projectedCashLabel: r'$ 900',
      projectedCashContextLabel: 'si agregás un Maní',
      actions: _actions,
      state: state,
      pendingAction: pendingAction,
      confirmationMessage: confirmationMessage,
      onAction: onAction,
    ),
  );
}

Widget _surface({
  required PropertyManagementViewState state,
  required String propertyLabel,
  required int improvementLevel,
}) {
  return PropertyManagementSurface(
    propertyLabel: propertyLabel,
    ownerLabel: 'Vos',
    groupLabel: 'Grupo sintético',
    groupStatusLabel: 'Grupo completo',
    groupSignalColor: AppPalette.ritual,
    improvementLevel: improvementLevel,
    rentLabel: r'$ 80',
    mortgageStatusLabel: 'Hipoteca disponible',
    mortgageValueLabel: r'Recibís $ 150',
    confirmedCashLabel: r'$ 1.000',
    projectedCashLabel: r'$ 900',
    projectedCashContextLabel: 'si agregás un Maní',
    actions: _actions,
    state: state,
    onAction: (_) {},
  );
}

const _actions = <PropertyManagementActionView>[
  PropertyManagementActionView(
    kind: PropertyManagementActionKind.addMani,
    label: 'Agregar Maní',
    consequenceLabel: r'Pagás $ 100',
    pendingLabel: 'Agregando Maní…',
    enabled: true,
  ),
  PropertyManagementActionView(
    kind: PropertyManagementActionKind.sellImprovement,
    label: 'Vender mejora',
    consequenceLabel: r'Recibís $ 50',
    pendingLabel: 'Vendiendo mejora…',
    enabled: true,
  ),
  PropertyManagementActionView(
    kind: PropertyManagementActionKind.mortgage,
    label: 'Hipotecar',
    consequenceLabel: r'Recibís $ 150',
    pendingLabel: 'Hipotecando…',
    enabled: false,
    disabledReason: 'Primero vendé las mejoras incompatibles',
  ),
  PropertyManagementActionView(
    kind: PropertyManagementActionKind.unmortgage,
    label: 'Levantar hipoteca',
    consequenceLabel: r'Pagás $ 165',
    pendingLabel: 'Levantando hipoteca…',
    enabled: false,
    disabledReason: 'Esta propiedad no está hipotecada',
  ),
];
