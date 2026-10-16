/// What the accent picker offers for a theme (the "Accent picker" screen),
/// and how a custom accent is made. Pure Dart.
library;

import '../catalog/catalog.dart';
import 'accent_contrast.dart';

/// The picker's sections, in order, without repeats: an accent offered by
/// the theme isn't offered again as a preset of the same colours.
class AccentChoices {
  const AccentChoices({
    required this.theme,
    required this.solids,
    required this.gradients,
    required this.mine,
    required this.background,
  });

  factory AccentChoices.forTheme(
    ThemeDetail theme,
    AccentPresets presets,
    List<Accent> mine, {
    String? variantId,
  }) {
    final seen = {for (final a in theme.accents) a.key};
    List<Accent> fresh(List<Accent> list) => [
      for (final a in list)
        if (seen.add(a.key)) a,
    ];
    return AccentChoices(
      theme: theme.accents,
      solids: fresh(presets.solids),
      gradients: fresh(presets.gradients),
      mine: mine,
      background: theme.paletteFor(variantId).background,
    );
  }

  /// The theme's own accents (first = default).
  final List<Accent> theme;
  final List<Accent> solids;
  final List<Accent> gradients;

  /// The user's saved custom accents, newest first.
  final List<Accent> mine;

  /// The wallpaper's sky, which the clock sits on.
  final HexColor background;

  List<Accent> get all => [...theme, ...solids, ...gradients, ...mine];

  /// "Easy to read" / "Hard to read here" for a clock in [accent].
  bool isReadable(Accent accent) => isReadableClock(accent, background);
}

extension on Accent {
  /// Same look = same colours and, for gradients, the same direction.
  String get key =>
      '${colors.map((c) => c.hex.toUpperCase()).join(',')}'
      '${type == AccentType.gradient ? '@$angle' : ''}';
}

/// The four directions the picker offers, in CSS degrees.
const gradientDirections = [90, 135, 180, 45];

/// A custom accent from the picker's colour wells: one colour, or a
/// two-colour gradient in one of [gradientDirections].
Accent customAccent({
  required String id,
  required String name,
  required HexColor start,
  HexColor? end,
  int angle = 135,
}) {
  if (end != null && !gradientDirections.contains(angle)) {
    throw ArgumentError.value(angle, 'angle', 'not one of $gradientDirections');
  }
  return Accent(
    id: id,
    name: LocalizedText.en(name),
    colors: [start, ?end],
    angle: end == null ? 90 : angle,
  );
}

/// Same colours (and direction, for a gradient).
bool sameLook(Accent a, Accent b) => a.key == b.key;
