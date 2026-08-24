import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/ui/settings/accessibility_settings_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sections = <AccessibilitySettingsSection>[
  AccessibilitySettingsSection(
    title: 'Movimiento',
    description: 'PLACEHOLDER: preferencias caller-owned.',
    items: [
      AccessibilitySettingItem(
        id: 'reduce-motion',
        title: 'Reducir movimiento',
        description: 'Respeta una preferencia de presentación.',
        kind: AccessibilitySettingKind.toggle,
      ),
      AccessibilitySettingItem(
        id: 'haptics',
        title: 'Respuesta háptica',
        description: 'PLACEHOLDER: estado provisto por el caller.',
        kind: AccessibilitySettingKind.toggle,
        isSelected: true,
      ),
    ],
  ),
  AccessibilitySettingsSection(
    title: 'Sistema',
    items: [
      AccessibilitySettingItem(
        id: 'text-size',
        title: 'Tamaño de texto',
        description: 'La interfaz usa el tamaño informado por el sistema.',
        kind: AccessibilitySettingKind.status,
        valueLabel: 'Sistema',
      ),
      AccessibilitySettingItem(
        id: 'system-settings',
        title: 'Abrir ajustes del sistema',
        description: 'Acción disponible solo si el caller la provee.',
        kind: AccessibilitySettingKind.action,
      ),
    ],
  ),
];

void main() {
  testWidgets('renders_caller_owned_sections_without_inventing_preferences', (
    tester,
  ) async {
    await _pumpSurface(tester);

    expect(find.text('MOVIMIENTO'), findsOneWidget);
    expect(find.text('Reducir movimiento'), findsOneWidget);
    expect(find.text('Respuesta háptica'), findsOneWidget);
    expect(find.text('Tamaño de texto'), findsOneWidget);
    expect(find.text('Sistema'), findsOneWidget);
    expect(find.text('Sonido'), findsNothing);
    expect(find.text('Alto contraste'), findsNothing);
  });

  testWidgets('toggle_emits_caller_id_and_value_without_local_persistence', (
    tester,
  ) async {
    String? changedId;
    bool? changedValue;

    await _pumpSurface(
      tester,
      onToggleChanged: (settingId, isSelected) {
        changedId = settingId;
        changedValue = isSelected;
      },
    );

    await tester.tap(find.text('Reducir movimiento'));
    await tester.pump();

    expect(changedId, 'reduce-motion');
    expect(changedValue, isTrue);
    expect(
      tester.widget<Switch>(find.byType(Switch).first).value,
      isFalse,
      reason: 'The caller remains the source of the selected state.',
    );
  });

  testWidgets('disabled_setting_exposes_reason_and_blocks_callback', (
    tester,
  ) async {
    var calls = 0;
    const disabledSections = <AccessibilitySettingsSection>[
      AccessibilitySettingsSection(
        title: 'Respuesta',
        items: [
          AccessibilitySettingItem(
            id: 'disabled-placeholder',
            title: 'Preferencia no disponible',
            description: 'PLACEHOLDER: depende del dispositivo.',
            kind: AccessibilitySettingKind.toggle,
            isEnabled: false,
            disabledReason: 'No disponible en este dispositivo.',
          ),
        ],
      ),
    ];

    final semantics = tester.ensureSemantics();
    await _pumpSurface(
      tester,
      sections: disabledSections,
      onToggleChanged: (_, _) => calls += 1,
    );

    expect(find.text('No disponible en este dispositivo.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('disabled-reason-disabled-placeholder')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Preferencia no disponible'), findsOneWidget);

    await tester.tap(find.text('Preferencia no disponible'));
    await tester.pump();
    expect(calls, 0);

    semantics.dispose();
  });

  testWidgets('status_row_is_read_only_and_action_row_is_touchable', (
    tester,
  ) async {
    String? actionId;

    await _pumpSurface(
      tester,
      onActionRequested: (settingId) => actionId = settingId,
    );

    final statusInkWell = tester.widget<InkWell>(
      find
          .ancestor(
            of: find.text('Tamaño de texto'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(statusInkWell.onTap, isNull);

    final actionInkWellFinder = find
        .ancestor(
          of: find.text('Abrir ajustes del sistema'),
          matching: find.byType(InkWell),
        )
        .first;
    expect(
      tester.getSize(actionInkWellFinder).height,
      greaterThanOrEqualTo(44),
    );

    await tester.tap(find.text('Abrir ajustes del sistema'));
    await tester.pump();
    expect(actionId, 'system-settings');
  });

  testWidgets('reflows_at_360_with_130_percent_text_and_reduced_motion', (
    tester,
  ) async {
    await _pumpSurface(
      tester,
      width: 360,
      textScale: 1.3,
      disableAnimations: true,
    );

    final initialSize = tester.getSize(
      find.byType(AccessibilitySettingsSurface),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(AccessibilitySettingsSurface)),
      initialSize,
    );
    expect(find.byType(AnimatedSwitcher), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

Future<void> _pumpSurface(
  WidgetTester tester, {
  List<AccessibilitySettingsSection> sections = _sections,
  AccessibilityToggleChanged? onToggleChanged,
  AccessibilityActionRequested? onActionRequested,
  double width = 390,
  double textScale = 1,
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 844),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: AccessibilitySettingsSurface(
          sections: sections,
          onToggleChanged: onToggleChanged,
          onActionRequested: onActionRequested,
        ),
      ),
    ),
  );
}
