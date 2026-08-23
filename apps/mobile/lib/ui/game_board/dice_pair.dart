import 'package:flutter/material.dart';

import '../../design_system/tokens.dart';

class DicePair extends StatelessWidget {
  const DicePair({this.first, this.second, super.key});

  final int? first;
  final int? second;

  bool get _hasConfirmedResult => first != null && second != null;

  @override
  Widget build(BuildContext context) {
    final semanticLabel = _hasConfirmedResult
        ? 'Dados confirmados: $first y $second. Total ${first! + second!}.'
        : 'Dados listos para tirar.';

    return Semantics(
      container: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _DieFace(value: first),
          const SizedBox(width: AppSpacing.x3),
          _DieFace(value: second),
        ],
      ),
    );
  }
}

class _DieFace extends StatelessWidget {
  const _DieFace({required this.value});

  final int? value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppPalette.surface,
        border: Border.all(color: AppPalette.ink, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Text(
        value?.toString() ?? '—',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w900,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
