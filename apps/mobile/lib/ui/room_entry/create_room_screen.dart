import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import 'room_entry_components.dart';
import 'room_entry_models.dart';

class CreateRoomScreen extends StatelessWidget {
  const CreateRoomScreen({
    required this.presets,
    required this.selectedPresetId,
    required this.onSelectPreset,
    required this.onCreateRoom,
    this.isPending = false,
    this.errorMessage,
    super.key,
  });

  final List<PresetViewData> presets;
  final String? selectedPresetId;
  final ValueChanged<String> onSelectPreset;
  final VoidCallback? onCreateRoom;
  final bool isPending;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final canCreate =
        selectedPresetId != null && !isPending && onCreateRoom != null;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 375;
            final gutter = compact ? AppSpacing.x3 : AppSpacing.x5;

            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      AppSpacing.x5,
                      gutter,
                      AppSpacing.x4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            'Elegí cómo se juega',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.x2),
                        Text(
                          'La duración es un objetivo, no una promesa. Las reglas efectivas llegan como configuración versionada.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: AppPalette.inkSecondary,
                                height: 1.35,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.x5),
                        if (presets.isEmpty)
                          const InlineStatusMessage(
                            message: 'Todavía no hay presets disponibles.',
                          )
                        else
                          ...presets.map(
                            (preset) => Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.x3,
                              ),
                              child: PresetOptionCard(
                                preset: preset,
                                isSelected: preset.id == selectedPresetId,
                                onSelected: isPending
                                    ? null
                                    : () => onSelectPreset(preset.id),
                              ),
                            ),
                          ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: AppSpacing.x2),
                          InlineStatusMessage(
                            message: errorMessage!,
                            isError: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    AppSpacing.x3,
                    gutter,
                    AppSpacing.x4,
                  ),
                  decoration: const BoxDecoration(
                    color: AppPalette.canvas,
                    border: Border(
                      top: BorderSide(
                        color: AppPalette.inkSecondary,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: FilledButton(
                    onPressed: canCreate ? onCreateRoom : null,
                    child: Text(isPending ? 'Creando sala…' : 'Crear sala'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
