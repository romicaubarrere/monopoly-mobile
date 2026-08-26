import 'package:flutter/material.dart';

abstract final class AppPalette {
  // Direction B — the only active visual language from 26 Aug 2026.
  static const canvas = Color(0xFFF7F0E4);
  static const surface = Color(0xFFFFFCF5);
  static const ink = Color(0xFF24382F);
  static const inkSecondary = Color(0xFF5E6B64);
  static const primary = Color(0xFF3F7D61);
  static const primaryDeep = Color(0xFF285642);
  static const coral = Color(0xFFEE7B69);
  static const coralSoft = Color(0xFFFFE2D9);
  static const violet = Color(0xFF765A9B);
  static const violetSoft = Color(0xFFEDE5F6);
  static const greenSoft = Color(0xFFDDEBDD);
  static const creamStrong = Color(0xFFF0E0C5);
  static const info = Color(0xFF4E7185);
  static const focus = Color(0xFF765A9B);
  static const danger = Color(0xFFB84242);
  static const ritual = Color(0xFFE2A43A);

  // Compatibility aliases for already accepted Layer-U surfaces. They resolve
  // to Direction B colors so historical Almacén styling does not propagate.
  static const burgundy = violet;
  static const bottleGreen = primary;
  static const wornBlue = info;
  static const mustard = coral;
  static const kraft = creamStrong;
  static const paperEdge = Color(0xFFD5C9B8);
  static const tape = violetSoft;
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
  static const control = 16.0;
  static const card = 24.0;
  static const sheet = 30.0;
  static const sign = 18.0;
}

abstract final class AppSizes {
  static const minTouchTarget = 44.0;
  static const primaryControlHeight = 52.0;
}

abstract final class AppMotion {
  static const press = Duration(milliseconds: 100);
  static const sheet = Duration(milliseconds: 240);
  static const receipt = Duration(milliseconds: 420);
  static const page = Duration(milliseconds: 260);
}
