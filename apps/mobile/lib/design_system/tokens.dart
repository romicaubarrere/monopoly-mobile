import 'package:flutter/material.dart';

abstract final class AppPalette {
  static const canvas = Color(0xFFF2E4C8);
  static const surface = Color(0xFFFFF7E7);
  static const ink = Color(0xFF20231F);
  static const inkSecondary = Color(0xFF665F54);
  static const primary = Color(0xFFA23C31);
  static const info = Color(0xFF365E49);
  static const focus = Color(0xFF2A6578);
  static const danger = Color(0xFFA63730);
  static const ritual = Color(0xFFC89B32);

  static const burgundy = Color(0xFF7F302C);
  static const bottleGreen = Color(0xFF365E49);
  static const wornBlue = Color(0xFF2A6578);
  static const mustard = Color(0xFFC89B32);
  static const kraft = Color(0xFFE3C89A);
  static const paperEdge = Color(0xFFC8B58F);
  static const tape = Color(0xFFD8CAA8);
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
  static const sign = 8.0;
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
