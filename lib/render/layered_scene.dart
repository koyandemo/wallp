import 'package:flutter/painting.dart';

import '../catalog/catalog.dart';

/// A `layers` engine scene ready to draw: its layers, with every palette
/// token (`@accent`, `@motif`…) turned into a colour for this theme,
/// variant and accent.
class LayeredScene {
  const LayeredScene({
    required this.layers,
    required this.tokens,
    this.accentGradient,
  });

  final List<Layer> layers;

  /// `@background` → its colour, for every token in [SceneColor.tokens].
  final Map<String, Color> tokens;

  /// Paints `@accent` shapes when the accent is a gradient.
  final Gradient? accentGradient;

  /// The pictures this scene draws, to load before painting.
  Iterable<AssetRef> get images sync* {
    for (final l in layers) {
      if (l is ImageLayer) yield l.image;
    }
  }

  Color color(SceneColor c) => c.isToken
      ? (tokens[c.value] ?? const Color(0xFFFF00FF))
      : Color(HexColor(c.value).argb);

  /// Whether [c] should be painted with [accentGradient].
  bool isGradientAccent(SceneColor c) =>
      accentGradient != null && c.value == '@accent';
}
