/// Scene layer pictures for the Spider Night kit (spider_night.dart),
/// drawn by render_art_test.dart. The animated parts (red moon, swinging
/// spider, rain) are `layers` shapes and particles, not pictures.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

ui.Color _c(int rgb, [double alpha = 1]) =>
    ui.Color(0xFF000000 | rgb).withValues(alpha: alpha);

/// Two rows of towers along the bottom: a hazy far row and a black near row
/// with lit windows, a water tower and a red rim light from the moon.
void spiderSkyline(ui.Canvas canvas, ui.Size size) {
  final w = size.width, h = size.height;
  final rnd = math.Random(7);

  // Far row: tall, flat, bluish.
  var x = -20.0;
  final far = ui.Paint()..color = _c(0x1A2450);
  while (x < w) {
    final bw = 70 + rnd.nextDouble() * 90;
    final top = h * (0.12 + rnd.nextDouble() * 0.3);
    canvas.drawRect(ui.Rect.fromLTRB(x, top, x + bw, h), far);
    // A few faint windows.
    for (var wy = top + 24; wy < h - 20; wy += 34) {
      for (var wx = x + 12; wx < x + bw - 16; wx += 22) {
        if (rnd.nextDouble() < 0.18) {
          canvas.drawRect(
            ui.Rect.fromLTWH(wx, wy, 8, 12),
            ui.Paint()..color = _c(0x7CC6FF, 0.25),
          );
        }
      }
    }
    x += bw + 6;
  }

  // Near row: black towers with warm windows.
  final near = ui.Paint()..color = _c(0x05070F);
  final rim = ui.Paint()
    ..color = _c(0xE23636, 0.55)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 4;
  x = -30.0;
  var i = 0;
  while (x < w) {
    final bw = 110 + rnd.nextDouble() * 120;
    final top = h * (0.38 + rnd.nextDouble() * 0.32);
    final body = ui.Rect.fromLTRB(x, top, x + bw, h);
    canvas.drawRect(body, near);
    // Moon light catches the roof edge and the right wall.
    canvas.drawPath(
      ui.Path()
        ..moveTo(x, top)
        ..lineTo(x + bw, top)
        ..lineTo(x + bw, top + 140),
      rim,
    );
    for (var wy = top + 30; wy < h - 30; wy += 46) {
      for (var wx = x + 18; wx < x + bw - 24; wx += 30) {
        final r = rnd.nextDouble();
        if (r < 0.32) {
          canvas.drawRect(
            ui.Rect.fromLTWH(wx, wy, 13, 20),
            ui.Paint()..color = _c(r < 0.08 ? 0xFFF1C2 : 0xFFD27A, 0.85),
          );
        }
      }
    }
    // A rooftop water tower on the second tower, an antenna on the fourth.
    if (i == 1) _waterTower(canvas, x + bw * 0.55, top);
    if (i == 3) {
      canvas.drawRect(
        ui.Rect.fromLTWH(x + bw / 2 - 3, top - 150, 6, 150),
        near,
      );
      canvas.drawCircle(
        ui.Offset(x + bw / 2, top - 152),
        7,
        ui.Paint()..color = _c(0xE23636),
      );
    }
    x += bw + 4;
    i++;
  }
}

void _waterTower(ui.Canvas canvas, double cx, double roof) {
  final ink = ui.Paint()..color = _c(0x05070F);
  final legs = ui.Paint()
    ..color = _c(0x05070F)
    ..strokeWidth = 6;
  const tw = 70.0, th = 80.0, lift = 50.0;
  for (final dx in [-tw * 0.4, tw * 0.4]) {
    canvas.drawLine(
      ui.Offset(cx + dx, roof),
      ui.Offset(cx + dx * 0.8, roof - lift),
      legs,
    );
  }
  canvas
    ..drawRect(ui.Rect.fromLTWH(cx - tw / 2, roof - lift - th, tw, th), ink)
    ..drawPath(
      ui.Path()
        ..moveTo(cx - tw / 2 - 6, roof - lift - th)
        ..lineTo(cx, roof - lift - th - 40)
        ..lineTo(cx + tw / 2 + 6, roof - lift - th)
        ..close(),
      ink,
    );
}

/// A corner web: spokes fan out from just off the top-left corner, joined by
/// threads that sag toward the hub, like a real orb web.
void spiderWeb(ui.Canvas canvas, ui.Size size) {
  final hub = ui.Offset(-30, -30);
  const spokes = 10;
  const reach = 1250.0;
  final angles = [
    for (var i = 0; i < spokes; i++) (math.pi / 2) * (i / (spokes - 1)),
  ];
  ui.Offset at(double angle, double r) =>
      hub + ui.Offset(math.cos(angle) * r, math.sin(angle) * r);

  canvas.drawPath(
    ui.Path()..addPolygon([
      for (final a in angles) ...[hub, at(a, reach)],
    ], false),
    ui.Paint()
      ..color = _c(0xF5F1EA, 0.75)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3,
  );

  final thread = ui.Paint()
    ..color = _c(0xF5F1EA, 0.6)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 2.2;
  // Rings get further apart toward the edge.
  for (var ring = 1; ring <= 11; ring++) {
    final r = 70.0 * ring + 6.0 * ring * ring;
    final path = ui.Path()
      ..moveTo(at(angles.first, r).dx, at(angles.first, r).dy);
    for (var i = 1; i < spokes; i++) {
      final mid = (angles[i - 1] + angles[i]) / 2;
      final sag = at(mid, r * 0.9);
      final end = at(angles[i], r);
      path.quadraticBezierTo(sag.dx, sag.dy, end.dx, end.dy);
    }
    canvas.drawPath(path, thread);
  }
}
