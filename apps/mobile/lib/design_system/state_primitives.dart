import 'package:flutter/material.dart';

import 'tokens.dart';
import 'visual_components.dart';

enum LoadingSkeletonVariant { page, sheet, row }

enum InlineErrorKind { validation, domain, retryable }

class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({
    super.key,
    this.variant = LoadingSkeletonVariant.row,
    this.semanticsLabel = 'Cargando contenido',
  });

  final LoadingSkeletonVariant variant;
  final String semanticsLabel;

  double get _minHeight => switch (variant) {
    LoadingSkeletonVariant.page => 180,
    LoadingSkeletonVariant.sheet => 128,
    LoadingSkeletonVariant.row => 72,
  };

  int get _barCount => switch (variant) {
    LoadingSkeletonVariant.page => 5,
    LoadingSkeletonVariant.sheet => 4,
    LoadingSkeletonVariant.row => 2,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: _minHeight),
          child: PaperPanel(
            background: AppPalette.kraft,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: TapeMark(width: 42),
                ),
                const SizedBox(height: AppSpacing.x3),
                for (var index = 0; index < _barCount; index += 1) ...[
                  _SkeletonBar(
                    widthFactor: index.isEven ? 0.82 : 0.58,
                    height: index == 0 ? 16 : 12,
                  ),
                  if (index != _barCount - 1)
                    const SizedBox(height: AppSpacing.x2),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InlineError extends StatelessWidget {
  const InlineError({
    required this.message,
    super.key,
    this.kind = InlineErrorKind.validation,
    this.retryLabel = 'Reintentar',
    this.onRetry,
  });

  final String message;
  final InlineErrorKind kind;
  final String retryLabel;
  final VoidCallback? onRetry;

  IconData get _icon => switch (kind) {
    InlineErrorKind.validation => Icons.error_outline_rounded,
    InlineErrorKind.domain => Icons.info_outline_rounded,
    InlineErrorKind.retryable => Icons.sync_problem_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return PaperPanel(
      borderColor: AppPalette.danger,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon, color: AppPalette.danger),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: 'Error: $message',
                  child: ExcludeSemantics(
                    child: Text(
                      message,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppPalette.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.x3),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(retryLabel),
            ),
          ],
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    required this.body,
    super.key,
    this.leading,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String body;
  final Widget? leading;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return PaperPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: StampBadge(label: 'POR AHORA', angle: -0.025),
          ),
          if (leading != null) ...[
            const SizedBox(height: AppSpacing.x4),
            Center(key: const ValueKey('empty-state-leading'), child: leading),
          ],
          const SizedBox(height: AppSpacing.x4),
          Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(body),
          if (onPrimary != null) ...[
            const SizedBox(height: AppSpacing.x4),
            FilledButton(
              onPressed: onPrimary,
              child: Text(primaryLabel ?? 'Continuar'),
            ),
          ],
          if (onSecondary != null) ...[
            const SizedBox(height: AppSpacing.x2),
            OutlinedButton(
              onPressed: onSecondary,
              child: Text(secondaryLabel ?? 'Volver'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.widthFactor, required this.height});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppPalette.paperEdge,
          borderRadius: BorderRadius.circular(AppRadius.sign),
        ),
      ),
    );
  }
}
