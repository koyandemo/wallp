import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../catalog/catalog.dart';

/// Flutter colours and gradients for a catalog [Accent].
extension AccentPaint on Accent {
  Color get color => Color(primary.argb);

  /// Null for a solid accent.
  LinearGradient? get gradient => type == AccentType.solid
      ? null
      : cssLinearGradient(angle, [for (final c in colors) Color(c.argb)]);

  /// A fill for boxes and circles: the gradient, or the solid colour.
  BoxDecoration decoration({
    BoxShape shape = BoxShape.rectangle,
    BorderRadius? radius,
  }) => BoxDecoration(
    color: gradient == null ? color : null,
    gradient: gradient,
    shape: shape,
    borderRadius: radius,
  );
}

/// A CSS `linear-gradient(<angle>deg, …)` as a Flutter gradient: 0° points
/// up, 90° right, 180° down (the catalog's angles are CSS ones).
LinearGradient cssLinearGradient(int degrees, List<Color> colors) {
  final r = degrees * math.pi / 180;
  // Direction in Flutter's alignment space: x right, y down.
  final dx = math.sin(r), dy = -math.cos(r);
  // Stretch to the box edge, so 135° runs corner to corner.
  final scale = 1 / math.max(dx.abs(), dy.abs());
  final end = Alignment(_clean(dx * scale), _clean(dy * scale));
  return LinearGradient(begin: -end, end: end, colors: colors);
}

/// Rounds away floating point noise (sin 180° is 1.2e-16, not 0).
double _clean(double v) => (v * 1e6).roundToDouble() / 1e6;

/// Text painted with a gradient: the clock in a gradient accent. With no
/// [gradient] it's the plain [child].
class GradientText extends StatelessWidget {
  const GradientText({super.key, required this.child, this.gradient});

  /// Text drawn in an opaque colour; only its shape is used.
  final Widget child;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final g = gradient;
    if (g == null) return child;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: g.createShader,
      child: child,
    );
  }
}
