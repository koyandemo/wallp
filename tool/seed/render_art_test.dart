// Draws the mock catalog's icon pack and scene layer PNGs.
//
//   flutter test tool/seed/render_art_test.dart
//
// Run it only when the art in art.dart changes; the PNGs are committed under
// tool/seed/source/ and generate.dart hashes them into assets/mock/.
// It's a "test" only because flutter test is the easy way to get dart:ui.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:path_drawing/path_drawing.dart';

import 'art.dart';

void main() {
  test('render icon packs', () async {
    for (final pack in packArt) {
      for (final MapEntry(key: glyph, value: path) in glyphPaths.entries) {
        await _save(
          iconPath(pack.id, glyph),
          iconPixels,
          iconPixels,
          (c) => _icon(c, pack, path),
        );
      }
    }
  });

  test('render scene layers', () async {
    for (final art in LayerArt.values) {
      await _save(layerPath(art), art.width, art.height, (c) {
        final size = ui.Size(art.width.toDouble(), art.height.toDouble());
        switch (art) {
          case LayerArt.snowHills:
            _snowHills(c, size);
          case LayerArt.pagoda:
            _pagoda(c, size);
          case LayerArt.lanternGarland:
            _lanternGarland(c, size);
        }
      });
    }
  });
}

ui.Color _c(int rgb, [double alpha = 1]) =>
    ui.Color(0xFF000000 | rgb).withValues(alpha: alpha);

Future<void> _save(
  String path,
  int width,
  int height,
  void Function(ui.Canvas) draw,
) async {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(png!.buffer.asUint8List());
}

ui.Path _tileShape(String shape, ui.Rect r) {
  final w = r.width;
  ui.Radius rad(double f) => ui.Radius.circular(w * f);
  return switch (shape) {
    'circle' => ui.Path()..addOval(r),
    'square' => ui.Path()..addRRect(ui.RRect.fromRectAndRadius(r, rad(0.12))),
    // CSS "50% 50% 50% 12%": round everywhere but the bottom-left corner.
    'leaf' =>
      ui.Path()..addRRect(
        ui.RRect.fromRectAndCorners(
          r,
          topLeft: rad(0.5),
          topRight: rad(0.5),
          bottomRight: rad(0.5),
          bottomLeft: rad(0.12),
        ),
      ),
    _ => ui.Path()..addRRect(ui.RRect.fromRectAndRadius(r, rad(0.3))),
  };
}

void _icon(ui.Canvas canvas, PackArt pack, String glyphPath) {
  const s = iconPixels * 1.0;
  final tile = ui.Rect.fromLTWH(s * 0.06, s * 0.06, s * 0.88, s * 0.88);
  final shape = _tileShape(pack.shape, tile);

  if (pack.look == PackLook.glow) {
    canvas.drawPath(
      shape,
      ui.Paint()
        ..color = _c(pack.ring, 0.55)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = s * 0.06
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 10),
    );
  }
  if (pack.tile case final tileColor?) {
    canvas.drawPath(shape, ui.Paint()..color = _c(tileColor));
  }
  if (pack.look == PackLook.outline || pack.look == PackLook.glow) {
    canvas.drawPath(
      shape,
      ui.Paint()
        ..color = _c(pack.ring)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = s * 0.035,
    );
  }

  // The glyph fills half the tile (70% for line icons, which have no tile).
  final box = pack.look == PackLook.line ? s * 0.7 : s * 0.5;
  final scale = box / 24;
  canvas
    ..save()
    ..translate((s - box) / 2, (s - box) / 2)
    ..scale(scale)
    ..drawPath(
      parseSvgPathData(glyphPath),
      ui.Paint()
        ..color = _c(pack.glyph)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = pack.look == PackLook.line ? 1.6 : 2
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round,
    )
    ..restore();
}

void _snowHills(ui.Canvas canvas, ui.Size size) {
  final w = size.width, h = size.height;
  void hill(double left, double top, double right, int color) {
    final path = ui.Path()
      ..moveTo(left, h)
      ..quadraticBezierTo((left + right) / 2, top, right, h)
      ..close();
    canvas.drawPath(path, ui.Paint()..color = _c(color));
  }

  // Pines between the far and near hills.
  final pine = ui.Paint()..color = _c(0x1F6B4A);
  for (final (x, height) in [
    (0.14, 0.34),
    (0.22, 0.26),
    (0.78, 0.3),
    (0.86, 0.22),
  ]) {
    final base = h * 0.78;
    final px = w * x, ph = h * height;
    canvas.drawPath(
      ui.Path()
        ..moveTo(px, base - ph)
        ..lineTo(px + ph * 0.32, base)
        ..lineTo(px - ph * 0.32, base)
        ..close(),
      pine,
    );
  }
  hill(-w * 0.3, h * 0.25, w * 0.75, 0xDCE6EE);
  hill(w * 0.3, h * 0.15, w * 1.35, 0xE9EFEC);
  hill(-w * 0.1, h * 0.55, w * 1.1, 0xF5F8F7);
}

void _pagoda(ui.Canvas canvas, ui.Size size) {
  final w = size.width, h = size.height;
  final gold = ui.Paint()..color = _c(0xF2B33D);
  final cx = w / 2;
  // Hill.
  canvas.drawOval(
    ui.Rect.fromCenter(
      center: ui.Offset(cx, h * 1.02),
      width: w * 1.4,
      height: h * 0.36,
    ),
    ui.Paint()..color = _c(0x0F2238),
  );
  // Stacked terraces, narrowing upward.
  var y = h * 0.86;
  for (var i = 0; i < 5; i++) {
    final half = w * (0.3 - i * 0.05);
    final tier = h * 0.06;
    canvas.drawRect(ui.Rect.fromLTRB(cx - half, y - tier, cx + half, y), gold);
    y -= tier;
  }
  // Bell, then the tapering spire and the hti umbrella on top.
  canvas.drawPath(
    ui.Path()
      ..moveTo(cx - w * 0.1, y)
      ..quadraticBezierTo(cx - w * 0.09, y - h * 0.16, cx, y - h * 0.24)
      ..quadraticBezierTo(cx + w * 0.09, y - h * 0.16, cx + w * 0.1, y)
      ..close(),
    gold,
  );
  final top = y - h * 0.24;
  canvas.drawPath(
    ui.Path()
      ..moveTo(cx - w * 0.012, top + h * 0.02)
      ..lineTo(cx, top - h * 0.22)
      ..lineTo(cx + w * 0.012, top + h * 0.02)
      ..close(),
    gold,
  );
  canvas.drawOval(
    ui.Rect.fromCenter(
      center: ui.Offset(cx, top - h * 0.12),
      width: w * 0.05,
      height: h * 0.02,
    ),
    gold,
  );
}

void _lanternGarland(ui.Canvas canvas, ui.Size size) {
  final w = size.width, h = size.height;
  final string = ui.Path()
    ..moveTo(-w * 0.05, h * 0.08)
    ..quadraticBezierTo(w / 2, h * 0.5, w * 1.05, h * 0.08);
  canvas.drawPath(
    string,
    ui.Paint()
      ..color = _c(0x8A7A5A)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3,
  );
  const colors = [
    0xFFD27A,
    0xFFB547,
    0xFF8FC0,
    0xFFD27A,
    0xFFB547,
    0xFF8FC0,
    0xFFD27A,
  ];
  final metric = string.computeMetrics().first;
  for (var i = 0; i < colors.length; i++) {
    final at = metric
        .getTangentForOffset(metric.length * (i + 1) / (colors.length + 1))!
        .position;
    final lw = w * 0.06, lh = lw * 1.35;
    final center = at + ui.Offset(0, lh * 0.7);
    canvas.drawCircle(
      center,
      lw * 1.1,
      ui.Paint()
        ..color = _c(colors[i], 0.35)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 18),
    );
    canvas.drawLine(
      at,
      center - ui.Offset(0, lh / 2),
      ui.Paint()
        ..color = _c(0x8A7A5A)
        ..strokeWidth = 2,
    );
    canvas.drawOval(
      ui.Rect.fromCenter(center: center, width: lw, height: lh),
      ui.Paint()..color = _c(colors[i]),
    );
    // Ribs.
    final rib = ui.Paint()
      ..color = _c(0x000000, 0.18)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final f in [-0.25, 0.0, 0.25]) {
      canvas.drawLine(
        center + ui.Offset(-lw / 2, lh * f * math.sqrt1_2),
        center + ui.Offset(lw / 2, lh * f * math.sqrt1_2),
        rib,
      );
    }
  }
}
