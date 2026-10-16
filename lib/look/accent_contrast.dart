/// Readability checks for accents (WCAG 2 contrast), as the accent picker
/// shows them: "Easy to read" / "Hard to read here".
///
/// Pure Dart, so the dashboard's checks can use the same rules.
library;

import 'dart:math' as math;

import '../catalog/catalog.dart';

/// WCAG relative luminance, 0 (black) to 1 (white).
double luminance(HexColor color) {
  double channel(int v) {
    final c = v / 255;
    return c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  final n = color.argb;
  return 0.2126 * channel((n >> 16) & 255) +
      0.7152 * channel((n >> 8) & 255) +
      0.0722 * channel(n & 255);
}

/// WCAG contrast ratio, 1 to 21.
double contrast(HexColor a, HexColor b) {
  final x = luminance(a), y = luminance(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// The weakest contrast any of [accent]'s colours has on [background]: a
/// gradient is only as readable as its faintest stop.
double worstContrast(Accent accent, HexColor background) =>
    accent.colors.map((c) => contrast(c, background)).reduce(math.min);

/// The large clock is big text: 3:1 is enough (WCAG AA, large text).
const clockMinContrast = 3.0;

/// Whether a clock in [accent] stays readable on [background].
bool isReadableClock(Accent accent, HexColor background) =>
    worstContrast(accent, background) >= clockMinContrast;

const _darkLabel = HexColor('#0E0C12');
const _lightLabel = HexColor('#F5F1EA');

/// Text colour for a button filled with [accent]: dark on light accents,
/// light on dark ones, judged by the weakest stop of a gradient.
HexColor labelOn(Accent accent) =>
    worstContrast(accent, _darkLabel) >= worstContrast(accent, _lightLabel)
    ? _darkLabel
    : _lightLabel;
