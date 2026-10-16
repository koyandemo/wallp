import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../catalog/catalog.dart';
import '../look/accent_paint.dart';
import '../scenes/scene_math.dart';
import '../scenes/scene_painter.dart';
import 'layered_scene.dart';

/// Draws a dashboard-made scene (`engine: "layers"`, docs/theme-api.md
/// §4.9), back to front, in the same 390 × 844 design space as the built-in
/// painters, so previews, the live wallpaper and wallpaper images all work
/// the same way.
///
/// Image layers whose picture isn't loaded (yet, or at all) are skipped:
/// the rest of the scene still draws.
class LayersPainter extends ScenePainter {
  LayersPainter({
    required super.time,
    required super.accent,
    required this.scene,
    this.images = const {},
  });

  final LayeredScene scene;

  /// Decoded pictures by sha256.
  final Map<String, ui.Image> images;

  static const _w = 390.0, _h = 844.0;

  @override
  void paintScene(Canvas canvas, double t) {
    for (final (i, layer) in scene.layers.indexed) {
      switch (layer) {
        case GradientLayer():
          _gradient(canvas, layer);
        case ShapeLayer():
          _shape(canvas, layer, t);
        case ImageLayer():
          _image(canvas, layer);
        case ParticlesLayer():
          _particles(canvas, layer, t, i);
      }
    }
  }

  Color _c(SceneColor c, double opacity) {
    final color = scene.color(c);
    return color.withValues(alpha: color.a * opacity);
  }

  void _gradient(Canvas canvas, GradientLayer layer) {
    final rect = const Offset(0, 0) & const Size(_w, _h);
    final shader = cssLinearGradient(layer.angle, [
      for (final c in layer.colors) _c(c, layer.opacity),
    ]).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  void _shape(Canvas canvas, ShapeLayer s, double t) {
    final w = s.width * _w;
    final h = s.shape == ShapeKind.circle ? w : w * s.aspect;
    var center = Offset(s.x * _w, s.y * _h);
    var scale = 1.0, angle = 0.0;
    switch (s.motion) {
      case ShapeMotion.none:
        break;
      case ShapeMotion.float:
        center += Offset(0, math.sin(t * 0.8) * 6);
      case ShapeMotion.pulse:
        scale = 1 + 0.04 * math.sin(t * 1.6);
      case ShapeMotion.sway:
        angle = math.sin(t * 1.2) * 0.07;
    }
    final box = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final path = switch (s.shape) {
      ShapeKind.circle || ShapeKind.ellipse => Path()..addOval(box),
      ShapeKind.rect =>
        Path()..addRRect(
          RRect.fromRectAndRadius(box, Radius.circular(math.min(w, h) * 0.08)),
        ),
      ShapeKind.polygon =>
        Path()..addPolygon([
          for (final p in s.points)
            Offset(box.left + p.x * w, box.top + p.y * h),
        ], true),
    };

    canvas
      ..save()
      // Sway swings from the top, like a hanging lantern.
      ..translate(center.dx, center.dy - (angle == 0 ? 0 : h / 2))
      ..rotate(angle)
      ..translate(0, angle == 0 ? 0 : h / 2)
      ..scale(scale);
    if (s.glow) {
      canvas.drawPath(
        path,
        Paint()
          ..color = _c(s.color, s.opacity * 0.55)
          ..maskFilter = ui.MaskFilter.blur(
            ui.BlurStyle.normal,
            math.max(w, h) * 0.12,
          ),
      );
    }
    final paint = Paint()..color = _c(s.color, s.opacity);
    if (scene.isGradientAccent(s.color)) {
      paint.shader = scene.accentGradient!.createShader(box);
    }
    canvas
      ..drawPath(path, paint)
      ..restore();
  }

  void _image(Canvas canvas, ImageLayer layer) {
    final image = images[layer.image.sha256];
    if (image == null) return;
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    final scale = switch (layer.fit) {
      ImageFit.width => _w / iw,
      ImageFit.cover => math.max(_w / iw, _h / ih),
      ImageFit.contain => math.min(_w / iw, _h / ih),
    };
    final dw = iw * scale, dh = ih * scale;
    final top = switch (layer.anchor) {
      ImageAnchor.top => 0.0,
      ImageAnchor.center => (_h - dh) / 2,
      ImageAnchor.bottom => _h - dh,
    };
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, iw, ih),
      Rect.fromLTWH((_w - dw) / 2, top, dw, dh),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, layer.opacity),
    );
  }

  /// A fixed pseudo-random number in 0..1 for particle [i], property [k]:
  /// the same every frame, so particles move instead of jumping.
  static double _rand(int layer, int i, int k) {
    var x = (layer * 73856093) ^ (i * 19349663) ^ (k * 83492791);
    x = (x ^ (x >> 13)) * 1274126177;
    return ((x ^ (x >> 16)) & 0xFFFF) / 0xFFFF;
  }

  void _particles(Canvas canvas, ParticlesLayer p, double t, int layerIndex) {
    // Speed 0 = a still decoration (stars that don't drift).
    final time = p.speed == 0 ? kSceneStillTime : t;
    final pace = 0.3 + p.speed;
    final paint = Paint()..color = _c(p.color, p.opacity);
    for (var i = 0; i < p.count; i++) {
      double r(int k) => _rand(layerIndex, i, k);
      final size = (0.4 + r(3) * 0.6) * p.size;
      switch (p.effect) {
        case ParticleEffect.snow:
          final y = ((r(1) + time * 0.03 * pace) % 1.1 - 0.05) * _h;
          final x = r(0) * _w + math.sin(time * 0.9 + r(2) * 6) * 8;
          canvas.drawCircle(Offset(x, y), 1.2 + size * 3.5, paint);
        case ParticleEffect.rain:
          final y = ((r(1) + time * 0.25 * pace) % 1.1 - 0.05) * _h;
          final x = r(0) * _w;
          canvas.drawLine(
            Offset(x, y),
            Offset(x - 2, y + 8 + size * 14),
            Paint()
              ..color = paint.color
              ..strokeWidth = 1.2
              ..strokeCap = StrokeCap.round,
          );
        case ParticleEffect.drops:
          final y = ((r(1) + time * 0.12 * pace) % 1.1 - 0.05) * _h;
          final x = r(0) * _w;
          final d = 2 + size * 4;
          canvas.drawOval(
            Rect.fromCenter(center: Offset(x, y), width: d, height: d * 1.5),
            paint,
          );
        case ParticleEffect.bats:
          final x = ((r(0) + time * 0.03 * pace) % 1.2 - 0.1) * _w;
          final y =
              (0.08 + r(1) * 0.35) * _h + math.sin(time * 2 + r(2) * 6) * 10;
          _bat(
            canvas,
            Offset(x, y),
            6 + size * 10,
            math.sin(time * 9 + r(2) * 6),
            paint,
          );
        case ParticleEffect.lanterns:
          final y = (1.05 - (r(1) + time * 0.015 * pace) % 1.1) * _h;
          final x = r(0) * _w + math.sin(time * 0.6 + r(2) * 6) * 6;
          final s = 5 + size * 9;
          canvas
            ..drawCircle(
              Offset(x, y),
              s * 1.6,
              Paint()
                ..color = paint.color.withValues(alpha: paint.color.a * 0.3)
                ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
            )
            ..drawOval(
              Rect.fromCenter(center: Offset(x, y), width: s, height: s * 1.3),
              paint,
            );
        case ParticleEffect.petals:
          final y = ((r(1) + time * 0.04 * pace) % 1.1 - 0.05) * _h;
          final x = r(0) * _w + math.sin(time * 1.1 + r(2) * 6) * 14;
          final s = 3 + size * 6;
          canvas
            ..save()
            ..translate(x, y)
            ..rotate(time * (0.5 + r(4)) + r(2) * 6)
            ..drawOval(
              Rect.fromCenter(center: Offset.zero, width: s * 1.6, height: s),
              paint,
            )
            ..restore();
        case ParticleEffect.sparkles || ParticleEffect.stars:
          final twinkle =
              0.25 + 0.75 * pingPong(phase(time, 1.8 + r(4) * 2.5, r(2) * 3));
          final c = Offset(r(0) * _w, r(1) * _h * 0.7);
          final glint = Paint()
            ..color = paint.color.withValues(alpha: paint.color.a * twinkle);
          if (p.effect == ParticleEffect.stars) {
            canvas.drawCircle(c, 0.8 + size * 1.6, glint);
          } else {
            final s = 2 + size * 6;
            canvas.drawPath(
              Path()
                ..moveTo(c.dx, c.dy - s)
                ..quadraticBezierTo(c.dx, c.dy, c.dx + s, c.dy)
                ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + s)
                ..quadraticBezierTo(c.dx, c.dy, c.dx - s, c.dy)
                ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - s)
                ..close(),
              glint,
            );
          }
      }
    }
  }

  /// A small bat: a body and two wings that flap with [flap] (-1..1).
  void _bat(Canvas canvas, Offset c, double s, double flap, Paint paint) {
    final lift = flap * s * 0.45;
    final wing = Path()
      ..moveTo(c.dx, c.dy)
      ..quadraticBezierTo(
        c.dx - s * 0.5,
        c.dy - s * 0.3 - lift,
        c.dx - s,
        c.dy - lift,
      )
      ..quadraticBezierTo(
        c.dx - s * 0.6,
        c.dy + s * 0.1,
        c.dx - s * 0.35,
        c.dy + s * 0.25,
      )
      ..quadraticBezierTo(
        c.dx - s * 0.15,
        c.dy + s * 0.05,
        c.dx,
        c.dy + s * 0.2,
      )
      ..quadraticBezierTo(
        c.dx + s * 0.15,
        c.dy + s * 0.05,
        c.dx + s * 0.35,
        c.dy + s * 0.25,
      )
      ..quadraticBezierTo(c.dx + s * 0.6, c.dy + s * 0.1, c.dx + s, c.dy - lift)
      ..quadraticBezierTo(c.dx + s * 0.5, c.dy - s * 0.3 - lift, c.dx, c.dy)
      ..close();
    canvas.drawPath(wing, paint);
  }

  @override
  bool shouldRepaint(covariant ScenePainter oldDelegate) =>
      super.shouldRepaint(oldDelegate) ||
      oldDelegate is! LayersPainter ||
      oldDelegate.scene != scene ||
      oldDelegate.images != images;
}
