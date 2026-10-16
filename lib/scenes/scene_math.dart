import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// Progress 0..1 through a repeating animation of [period] seconds.
/// A negative [delay] starts part-way through, like a CSS animation-delay.
double phase(double t, double period, [double delay = 0]) =>
    ((t - delay) / period) % 1.0;

/// 0 → 1 → 0 with ease-in-out: the CSS `0%,100%{a} 50%{b}` keyframe shape.
double pingPong(double p) => 0.5 - 0.5 * math.cos(2 * math.pi * p);

double lerp(double a, double b, double t) => a + (b - a) * t;

/// Interpolates through [values] placed at [stops] (both 0..1, same length).
double keyframes(
  double p,
  List<double> stops,
  List<double> values, {
  Curve curve = Curves.linear,
}) {
  for (var i = 0; i < stops.length - 1; i++) {
    if (p <= stops[i + 1]) {
      final local = (p - stops[i]) / (stops[i + 1] - stops[i]);
      return lerp(values[i], values[i + 1], curve.transform(local.clamp(0, 1)));
    }
  }
  return values.last;
}
