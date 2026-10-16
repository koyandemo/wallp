import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

import 'scene_math.dart';
import 'scene_painter.dart';

/// Halloween lock screen: moon, bats, ghost, graveyard and a jack-o'-lantern.
/// Ported from the design canvas's Main.dc.html SVG, same coordinates.
class HalloweenPainter extends ScenePainter {
  HalloweenPainter({required super.time, required super.accent});

  static const _bg = Color(0xFF160C24);
  static const _cream = Color(0xFFF4E9C9);
  static const _crater = Color(0xFFE3D3A6);
  static const _ink = Color(0xFF0D0717);
  static const _hill = Color(0xFF241536);
  static const _stone = Color(0xFF2C1E40);
  static const _pumpkin = Color(0xFFFF7A1A);
  static const _pumpkinDark = Color(0xFFD9590C);
  static const _stem = Color(0xFF4C7A2E);
  static const _candle = Color(0xFFFFD27A);

  /// (x, y, radius, twinkle delay in s)
  static const _stars = <(double, double, double, double)>[
    (40, 60, 1.6, 0),
    (120, 30, 1.2, 1.2),
    (350, 50, 1.8, 0.6),
    (300, 140, 1.2, 2),
    (30, 250, 1.4, 0.3),
    (80, 400, 1.2, 1.6),
    (150, 370, 1.8, 2.4),
    (365, 300, 1.3, 0.9),
    (60, 520, 1.5, 1.8),
  ];

  /// (x, y, scale, flight period, flight delay, flap period)
  static const _bats = <(double, double, double, double, double, double)>[
    (215, 400, 1.1, 7, 0, 0.32),
    (340, 380, 0.8, 9, -3, 0.28),
    (150, 470, 0.65, 6, -1.5, 0.38),
  ];
  static const _flightStops = [0.0, 0.25, 0.5, 0.75, 1.0];
  static const _flightX = <double>[0, -16, -30, -12, 0];
  static const _flightY = <double>[0, -12, 4, 12, 0];

  /// Vertical middle of the bat path; wings flap around it.
  static const _batCenterY = -1.0;

  static final _batPath = Path()
    ..moveTo(0, 0)
    ..cubicTo(-6, -8, -14, -8, -20, -2)
    ..cubicTo(-16, -2, -14, 2, -14, 4)
    ..cubicTo(-11, 1, -7, 2, -6, 5)
    ..cubicTo(-4, 2, -2, 2, 0, 4)
    ..cubicTo(2, 2, 4, 2, 6, 5)
    ..cubicTo(7, 2, 11, 1, 14, 4)
    ..cubicTo(14, 2, 16, -2, 20, -2)
    ..cubicTo(14, -8, 6, -8, 0, 0)
    ..close()
    ..moveTo(-3, -2)
    ..lineTo(-2, -6)
    ..lineTo(0, -3)
    ..lineTo(2, -6)
    ..lineTo(3, -2)
    ..close();

  static final _backHill = Path()
    ..moveTo(0, 610)
    ..quadraticBezierTo(90, 560, 190, 600)
    ..quadraticBezierTo(290, 640, 390, 580)
    ..lineTo(390, 844)
    ..lineTo(0, 844)
    ..close();

  static final _frontGround = Path()
    ..moveTo(0, 690)
    ..quadraticBezierTo(120, 640, 230, 680)
    ..quadraticBezierTo(340, 720, 390, 670)
    ..lineTo(390, 844)
    ..lineTo(0, 844)
    ..close();

  /// Bare tree branches as (x1, y1, x2, y2).
  static const _branches = <(double, double, double, double)>[
    (60, 600, 64, 520),
    (64, 545, 40, 508),
    (63, 528, 88, 494),
    (46, 516, 30, 506),
    (84, 498, 98, 482),
    (64, 520, 70, 500),
  ];

  static final _ghostPath = Path()
    ..moveTo(0, 0)
    ..arcToPoint(const Offset(28, 0), radius: const Radius.circular(14))
    ..lineTo(28, 24)
    ..relativeLineTo(-4.7, -5)
    ..relativeLineTo(-4.6, 5)
    ..relativeLineTo(-4.7, -5)
    ..relativeLineTo(-4.6, 5)
    ..relativeLineTo(-4.7, -5)
    ..relativeLineTo(-4.7, 5)
    ..close();

  /// Tombstones as (left x, bottom y, straight height, top radius).
  static const _tombstones = <(double, double, double, double)>[
    (298, 694, 30, 16),
    (342, 690, 20, 11),
    (30, 712, 18, 10),
  ];

  static final _stemPath = Path()
    ..moveTo(-4, -44)
    ..relativeQuadraticBezierTo(2, -14, 12, -18)
    ..relativeLineTo(3, 5)
    ..relativeQuadraticBezierTo(-8, 4, -8, 15)
    ..close();

  static final _facePath = Path()
    ..moveTo(-28, -8)
    ..lineTo(-18, -22)
    ..lineTo(-8, -8)
    ..close()
    ..moveTo(8, -8)
    ..lineTo(18, -22)
    ..lineTo(28, -8)
    ..close()
    ..moveTo(-5, 4)
    ..lineTo(0, -4)
    ..lineTo(5, 4)
    ..close()
    ..moveTo(-30, 12)
    ..quadraticBezierTo(0, 40, 30, 12)
    ..lineTo(22, 16)
    ..lineTo(16, 10)
    ..lineTo(8, 18)
    ..lineTo(0, 12)
    ..lineTo(-8, 18)
    ..lineTo(-16, 10)
    ..lineTo(-22, 16)
    ..close();
  static const _flickerStops = [0.0, 0.2, 0.24, 0.52, 0.58, 0.8, 1.0];
  static const _flickerValues = [1.0, 0.7, 0.95, 0.6, 1.0, 0.8, 1.0];

  @override
  void paintScene(Canvas canvas, double t) {
    canvas.drawRect(Offset.zero & kSceneSize, Paint()..color = _bg);
    _paintStars(canvas, t);
    _paintMoon(canvas, t);
    _paintBats(canvas, t);
    canvas.drawPath(_backHill, Paint()..color = _hill);
    _paintTree(canvas);
    _paintGhost(canvas, t);
    canvas.drawPath(_frontGround, Paint()..color = _ink);
    _paintTombstones(canvas);
    _paintPumpkin(canvas, t);
  }

  void _paintStars(Canvas canvas, double t) {
    for (final (x, y, r, delay) in _stars) {
      final opacity = lerp(0.85, 0.12, pingPong(phase(t, 3, delay)));
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = _cream.withValues(alpha: opacity),
      );
    }
  }

  /// Soft pulsing halo behind the moon and the pumpkin.
  void _paintGlow(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double t,
    double period,
  ) {
    final p = pingPong(phase(t, period));
    canvas.drawCircle(
      center,
      radius * lerp(1, 1.08, p),
      Paint()..color = color.withValues(alpha: lerp(0.06, 0.2, p)),
    );
  }

  void _paintMoon(Canvas canvas, double t) {
    const center = Offset(285, 470);
    _paintGlow(canvas, center, 112, _cream, t, 4);
    canvas.drawCircle(center, 92, Paint()..color = _cream);
    final crater = Paint()..color = _crater;
    canvas
      ..drawCircle(const Offset(250, 440), 16, crater)
      ..drawCircle(const Offset(310, 500), 22, crater)
      ..drawCircle(const Offset(315, 430), 9, crater);
  }

  void _paintBats(Canvas canvas, double t) {
    final paint = Paint()..color = _ink;
    for (final (x, y, scale, period, delay, flapPeriod) in _bats) {
      final p = phase(t, period, delay);
      final dx = keyframes(p, _flightStops, _flightX, curve: Curves.easeInOut);
      final dy = keyframes(p, _flightStops, _flightY, curve: Curves.easeInOut);
      final flap = lerp(1, 0.5, pingPong(phase(t, flapPeriod)));
      canvas
        ..save()
        ..translate(x + dx, y + dy)
        ..scale(scale)
        ..translate(0, _batCenterY)
        ..scale(1, flap)
        ..translate(0, -_batCenterY)
        ..drawPath(_batPath, paint)
        ..restore();
    }
  }

  void _paintTree(Canvas canvas) {
    final paint = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (final (x1, y1, x2, y2) in _branches) {
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
  }

  void _paintGhost(Canvas canvas, double t) {
    final p = pingPong(phase(t, 4.5));
    final opacity = lerp(0.85, 0.55, p);
    canvas
      ..save()
      ..translate(316, 600 + lerp(0, -14, p))
      // Fade body and eyes together, like the SVG group opacity.
      ..saveLayer(
        const Rect.fromLTWH(-2, -16, 32, 44),
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
      )
      ..drawPath(_ghostPath, Paint()..color = _cream)
      ..drawCircle(const Offset(9, 2), 2.4, Paint()..color = _bg)
      ..drawCircle(const Offset(19, 2), 2.4, Paint()..color = _bg)
      ..restore()
      ..restore();
  }

  void _paintTombstones(Canvas canvas) {
    final paint = Paint()..color = _stone;
    for (final (x, bottom, h, r) in _tombstones) {
      final path = Path()
        ..moveTo(x, bottom)
        ..relativeLineTo(0, -h)
        ..relativeArcToPoint(Offset(r * 2, 0), radius: Radius.circular(r))
        ..relativeLineTo(0, h)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  void _paintPumpkin(Canvas canvas, double t) {
    final flicker = keyframes(phase(t, 2.4), _flickerStops, _flickerValues);
    final dark = Paint()..color = _pumpkinDark;
    canvas
      ..save()
      ..translate(195, 716);
    _paintGlow(canvas, Offset.zero, 82, _pumpkin, t, 2.4);
    canvas
      ..drawOval(
        Rect.fromCenter(center: const Offset(-28, 0), width: 68, height: 84),
        dark,
      )
      ..drawOval(
        Rect.fromCenter(center: const Offset(28, 0), width: 68, height: 84),
        dark,
      )
      ..drawOval(
        Rect.fromCenter(center: Offset.zero, width: 76, height: 92),
        Paint()..color = _pumpkin,
      )
      ..drawPath(_stemPath, Paint()..color = _stem)
      ..drawPath(_facePath, Paint()..color = _candle.withValues(alpha: flicker))
      ..restore();
  }
}
