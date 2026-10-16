import 'package:flutter/material.dart';

/// "Night Market" colors for the app's own UI (not the seasonal wallpapers).
/// A near-black ground lets the dark, glowing wallpapers stand out.
class AppColors {
  AppColors._();

  static const background = Color(0xFF0E0C12);
  static const surface = Color(0xFF1A1720);
  static const surfaceHigh = Color(0xFF26222E);
  static const outline = Color(0xFF332E3D);
  static const textPrimary = Color(0xFFF5F1EA);
  static const textSecondary = Color(0xFFA39DAE);

  /// App brand color: warm lantern amber.
  static const brand = Color(0xFFFFB547);

  /// Readable text/icon color on top of [color].
  static Color onColor(Color color) =>
      ThemeData.estimateBrightnessForColor(color) == Brightness.light
      ? background
      : textPrimary;
}
