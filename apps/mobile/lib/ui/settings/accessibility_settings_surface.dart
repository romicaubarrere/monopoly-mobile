import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';

enum AccessibilitySettingKind { toggle, action, status }

class AccessibilitySettingItem {
  const AccessibilitySettingItem({
    required this.id,
    required this.title,
    required this.description,
    required this.kind,
    this.isEnabled = true,
    this.isSelected = false,
    this.valueLabel,
    this.disabledReason,
  });

  final String id;
  final String title;
  final String description;
  final AccessibilitySettingKind kind;
  final bool isEnabled;
  final bool isSelected;
  final String? valueLabel;
  final String? disabledReason;
}

class AccessibilitySettingsSection {
  const AccessibilitySettingsSection({
    required this.title,
    required this.items,
    this.description,
  });

  final String title;
  final String? description;
  final List<AccessibilitySettingItem> items;
}

typedef AccessibilityToggleChanged =
    void Function(String settingId, bool isSelected);
typedef AccessibilityActionRequested = void Function(String settingId);

class AccessibilitySettingsSurface extends StatelessWidget {
  const AccessibilitySettingsSurface({
    required this.sections,
    super.key,
    this.title = 'Ajustes y accesibilidad',
    this.subtitle =
        'Preferencias de presentación provistas por la aplicación o el sistema.',
    this.onToggleChanged,
    this.onActionRequested,
  });

  final List<AccessibilitySettingsSection> sections;
  final String title;
  final String subtitle;
  final AccessibilityToggleChanged? onToggleChanged;
  final AccessibilityActionRequested? onActionRequested;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x4,
            AppSpacing.x4,
            AppSpacing.x4,
            AppSpacing.x8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: TapeMark(width: 54),
              ),
              const SizedBox(height: AppSpacing.x2),
              Align(
                alignment: Alignment.centerLeft,
                child: StampBadge(
                  label: 'AJUSTES',
                  color: AppPalette.wornBlue,
                  angle: -0.025,
                ),
              ),
              const SizedBox(height: AppSpacing.x4),
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.x2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppPalette.inkSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.x6),
              for (var index = 0; index < sections.length; index += 1) ...[
                _SettingsSection(
                  section: sections[index],
                  onToggleChanged: onToggleChanged,
                  onActionRequested: onActionRequested,
                ),
                if (index != sections.length - 1)
                  const SizedBox(height: AppSpacing.x6),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.section,
    required this.onToggleChanged,
    required this.onActionRequested,
  });

  final AccessibilitySettingsSection section;
  final AccessibilityToggleChanged? onToggleChanged;
  final AccessibilityActionRequested? onActionRequested;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            section.title.toUpperCase(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppPalette.burgundy,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ),
        if (section.description case final description?) ...[
          const SizedBox(height: AppSpacing.x1),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.inkSecondary,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.x3),
        for (var index = 0; index < section.items.length; index += 1) ...[
          _SettingRow(
            item: section.items[index],
            onToggleChanged: onToggleChanged,
            onActionRequested: onActionRequested,
          ),
          if (index != section.items.length - 1)
            const SizedBox(height: AppSpacing.x3),
        ],
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.item,
    required this.onToggleChanged,
    required this.onActionRequested,
  });

  final AccessibilitySettingItem item;
  final AccessibilityToggleChanged? onToggleChanged;
  final AccessibilityActionRequested? onActionRequested;

  bool get _isInteractive => switch (item.kind) {
    AccessibilitySettingKind.toggle =>
      item.isEnabled && onToggleChanged != null,
    AccessibilitySettingKind.action =>
      item.isEnabled && onActionRequested != null,
    AccessibilitySettingKind.status => false,
  };

  String get _semanticValue => switch (item.kind) {
    AccessibilitySettingKind.toggle =>
      item.isSelected ? 'Activado' : 'Desactivado',
    AccessibilitySettingKind.action => item.valueLabel ?? '',
    AccessibilitySettingKind.status => item.valueLabel ?? '',
  };

  String? get _semanticHint {
    if (!item.isEnabled && item.disabledReason != null) {
      return item.disabledReason;
    }
    return switch (item.kind) {
      AccessibilitySettingKind.toggle => 'Tocá para cambiar esta preferencia.',
      AccessibilitySettingKind.action => 'Tocá para abrir esta opción.',
      AccessibilitySettingKind.status => null,
    };
  }

  void _activate() {
    switch (item.kind) {
      case AccessibilitySettingKind.toggle:
        onToggleChanged?.call(item.id, !item.isSelected);
        return;
      case AccessibilitySettingKind.action:
        onActionRequested?.call(item.id);
        return;
      case AccessibilitySettingKind.status:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: item.kind == AccessibilitySettingKind.action,
      toggled: item.kind == AccessibilitySettingKind.toggle
          ? item.isSelected
          : null,
      enabled: item.kind == AccessibilitySettingKind.status
          ? null
          : item.isEnabled,
      label: item.title,
      value: _semanticValue,
      hint: _semanticHint,
      onTap: _isInteractive ? _activate : null,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: _isInteractive ? _activate : null,
          borderRadius: BorderRadius.circular(AppRadius.sign),
          child: PaperPanel(
            background: item.isEnabled ? AppPalette.surface : AppPalette.kraft,
            borderColor: item.isEnabled
                ? AppPalette.ink
                : AppPalette.inkSecondary,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x4,
              vertical: AppSpacing.x3,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSizes.minTouchTarget,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.x1),
                        Text(
                          item.description,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppPalette.inkSecondary,
                          ),
                        ),
                        if (!item.isEnabled &&
                            item.disabledReason != null) ...[
                          const SizedBox(height: AppSpacing.x2),
                          Text(
                            item.disabledReason!,
                            key: ValueKey('disabled-reason-${item.id}'),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppPalette.danger,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x3),
                  _SettingControl(item: item, isInteractive: _isInteractive),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingControl extends StatelessWidget {
  const _SettingControl({required this.item, required this.isInteractive});

  final AccessibilitySettingItem item;
  final bool isInteractive;

  @override
  Widget build(BuildContext context) {
    return switch (item.kind) {
      AccessibilitySettingKind.toggle => IgnorePointer(
        child: Switch(
          value: item.isSelected,
          onChanged: isInteractive ? (_) {} : null,
        ),
      ),
      AccessibilitySettingKind.action => ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppSizes.minTouchTarget,
          minHeight: AppSizes.minTouchTarget,
        ),
        child: const Icon(Icons.chevron_right_rounded),
      ),
      AccessibilitySettingKind.status => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            item.valueLabel ?? '—',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppPalette.wornBlue,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    };
  }
}
