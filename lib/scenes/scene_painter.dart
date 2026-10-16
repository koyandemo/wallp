import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// Design size of every wallpaper scene (matches the design canvas).
const kSceneSize = Size(390, 844);

/// Animation time (s) of the frame used for still previews and wallpaper
/// images: bats mid-flight, star glowing, etc.
const kSceneStillTime = 1.2;

/// Base for the painted wallpapers. Subclasses draw in [kSceneSize]
/// coordinates; this scales them to cover whatever size they're given
/// (a grid card, the full screen, or a wallpaper bitmap in Step 6).
abstract class ScenePainter extends CustomPainter {
  ScenePainter({required this.time, required this.accent})
    : super(repaint: time);

  /// Seconds since the animation started.
  final ValueListenable<double> time;
  final Color accent;

  void paintScene(Canvas canvas, double t);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.max(
      size.width / kSceneSize.width,
      size.height / kSceneSize.height,
    );
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..translate(
        (size.width - kSceneSize.width * scale) / 2,
        (size.height - kSceneSize.height * scale) / 2,
      )
      ..scale(scale);
    paintScene(canvas, time.value);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ScenePainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.accent != accent;
}

/// Strokes [path] as dashes, like SVG `stroke-dasharray: dash gap`.
/// The pattern restarts on each subpath (as SVG does); a negative [offset]
/// moves the dashes forward along the path, like `stroke-dashoffset`.
void drawDashedPath(
  Canvas canvas,
  Path path,
  Paint paint, {
  required double dash,
  required double gap,
  double offset = 0,
}) {
  final period = dash + gap;
  final first = (-offset) % period - period;
  for (final metric in path.computeMetrics()) {
    for (var s = first; s < metric.length; s += period) {
      final start = math.max(s, 0.0);
      final end = math.min(s + dash, metric.length);
      if (end > start) {
        canvas.drawPath(metric.extractPath(start, end), paint);
      }
    }
  }
}
