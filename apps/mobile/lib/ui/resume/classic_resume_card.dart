import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';
import '../../design_system/visual_components.dart';

enum ClassicResumeVisualState { available, loading, recoveryError }

class ClassicResumePresentation {
  const ClassicResumePresentation({
    required this.progressLabel,
    required this.savedAtLabel,
    this.state = ClassicResumeVisualState.available,
    this.statusMessage,
  });

  final String progressLabel;
  final String savedAtLabel;
  final ClassicResumeVisualState state;
  final String? statusMessage;
}

class ClassicResumeCard extends StatelessWidget {
  const ClassicResumeCard({
    required this.presentation,
    this.onContinue,
    this.onRetry,
    super.key,
  });

  final ClassicResumePresentation presentation;
  final VoidCallback? onContinue;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final isLoading = presentation.state == ClassicResumeVisualState.loading;
    final isError =
        presentation.state == ClassicResumeVisualState.recoveryError;
    final statusMessage = presentation.statusMessage;

    return Semantics(
      container: true,
      label: _semanticLabel(isLoading: isLoading, isError: isError),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PaperPanel(
            background: AppPalette.kraft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.x3,
                  runSpacing: AppSpacing.x2,
                  children: [
                    Text(
                      'PARTIDA GUARDADA',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const StampBadge(
                      label: 'Clásica',
                      color: AppPalette.bottleGreen,
                      angle: -0.025,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x3),
                Text(
                  presentation.progressLabel,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  presentation.savedAtLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.inkSecondary,
                  ),
                ),
                if (statusMessage != null) ...[
                  const SizedBox(height: AppSpacing.x3),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.x3),
                    decoration: BoxDecoration(
                      color: isError
                          ? AppPalette.surface
                          : AppPalette.canvas,
                      border: Border.all(
                        color: isError
                            ? AppPalette.burgundy
                            : AppPalette.inkSecondary,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.sign),
                    ),
                    child: Text(
                      statusMessage,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppPalette.ink,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.x4),
                if (isError)
                  SizedBox(
                    height: AppSizes.primaryControlHeight,
                    child: OutlinedButton(
                      onPressed: onRetry,
                      child: const Text('Reintentar recuperación'),
                    ),
                  )
                else
                  SizedBox(
                    height: AppSizes.primaryControlHeight,
                    child: FilledButton(
                      onPressed: isLoading ? null : onContinue,
                      child: isLoading
                          ? _LoadingLabel(reduceMotion: reduceMotion)
                          : const Text('Continuar partida'),
                    ),
                  ),
                const SizedBox(height: AppSpacing.x2),
                Text(
                  isError
                      ? 'El estado guardado no se sobrescribe desde esta pantalla.'
                      : 'Se reanuda desde el último estado confirmado por la partida.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.inkSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const Positioned(top: -7, right: 38, child: TapeMark(width: 58)),
        ],
      ),
    );
  }

  String _semanticLabel({required bool isLoading, required bool isError}) {
    final stateCopy = isError
        ? 'La recuperación necesita atención.'
        : isLoading
        ? 'Cargando la partida guardada.'
        : 'Lista para continuar.';
    final message = presentation.statusMessage;

    return [
      'Partida Clásica guardada.',
      presentation.progressLabel,
      presentation.savedAtLabel,
      stateCopy,
      if (message != null) message,
    ].join(' ');
  }
}

class _LoadingLabel extends StatelessWidget {
  const _LoadingLabel({required this.reduceMotion});

  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 18,
          child: reduceMotion
              ? const Icon(Icons.more_horiz_rounded, size: 18)
              : const CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: AppSpacing.x2),
        const Flexible(child: Text('Cargando partida…')),
      ],
    );
  }
}
