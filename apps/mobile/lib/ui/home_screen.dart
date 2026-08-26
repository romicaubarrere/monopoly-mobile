import 'package:flutter/material.dart';

import '../design_system/tokens.dart';
import '../design_system/visual_components.dart';
import 'resume/classic_resume_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    this.onCreateRoom,
    this.onJoinRoom,
    this.savedClassic,
    this.onContinueClassic,
    this.onRetryClassic,
    super.key,
  });

  final VoidCallback? onCreateRoom;
  final VoidCallback? onJoinRoom;
  final ClassicResumePresentation? savedClassic;
  final VoidCallback? onContinueClassic;
  final VoidCallback? onRetryClassic;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('direction-b-home'),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final gutter = constraints.maxWidth < 375
                ? AppSpacing.x3
                : AppSpacing.x5;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                gutter,
                AppSpacing.x4,
                gutter,
                AppSpacing.x8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _HomeHeader(),
                  const SizedBox(height: AppSpacing.x5),
                  const _HomeHero(),
                  const SizedBox(height: AppSpacing.x5),
                  FilledButton.icon(
                    onPressed: onCreateRoom,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: const Text('Crear partida'),
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  OutlinedButton.icon(
                    onPressed: onJoinRoom,
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Unirse con código'),
                  ),
                  if (savedClassic != null) ...[
                    const SizedBox(height: AppSpacing.x5),
                    ClassicResumeCard(
                      presentation: savedClassic!,
                      onContinue: onContinueClassic,
                      onRetry: onRetryClassic,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.x6),
                  const _FirstPlayablePromise(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.x3,
      runSpacing: AppSpacing.x2,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(
          header: true,
          child: Text(
            'LA VUELTA',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppPalette.primaryDeep,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const GamePill(
          label: 'LISTA PARA JUGAR',
          color: AppPalette.violet,
          icon: Icons.favorite_rounded,
        ),
      ],
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero();

  @override
  Widget build(BuildContext context) {
    return GameCard(
      background: AppPalette.greenSoft,
      borderColor: AppPalette.primary,
      padding: const EdgeInsets.all(AppSpacing.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: CharacterArtSlot(
                  identity: CharacterIdentity.mani,
                  size: 112,
                ),
              ),
              const SizedBox(width: AppSpacing.x4),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Una vuelta más.\nUna historia nueva.',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: AppPalette.primaryDeep,
                            height: 0.98,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.x3),
                    Text(
                      'Jugá con tu gente, picanteá la mesa y volvé siempre al tablero.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppPalette.inkSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          Container(
            padding: const EdgeInsets.all(AppSpacing.x3),
            decoration: BoxDecoration(
              color: AppPalette.surface,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: AppPalette.coral),
                SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Text(
                    'Maní guía la partida. Su ilustración final espera la foto fuente.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FirstPlayablePromise extends StatelessWidget {
  const _FirstPlayablePromise();

  @override
  Widget build(BuildContext context) {
    return GameCard(
      background: AppPalette.violetSoft,
      borderColor: AppPalette.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PRIMERA VUELTA',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppPalette.violet,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            'Sala • tablero • dados • propiedad • subasta • reconexión.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            'Los nombres, valores y casilleros pendientes usan PLACEHOLDER según DEC-065.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppPalette.inkSecondary),
          ),
        ],
      ),
    );
  }
}
