import 'package:flutter/material.dart';

import 'tokens.dart';

abstract final class AppTheme {
  static ThemeData get light {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppPalette.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppPalette.primary,
          onPrimary: AppPalette.surface,
          secondary: AppPalette.coral,
          onSecondary: AppPalette.ink,
          surface: AppPalette.surface,
          onSurface: AppPalette.ink,
          error: AppPalette.danger,
          outline: AppPalette.inkSecondary,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppPalette.canvas,
    );

    return base.copyWith(
      textTheme: base.textTheme
          .apply(bodyColor: AppPalette.ink, displayColor: AppPalette.ink)
          .copyWith(
            displayLarge: base.textTheme.displayLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -1.8,
              height: 0.94,
            ),
            headlineLarge: base.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -1.0,
            ),
            headlineMedium: base.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            ),
            titleLarge: base.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(
            AppSizes.minTouchTarget,
            AppSizes.primaryControlHeight,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(
            AppSizes.minTouchTarget,
            AppSizes.primaryControlHeight,
          ),
          foregroundColor: AppPalette.ink,
          side: const BorderSide(color: AppPalette.ink),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppPalette.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x4,
          vertical: AppSpacing.x4,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppPalette.inkSecondary),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(
            color: AppPalette.inkSecondary.withValues(alpha: 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppPalette.violet, width: 2),
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: AppPalette.surface,
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(color: AppPalette.inkSecondary),
      iconTheme: const IconThemeData(color: AppPalette.primaryDeep),
      focusColor: AppPalette.focus,
    );
  }
}
