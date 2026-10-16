import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/phone_theme.dart';

/// An app icon in a festival's style, drawn as an Android adaptive icon: a
/// 108×108 square whose launcher-masked middle (18..90) holds everything
/// important.
///
/// Glowing tile + festival decorations + accent ring, and either a themed
/// [glyph] or the app's own [appIcon] recolored in the accent.
///
/// * Halloween: purple tile, cobweb, crescent moon.
/// * Christmas: pine-green tile, snow along the top, red ornament, flakes.
/// * Thingyan: water-blue tile, padauk blossoms, a wave along the bottom.
class ThemedIconPainter extends CustomPainter {
  ThemedIconPainter({
    required this.style,
    required this.accent,
    this.glyph,
    this.appIcon,
  });

  final SceneKind style;
  final Color accent;
  final IconData? glyph;
  final ui.Image? appIcon;

  static const _unit = 108.0;
  static const _center = Offset(54, 54);

  /// (tile center glow, tile edge, glyph fallback color) per festival.
  static const _tiles = <SceneKind, (Color, Color, Color)>{
    SceneKind.halloween: (
      Color(0xFF3A2156),
      Color(0xFF160C24),
      Color(0xFFF4E9C9),
    ),
    SceneKind.christmas: (
      Color(0xFF1F6B4C),
      Color(0xFF0A2A20),
      Color(0xFFFFF6E5),
    ),
    // Glow a little darker than the scene's water so the yellow accent
    // keeps 3:1 contrast as a glyph.
    SceneKind.thingyan: (
      Color(0xFF0F5FA3),
      Color(0xFF0A3D6B),
      Color(0xFFFFF8E7),
    ),
  };

  /// The glyph uses the accent when it reads on the tile (3:1), otherwise
  /// the festival's light text color (e.g. Christmas red on green).
  Color get glyphColor {
    final (glow, _, light) = _tiles[style]!;
    return contrastRatio(accent, glow) >= 3 ? accent : light;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / _unit, size.height / _unit);

    final (glow, edge, _) = _tiles[style]!;
    const full = Rect.fromLTWH(0, 0, _unit, _unit);
    canvas.drawRect(
      full,
      Paint()
        ..shader = RadialGradient(
          colors: [glow, edge],
          radius: 0.6,
        ).createShader(full),
    );

    switch (style) {
      case SceneKind.halloween:
        _cobweb(canvas);
        _crescentMoon(canvas);
      case SceneKind.christmas:
        _snowCap(canvas);
        _ornament(canvas);
        _snowflakes(canvas);
      case SceneKind.thingyan:
        _wave(canvas);
        _padauk(canvas);
    }

    canvas.drawCircle(
      _center,
      25,
      Paint()
        ..color = accent.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    if (glyph != null) {
      _paintGlyph(canvas, glyph!);
    } else if (appIcon != null) {
      _paintTintedIcon(canvas, appIcon!);
    }
    canvas.restore();
  }

  // ---- Halloween ----

  static const _cream = Color(0xFFF4E9C9);

  void _cobweb(Canvas canvas) {
    final web = Paint()
      ..color = _cream.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    const origin = Offset(20, 20);
    for (final angle in [0.0, 0.4, 0.8, 1.2, 1.57]) {
      canvas.drawLine(
        origin,
        origin + Offset(math.cos(angle), math.sin(angle)) * 18,
        web,
      );
    }
    for (final r in [6.0, 11.0, 16.0]) {
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: r),
        0,
        math.pi / 2,
        false,
        web,
      );
    }
  }

  void _crescentMoon(Canvas canvas) {
    const moon = Offset(76, 32);
    canvas
      ..saveLayer(Rect.fromCircle(center: moon, radius: 7), Paint())
      ..drawCircle(moon, 6, Paint()..color = _cream)
      ..drawCircle(
        moon + const Offset(3, -2),
        5,
        Paint()..blendMode = BlendMode.clear,
      )
      ..restore();
  }

  // ---- Christmas ----

  void _snowCap(Canvas canvas) {
    final snow = Path()
      ..moveTo(10, 0)
      ..lineTo(98, 0)
      ..lineTo(98, 24)
      ..quadraticBezierTo(86, 31, 74, 25)
      ..quadraticBezierTo(62, 31, 50, 25)
      ..quadraticBezierTo(38, 31, 26, 25)
      ..quadraticBezierTo(18, 30, 10, 25)
      ..close();
    canvas.drawPath(snow, Paint()..color = const Color(0xFFEEF3F0));
  }

  void _ornament(Canvas canvas) {
    const gold = Color(0xFFE8B04B);
    canvas
      ..drawLine(
        const Offset(78, 26),
        const Offset(78, 31),
        Paint()
          ..color = gold
          ..strokeWidth = 1,
      )
      ..drawRect(const Rect.fromLTWH(76, 30, 4, 3), Paint()..color = gold)
      ..drawCircle(
        const Offset(78, 38),
        5.5,
        Paint()..color = const Color(0xFFD7263D),
      )
      ..drawCircle(
        const Offset(76.2, 36.2),
        1.4,
        Paint()..color = Colors.white.withValues(alpha: 0.6),
      );
  }

  void _snowflakes(Canvas canvas) {
    final flake = Paint()..color = Colors.white.withValues(alpha: 0.75);
    for (final (x, y, r) in const [
      (26.0, 38.0, 1.4),
      (32.0, 78.0, 1.1),
      (82.0, 72.0, 1.3),
      (74.0, 84.0, 0.9),
      (22.0, 60.0, 0.9),
    ]) {
      canvas.drawCircle(Offset(x, y), r, flake);
    }
  }

  // ---- Thingyan ----

  void _wave(Canvas canvas) {
    final back = Path()
      ..moveTo(0, 82)
      ..quadraticBezierTo(18, 76, 36, 82)
      ..quadraticBezierTo(54, 88, 72, 82)
      ..quadraticBezierTo(90, 76, 108, 82)
      ..lineTo(108, 108)
      ..lineTo(0, 108)
      ..close();
    final front = back.shift(const Offset(-12, 6));
    canvas
      ..drawPath(back, Paint()..color = const Color(0xFF3FA2E3))
      ..drawPath(front, Paint()..color = const Color(0xFFA9DCF7));
  }

  void _padauk(Canvas canvas) {
    const yellow = Color(0xFFFFC20E);
    const deep = Color(0xFFFFB000);
    canvas
      ..drawOval(
        Rect.fromCenter(center: const Offset(70, 26), width: 9, height: 4),
        Paint()..color = const Color(0xFF2E8B57),
      )
      ..drawCircle(const Offset(76, 30), 3.2, Paint()..color = yellow)
      ..drawCircle(const Offset(81, 33), 2.6, Paint()..color = yellow)
      ..drawCircle(const Offset(73, 35), 2.6, Paint()..color = deep)
      ..drawCircle(const Offset(79, 38), 2.6, Paint()..color = yellow)
      ..drawCircle(
        const Offset(76, 30),
        1,
        Paint()..color = const Color(0xFFC77700),
      );
    // A falling water drop on the left.
    final drop = Path()
      ..moveTo(28, 26)
      ..cubicTo(31, 31, 32, 33, 32, 35)
      ..arcToPoint(const Offset(24, 35), radius: const Radius.circular(4))
      ..cubicTo(24, 33, 25, 31, 28, 26)
      ..close();
    canvas.drawPath(drop, Paint()..color = const Color(0xFFDDF1FC));
  }

  // ---- Glyph / app icon ----

  void _paintGlyph(Canvas canvas, IconData icon) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 30,
          color: glyphColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      _center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  /// The app's own icon recolored to shades of the glyph color, in a circle.
  void _paintTintedIcon(Canvas canvas, ui.Image image) {
    final dest = Rect.fromCircle(center: _center, radius: 17);
    final tint = glyphColor;
    final r = tint.r * 1.3;
    final g = tint.g * 1.3;
    final b = tint.b * 1.3;
    // Each output channel = tint channel × source luminance.
    final filter = ColorFilter.matrix([
      r * 0.2126, r * 0.7152, r * 0.0722, 0, 0, //
      g * 0.2126, g * 0.7152, g * 0.0722, 0, 0, //
      b * 0.2126, b * 0.7152, b * 0.0722, 0, 0, //
      0, 0, 0, 1, 0, //
    ]);
    canvas
      ..save()
      ..clipPath(Path()..addOval(dest))
      ..drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        dest,
        Paint()
          ..colorFilter = filter
          ..filterQuality = FilterQuality.medium,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(ThemedIconPainter old) =>
      old.style != style ||
      old.accent != accent ||
      old.glyph != glyph ||
      old.appIcon != appIcon;
}

/// WCAG contrast ratio between two colors (1..21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// On-screen preview of a themed icon, rounded like a launcher would mask it.
class ThemedIcon extends StatelessWidget {
  const ThemedIcon({
    super.key,
    required this.style,
    required this.accent,
    this.glyph,
    this.appIcon,
    this.size = 56,
  });

  final SceneKind style;
  final Color accent;
  final IconData? glyph;
  final ui.Image? appIcon;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Show the launcher-visible middle two-thirds of the adaptive square.
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: SizedBox.square(
        dimension: size,
        child: OverflowBox(
          maxWidth: size * 1.5,
          maxHeight: size * 1.5,
          child: CustomPaint(
            size: Size.square(size * 1.5),
            painter: ThemedIconPainter(
              style: style,
              accent: accent,
              glyph: glyph,
              appIcon: appIcon,
            ),
          ),
        ),
      ),
    );
  }
}
