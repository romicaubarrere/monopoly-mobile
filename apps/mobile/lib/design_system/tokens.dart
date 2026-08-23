import 'package:flutter/material.dart';

abstract final class AppPalette {
  static const canvas = Color(0xFFF4EBDD);
  static const surface = Color(0xFFFFF8EC);
  static const ink = Color(0xFF17191A);
  static const inkSecondary = Color(0xFF5F625F);
  static const primary = Color(0xFFC84332);
  static const info = Color(0xFF0D6B66);
  static const focus = Color(0xFF1E5AA8);
  static const danger = Color(0xFFA62E2E);
  static const ritual = Color(0xFFE0A82E);
}

abstract final class AppSpacing {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x10 = 40.0;
}

abstract final class AppRadius {
  static const control = 12.0;
  static const card = 16.0;
  static const sheet = 24.0;
}

abstract final class AppSizes {
  static const minTouchTarget = 44.0;
  static const primaryControlHeight = 52.0;
}

abstract final class AppMotion {
  static const press = Duration(milliseconds: 100);
  static const sheet = Duration(milliseconds: 220);
  static const receipt = Duration(milliseconds: 600);
}
