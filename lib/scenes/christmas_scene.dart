import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'scene_math.dart';
import 'scene_painter.dart';

/// Christmas lock screen: falling snow, swinging ornaments, a lit tree with a
/// pulsing star, and presents in the snow.
/// Ported from the design canvas's Christmas-Lock.dc.html SVG, same coordinates.
class ChristmasPainter extends ScenePainter {
  ChristmasPainter({required super.time, required super.accent});

  static const _bg = Color(0xFF0F3D2E);
  static const _gold = Color(0xFFE8B04B);
  static const _red = Color(0xFFD7263D);
  static const _cream = Color(0xFFFFF6E5);
  static const _bulb = Color(0xFFFFE8A8);
  static const _pine = Color(0xFF0A2A20);
  static const _trunk = Color(0xFF5B3A1E);
  static const _snow = Color(0xFFEEF3F0);
  static const _snowShade = Color(0xFFDCE6E1);
  static const _white = Color(0xFFFFFFFF);

  /// Small background flakes as (x, y, radius, opacity).
  static const _flakesBack = <(double, double, double, double)>[
    (24, 180, 2.5, 0.7),
    (70, 240, 1.8, 0.6),
    (360, 200, 2.2, 0.7),
    (200, 40, 1.6, 0.5),
    (250, 120, 2, 0.6),
    (40, 380, 2.6, 0.8),
    (90, 440, 1.8, 0.6),
    (60, 520, 2.2, 0.7),
    (350, 380, 2.4, 0.8),
    (320, 450, 1.6, 0.6),
    (365, 540, 2.2, 0.7),
    (120, 590, 1.8, 0.6),
    (290, 600, 2, 0.7),
    (20, 700, 1.6, 0.5),
    (150, 300, 1.4, 0.5),
    (230, 760, 1.6, 0.5),
  ];

  /// Big foreground flakes, drawn over the ground.
  static const _flakesFront = <(double, double, double, double)>[
    (110, 90, 3.2, 0.85),
    (330, 300, 3, 0.85),
    (30, 470, 3.4, 0.85),
    (270, 520, 3, 0.8),
    (180, 690, 3.2, 0.8),
    (375, 760, 3, 0.8),
  ];

  /// Hanging ornaments as (x, string length, ball radius, color,
  /// swing period, swing delay, has shine).
  static const _ornaments =
      <(double, double, double, Color, double, double, bool)>[
        (34, 70, 16, _red, 3.2, 0, true),
        (80, 40, 12, _gold, 2.8, -1, false),
        (312, 52, 12, _gold, 3, -2, false),
        (358, 88, 16, _red, 3.6, -0.5, true),
      ];

  /// Tree tiers as (apex y, base y, half width, color), back to front.
  static const _tiers = <(double, double, double, Color)>[
    (400, 490, 55, Color(0xFF1F6B4C)),
    (450, 562, 77, Color(0xFF1A5C41)),
    (510, 642, 97, Color(0xFF164F38)),
  ];

  static final _garland = Path()
    ..moveTo(155, 480)
    ..quadraticBezierTo(195, 500, 238, 476)
    ..moveTo(138, 548)
    ..quadraticBezierTo(195, 574, 256, 540)
    ..moveTo(118, 626)
    ..quadraticBezierTo(195, 656, 276, 616);

  /// Tree lights as (x, y, radius, color, blink delay).
  static const _lights = <(double, double, double, Color, double)>[
    (172, 470, 6, _red, 0),
    (220, 462, 5, _cream, 0.4),
    (160, 540, 6, _gold, 0.8),
    (236, 534, 7, _red, 1.2),
    (196, 526, 5, _cream, 0.2),
    (140, 616, 7, _red, 0.6),
    (200, 604, 6, _gold, 1),
    (252, 612, 6, _cream, 1.4),
  ];

  static final _star = Path()
    ..addPolygon(const [
      Offset(195, 374),
      Offset(199.1, 384.3),
      Offset(210.2, 385.1),
      Offset(201.7, 392.2),
      Offset(204.4, 402.9),
      Offset(195, 397),
      Offset(185.6, 402.9),
      Offset(188.3, 392.2),
      Offset(179.8, 385.1),
      Offset(190.9, 384.3),
    ], true);
  static const _starCenter = Offset(195, 388.45);

  static final _pines = Path()
    ..addPolygon(const [
      Offset(20, 690),
      Offset(48, 640),
      Offset(76, 690),
    ], true)
    ..addPolygon(const [
      Offset(28, 660),
      Offset(48, 620),
      Offset(68, 660),
    ], true)
    ..addPolygon(const [
      Offset(314, 680),
      Offset(346, 624),
      Offset(378, 680),
    ], true)
    ..addPolygon(const [
      Offset(322, 648),
      Offset(346, 604),
      Offset(370, 648),
    ], true);

  static final _snowBack = Path()
    ..moveTo(0, 690)
    ..quadraticBezierTo(195, 645, 390, 690)
    ..lineTo(390, 844)
    ..lineTo(0, 844)
    ..close();

  static final _snowFront = Path()
    ..moveTo(0, 740)
    ..quadraticBezierTo(195, 712, 390, 744)
    ..lineTo(390, 844)
    ..lineTo(0, 844)
    ..close();

  @override
  void paintScene(Canvas canvas, double t) {
    canvas.drawRect(Offset.zero & kSceneSize, Paint()..color = _bg);
    _paintSnowfall(canvas, t, _flakesBack, fallPeriod: 22, driftPeriod: 4);
    _paintOrnaments(canvas, t);
    canvas.drawCircle(
      const Offset(195, 530),
      150,
      Paint()..color = _gold.withValues(alpha: 0.06),
    );
    _paintTree(canvas, t);
    _paintStar(canvas, t);
    canvas
      ..drawPath(_pines, Paint()..color = _pine)
      ..drawPath(_snowBack, Paint()..color = _snow)
      ..drawPath(_snowFront, Paint()..color = _snowShade);
    _paintPresents(canvas);
    _paintSnowfall(
      canvas,
      t,
      _flakesFront,
      fallPeriod: 14,
      driftPeriod: 3,
      driftDelay: -1,
    );
  }

  /// Flakes fall one screen-height per [fallPeriod]; a second copy one screen
  /// above keeps the loop seamless. The whole layer sways sideways.
  void _paintSnowfall(
    Canvas canvas,
    double t,
    List<(double, double, double, double)> flakes, {
    required double fallPeriod,
    required double driftPeriod,
    double driftDelay = 0,
  }) {
    final fall = phase(t, fallPeriod) * kSceneSize.height;
    final drift = lerp(0, 10, pingPong(phase(t, driftPeriod, driftDelay)));
    final paint = Paint();
    for (final (x, y, r, opacity) in flakes) {
      paint.color = _white.withValues(alpha: opacity);
      for (final copy in [0.0, -kSceneSize.height]) {
        canvas.drawCircle(Offset(x + drift, y + fall + copy), r, paint);
      }
    }
  }

  void _paintOrnaments(Canvas canvas, double t) {
    final string = Paint()
      ..color = _gold.withValues(alpha: 0.8)
      ..strokeWidth = 1.2;
    final cap = Paint()..color = _gold;
    final shine = Paint()
      ..color = _cream.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (final (x, len, r, color, period, delay, hasShine) in _ornaments) {
      final angle = lerp(-7, 7, pingPong(phase(t, period, delay)));
      final cy = len + 4 + r;
      canvas
        ..save()
        ..translate(x, 0)
        ..rotate(angle * math.pi / 180)
        ..translate(-x, 0)
        ..drawLine(Offset(x, 0), Offset(x, len), string)
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - 5, len - 2, 10, 7),
            const Radius.circular(1.5),
          ),
          cap,
        )
        ..drawCircle(Offset(x, cy), r, Paint()..color = color);
      if (hasShine) {
        canvas.drawPath(
          Path()
            ..moveTo(x - 8, cy - 6)
            ..quadraticBezierTo(x - 4, cy - 12, x + 2, cy - 12),
          shine,
        );
      }
      canvas.restore();
    }
  }

  void _paintTree(Canvas canvas, double t) {
    for (final (apex, base, half, color) in _tiers) {
      canvas.drawPath(
        Path()..addPolygon([
          Offset(195, apex),
          Offset(195 + half, base),
          Offset(195 - half, base),
        ], true),
        Paint()..color = color,
      );
    }
    canvas.drawRect(
      const Rect.fromLTWH(183, 640, 24, 36),
      Paint()..color = _trunk,
    );

    drawDashedPath(
      canvas,
      _garland,
      Paint()
        ..color = _bulb
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
      dash: 4,
      gap: 8,
      offset: -24 * phase(t, 1.2),
    );

    for (final (x, y, r, color, delay) in _lights) {
      final opacity = lerp(1, 0.25, pingPong(phase(t, 1.6, delay)));
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = color.withValues(alpha: opacity),
      );
    }
  }

  void _paintStar(Canvas canvas, double t) {
    final p = pingPong(phase(t, 2.4));
    canvas.drawCircle(
      const Offset(195, 390),
      30 * lerp(1, 1.35, p),
      Paint()..color = _gold.withValues(alpha: lerp(0.15, 0.45, p)),
    );
    final scale = lerp(1, 1.15, p);
    canvas
      ..save()
      ..translate(_starCenter.dx, _starCenter.dy)
      ..scale(scale)
      ..translate(-_starCenter.dx, -_starCenter.dy)
      ..drawPath(_star, Paint()..color = _gold)
      ..restore();
  }

  void _paintPresents(Canvas canvas) {
    final red = Paint()..color = _red;
    final gold = Paint()..color = _gold;
    const corner = Radius.circular(3);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(250, 660, 34, 28), corner),
        red,
      )
      ..drawRect(const Rect.fromLTWH(264, 660, 6, 28), gold)
      ..drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(104, 666, 28, 22), corner),
        gold,
      )
      ..drawRect(const Rect.fromLTWH(115, 666, 6, 22), red);
  }
}
