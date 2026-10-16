import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

import 'scene_math.dart';
import 'scene_painter.dart';

/// Thingyan (Myanmar water festival) lock screen: swaying padauk branches,
/// falling petals, a silver bowl splashing water, and rolling waves.
/// Ported from the design canvas's Thingyan-Lock.dc.html SVG, same coordinates.
class ThingyanPainter extends ScenePainter {
  ThingyanPainter({required super.time, required super.accent});

  static const _bg = Color(0xFF0A3D6B);
  static const _bark = Color(0xFF6B4423);
  static const _leaf = Color(0xFF2E8B57);
  static const _padauk = Color(0xFFFFC20E);
  static const _padaukDeep = Color(0xFFFFB000);
  static const _padaukLight = Color(0xFFFFD95A);
  static const _padaukHeart = Color(0xFFC77700);
  static const _waterLight = Color(0xFFA9DCF7);
  static const _waterMid = Color(0xFF7CC6F0);
  static const _bowl = Color(0xFFB8C6D2);
  static const _bowlShine = Color(0xFFE6EDF2);
  static const _bowlRim = Color(0xFFDDE5EC);
  static const _bowlWater = Color(0xFF5FB4E8);
  static const _foam = Color(0xFFFFF8E7);

  static final _branches = Path()
    // Left branch
    ..moveTo(-10, 30)
    ..quadraticBezierTo(60, 10, 130, 40)
    ..moveTo(40, 22)
    ..quadraticBezierTo(50, 60, 30, 110)
    ..moveTo(90, 28)
    ..quadraticBezierTo(110, 60, 104, 92)
    // Right branch
    ..moveTo(400, 60)
    ..quadraticBezierTo(330, 30, 262, 50)
    ..moveTo(350, 44)
    ..quadraticBezierTo(340, 80, 360, 130)
    ..moveTo(300, 46)
    ..quadraticBezierTo(286, 76, 292, 104);

  /// Padauk clusters as (x, y, sway delay).
  static const _clusters = <(double, double, double)>[
    (30, 40, 0),
    (70, 22, -0.8),
    (118, 44, -1.6),
    (34, 96, -2.2),
    (104, 92, -1.1),
    (12, 66, -2.8),
    (362, 56, -0.4),
    (318, 40, -1.9),
    (272, 52, -0.9),
    (356, 118, -2.5),
    (292, 100, -1.3),
    (380, 88, -3),
  ];

  /// One cluster's blossoms as (x, y, radius, color), relative to its center.
  static const _blossoms = <(double, double, double, Color)>[
    (0, 0, 6, _padauk),
    (10, 4, 5, _padauk),
    (-8, 6, 5, _padaukDeep),
    (4, 12, 5, _padauk),
    (-3, -9, 4, _padaukDeep),
    (12, -6, 4, _padauk),
    (-12, -2, 3.5, _padaukLight),
    (0, 0, 1.8, _padaukHeart),
    (10, 4, 1.5, _padaukHeart),
    (4, 12, 1.5, _padaukHeart),
  ];

  /// Clusters sway from the top-middle of their outline.
  static const _swayPivot = Offset(-2.5, -13);

  /// Falling petals as (x, y, radius, color, delay, period).
  static const _petals = <(double, double, double, Color, double, double)>[
    (40, 110, 3.5, _padauk, 0, 9),
    (110, 96, 3, _padaukLight, -3, 11),
    (20, 70, 3, _padaukDeep, -6, 10),
    (300, 104, 3.5, _padauk, -1.5, 12),
    (350, 124, 3, _padaukLight, -5, 9),
    (270, 60, 3, _padaukDeep, -7.5, 10),
  ];

  static final _drop = Path()
    ..moveTo(0, -12)
    ..cubicTo(5, -4, 7, 0, 7, 3)
    ..arcToPoint(const Offset(-7, 3), radius: const Radius.circular(7))
    ..cubicTo(-7, 0, -5, -4, 0, -12)
    ..close();

  /// Splash drops as (x, y, color, delay, period).
  static const _drops = <(double, double, Color, double, double)>[
    (340, 478, _waterLight, 0, 1.8),
    (320, 496, _waterLight, -0.6, 1.8),
    (354, 504, _waterMid, -1.2, 1.8),
    (300, 466, _waterMid, -0.3, 1.8),
    (70, 500, _waterLight, -0.9, 2.2),
    (46, 540, _waterMid, -1.5, 2.2),
    (96, 460, _waterMid, 0, 2.2),
  ];
  static const _splashMoveStops = [0.0, 0.6, 1.0];
  static const _splashX = <double>[0, 10, 18];
  static const _splashY = <double>[0, -22, 30];
  static const _splashFadeStops = [0.0, 0.2, 0.6, 1.0];
  static const _splashFade = <double>[0, 1, 1, 0];

  static final _arcBig = Path()
    ..moveTo(226, 548)
    ..quadraticBezierTo(262, 440, 336, 470);
  static final _arcSmall = Path()
    ..moveTo(214, 548)
    ..quadraticBezierTo(240, 470, 300, 452);

  static final _bowlBody = Path()
    ..moveTo(125, 560)
    ..quadraticBezierTo(125, 626, 195, 630)
    ..quadraticBezierTo(265, 626, 265, 560)
    ..close();
  static final _bowlBand = Path()
    ..moveTo(140, 590)
    ..quadraticBezierTo(195, 604, 250, 590);

  static final _wave1 = _wave(640, 20);
  static final _wave2 = _wave(690, 22);
  static final _wave3 = _wave(750, 20);

  static final _foam1 = Path()
    ..moveTo(70, 640)
    ..quadraticBezierTo(80, 626, 92, 632)
    ..moveTo(265, 640)
    ..quadraticBezierTo(275, 626, 287, 632)
    ..moveTo(460, 640)
    ..quadraticBezierTo(470, 626, 482, 632);
  static final _foam2 = Path()
    ..moveTo(55, 690)
    ..quadraticBezierTo(67, 676, 81, 682)
    ..moveTo(250, 690)
    ..quadraticBezierTo(262, 676, 276, 682)
    ..moveTo(445, 690)
    ..quadraticBezierTo(457, 676, 471, 682);

  /// A 585-wide wave strip (1.5 screens) so it can scroll by 195 and loop.
  /// Same curve as the SVG's `Q48 y-dy 97 y T195 y T292 y ...`.
  static Path _wave(double y, double dy) {
    const xs = <double>[0, 97, 195, 292, 390, 487, 585];
    final path = Path()..moveTo(0, y);
    var control = Offset(48, y - dy);
    for (var i = 1; i < xs.length; i++) {
      path.quadraticBezierTo(control.dx, control.dy, xs[i], y);
      control = Offset(2 * xs[i] - control.dx, 2 * y - control.dy);
    }
    return path
      ..lineTo(585, 844)
      ..lineTo(0, 844)
      ..close();
  }

  @override
  void paintScene(Canvas canvas, double t) {
    canvas.drawRect(Offset.zero & kSceneSize, Paint()..color = _bg);
    canvas.drawPath(
      _branches,
      Paint()
        ..color = _bark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    _paintClusters(canvas, t);
    _paintPetals(canvas, t);
    _paintGlow(canvas, t);
    _paintWaterArcs(canvas, t);
    _paintDrops(canvas, t);
    _paintBowl(canvas, t);
    _paintWaves(canvas, t);
  }

  void _paintClusters(Canvas canvas, double t) {
    final leaf = Paint()..color = _leaf;
    final blossom = Paint();
    for (final (x, y, delay) in _clusters) {
      final angle = lerp(-7, 7, pingPong(phase(t, 3.4, delay)));
      canvas
        ..save()
        ..translate(x + _swayPivot.dx, y + _swayPivot.dy)
        ..rotate(angle * math.pi / 180)
        ..translate(-_swayPivot.dx, -_swayPivot.dy);
      canvas
        ..save()
        ..rotate(-30 * math.pi / 180)
        ..drawOval(
          Rect.fromCenter(center: const Offset(-10, -10), width: 18, height: 8),
          leaf,
        )
        ..restore();
      for (final (bx, by, r, color) in _blossoms) {
        blossom.color = color;
        canvas.drawCircle(Offset(bx, by), r, blossom);
      }
      canvas.restore();
    }
  }

  void _paintPetals(Canvas canvas, double t) {
    final paint = Paint();
    for (final (x, y, r, color, delay, period) in _petals) {
      final p = phase(t, period, delay);
      final opacity = keyframes(p, const [0, 0.1, 1], const [0, 1, 0]);
      paint.color = color.withValues(alpha: opacity);
      canvas.drawCircle(Offset(x + 40 * p, y + 560 * p), r, paint);
    }
  }

  void _paintGlow(Canvas canvas, double t) {
    final p = pingPong(phase(t, 4));
    canvas.drawCircle(
      const Offset(195, 545),
      130 * lerp(1, 1.08, p),
      Paint()..color = _padauk.withValues(alpha: lerp(0.06, 0.16, p)),
    );
  }

  void _paintWaterArcs(Canvas canvas, double t) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    drawDashedPath(
      canvas,
      _arcBig,
      stroke
        ..color = _waterLight
        ..strokeWidth = 6,
      dash: 16,
      gap: 8,
      offset: -48 * phase(t, 1),
    );
    drawDashedPath(
      canvas,
      _arcSmall,
      stroke
        ..color = _waterMid.withValues(alpha: 0.8)
        ..strokeWidth = 3,
      dash: 16,
      gap: 8,
      offset: -48 * phase(t, 0.8),
    );
  }

  void _paintDrops(Canvas canvas, double t) {
    final paint = Paint();
    for (final (x, y, color, delay, period) in _drops) {
      final p = phase(t, period, delay);
      final dx = keyframes(
        p,
        _splashMoveStops,
        _splashX,
        curve: Curves.easeInOut,
      );
      final dy = keyframes(
        p,
        _splashMoveStops,
        _splashY,
        curve: Curves.easeInOut,
      );
      final opacity = keyframes(
        p,
        _splashFadeStops,
        _splashFade,
        curve: Curves.easeInOut,
      );
      paint.color = color.withValues(alpha: opacity);
      canvas
        ..save()
        ..translate(x + dx, y + dy)
        ..drawPath(_drop, paint)
        ..restore();
    }
  }

  void _paintBowl(Canvas canvas, double t) {
    final shimmer = lerp(1, 0.6, pingPong(phase(t, 1.6)));
    canvas
      ..drawPath(_bowlBody, Paint()..color = _bowl)
      ..drawPath(
        _bowlBand,
        Paint()
          ..color = _bowlShine
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      )
      ..drawOval(
        Rect.fromCenter(center: const Offset(195, 560), width: 140, height: 24),
        Paint()..color = _bowlRim,
      )
      ..drawOval(
        Rect.fromCenter(center: const Offset(195, 561), width: 120, height: 16),
        Paint()..color = _bowlWater.withValues(alpha: shimmer),
      );
  }

  void _paintWaves(Canvas canvas, double t) {
    final foam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    void layer(
      double period,
      Path wave,
      Color color, [
      Path? crest,
      double? a,
    ]) {
      canvas
        ..save()
        ..translate(-195 * phase(t, period), 0)
        ..drawPath(wave, Paint()..color = color);
      if (crest != null) {
        canvas.drawPath(crest, foam..color = _foam.withValues(alpha: a));
      }
      canvas.restore();
    }

    layer(9, _wave1, const Color(0xFF1477C2), _foam1, 0.7);
    layer(6, _wave2, const Color(0xFF3FA2E3), _foam2, 0.8);
    layer(4, _wave3, _waterLight);
  }
}
