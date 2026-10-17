// Draws the mock catalog's icon pack tile and scene layer PNGs.
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

import 'art.dart';
import 'spider_night_art.dart';

void main() {
  test('render the Web Slinger tile', () async {
    await _save(
      backgroundPath(webSlinger.id),
      iconPixels,
      iconPixels,
      (c) => _tile(c, webSlinger),
    );
  });

  test('render scene layers', () async {
    for (final art in LayerArt.values) {
      await _save(layerPath(art), art.width, art.height, (c) {
        final size = ui.Size(art.width.toDouble(), art.height.toDouble());
        switch (art) {
          case LayerArt.spiderSkyline:
            spiderSkyline(c, size);
          case LayerArt.spiderWeb:
            spiderWeb(c, size);
        }
      });
    }
  });
}

ui.Color _c(int rgb, [double alpha = 1]) =>
    ui.Color(0xFF000000 | rgb).withValues(alpha: alpha);

/// Files imported from an image generator, which this leaves alone.
final _external = File(externalArtList).existsSync()
    ? File(externalArtList).readAsLinesSync().toSet()
    : const <String>{};

Future<void> _save(
  String path,
  int width,
  int height,
  void Function(ui.Canvas) draw,
) async {
  if (_external.contains(path)) return;
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

/// Draws a pack's tile edge to edge on the square canvas: no margin and no
/// rim, since the app clips it to the user's tile shape and draws the rim in
/// the pack's ring colour itself.
void _tile(ui.Canvas canvas, PackArt pack) {
  const s = iconPixels * 1.0;
  const tile = ui.Rect.fromLTWH(0, 0, s, s);
  canvas.drawRect(tile, ui.Paint()..color = _c(pack.tile));
  _comicWeb(canvas, pack, tile);
}

/// A web from the centre out past every edge.
void _comicWeb(ui.Canvas canvas, PackArt pack, ui.Rect tile) {
  final hub = tile.center;
  final reach = tile.width * 0.75;
  const spokes = 12;
  ui.Offset at(double angle, double r) =>
      hub + ui.Offset(math.cos(angle) * r, math.sin(angle) * r);
  final web = ui.Paint()
    ..color = _c(pack.ring, 0.35)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 2;
  canvas
    ..save()
    ..clipRect(tile);
  for (var i = 0; i < spokes; i++) {
    canvas.drawLine(hub, at(i * 2 * math.pi / spokes, reach), web);
  }
  for (final r in [0.18, 0.32, 0.48, 0.66]) {
    final radius = tile.width * r;
    final ring = ui.Path()..moveTo(at(0, radius).dx, at(0, radius).dy);
    for (var i = 1; i <= spokes; i++) {
      final mid = at((i - 0.5) * 2 * math.pi / spokes, radius * 0.88);
      final end = at(i * 2 * math.pi / spokes, radius);
      ring.quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);
    }
    canvas.drawPath(ring, web);
  }
  canvas.restore();
}
