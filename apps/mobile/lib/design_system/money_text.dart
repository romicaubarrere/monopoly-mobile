import 'package:flutter/material.dart';

import 'tokens.dart';

enum MoneyDeltaTone { positive, negative, neutral }

class MoneyText extends StatelessWidget {
  const MoneyText({
    required this.value,
    required this.semanticLabel,
    this.emphasized = false,
    this.style,
    this.textAlign,
    super.key,
  });

  final String value;
  final String semanticLabel;
  final bool emphasized;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: AppPalette.ink,
      fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Text(value, textAlign: textAlign, style: baseStyle?.merge(style)),
    );
  }
}

class MoneyDelta extends StatelessWidget {
  const MoneyDelta({
    required this.value,
    required this.semanticLabel,
    required this.tone,
    this.style,
    super.key,
  });

  final String value;
  final String semanticLabel;
  final MoneyDeltaTone tone;
  final TextStyle? style;

  Color get _color => switch (tone) {
    MoneyDeltaTone.positive => AppPalette.info,
    MoneyDeltaTone.negative => AppPalette.danger,
    MoneyDeltaTone.neutral => AppPalette.inkSecondary,
  };

  IconData get _icon => switch (tone) {
    MoneyDeltaTone.positive => Icons.arrow_upward_rounded,
    MoneyDeltaTone.negative => Icons.arrow_downward_rounded,
    MoneyDeltaTone.neutral => Icons.remove_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: _color,
      fontWeight: FontWeight.w900,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Wrap(
        spacing: AppSpacing.x1,
        runSpacing: AppSpacing.x1,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(_icon, size: 18, color: _color),
          Text(value, style: baseStyle?.merge(style)),
        ],
      ),
    );
  }
}
