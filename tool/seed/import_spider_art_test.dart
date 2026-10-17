// Imports Spider Night pictures made in an outside image generator
// (docs/spiderman-script.md) in place of the drawn ones:
//
//   tool/seed/incoming/spider-night/icons/<glyph>.png   20 app icons
//   tool/seed/incoming/spider-night/skyline.png         bottom scene layer
//   tool/seed/incoming/spider-night/web.png             top scene layer
//
//   flutter test tool/seed/import_spider_art_test.dart
//
// PNG, JPG or WebP. Icons are centre-cropped square and resized to
// [iconPixels]. Layers are resized to 1080 px wide; a solid green
// (#00FF00) background is made transparent, since most generators can't
// export transparency. Missing files keep the current picture.
//
// Imported files are listed in [externalArtList], and render_art_test.dart
// leaves them alone. Delete that file to go back to the drawn art.
// It's a "test" only because flutter test is the easy way to get dart:ui.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'art.dart';

const _incoming = 'tool/seed/incoming/spider-night';
const _layerWidth = 1080;

void main() {
  test('import Spider Night art', () async {
    if (!Directory(_incoming).existsSync()) {
      fail('Put the generated pictures in $_incoming/ first.');
    }
    final imported = <String>[];

    for (final glyph in glyphPaths.keys) {
      final source = _find('$_incoming/icons/$glyph');
      if (source == null) continue;
      final out = iconPath('web-slinger', glyph);
      await _import(source, out, square: true);
      imported.add(out);
    }
    for (final (name, art) in [
      ('skyline', LayerArt.spiderSkyline),
      ('web', LayerArt.spiderWeb),
    ]) {
      final source = _find('$_incoming/$name');
      if (source == null) continue;
      final out = layerPath(art);
      await _import(source, out, square: false);
      imported.add(out);
    }

    if (imported.isEmpty) fail('No pictures found in $_incoming/.');
    // Keeps earlier imports that weren't replaced this time.
    final list = File(externalArtList);
    final all = {
      if (list.existsSync())
        ...list.readAsLinesSync().where((l) => l.isNotEmpty),
      ...imported,
    }.toList()..sort();
    list.writeAsStringSync('${all.join('\n')}\n');
    // ignore: avoid_print
    print('Imported ${imported.length} pictures:\n  ${imported.join('\n  ')}');
  });
}

String? _find(String base) {
  for (final ext in ['png', 'jpg', 'jpeg', 'webp']) {
    if (File('$base.$ext').existsSync()) return '$base.$ext';
  }
  return null;
}

Future<void> _import(String source, String out, {required bool square}) async {
  final codec = await ui.instantiateImageCodec(File(source).readAsBytesSync());
  final image = (await codec.getNextFrame()).image;
  final iw = image.width.toDouble(), ih = image.height.toDouble();

  // Icons: the centre square. Layers: the whole picture.
  final side = iw < ih ? iw : ih;
  final from = square
      ? ui.Rect.fromCenter(
          center: ui.Offset(iw / 2, ih / 2),
          width: side,
          height: side,
        )
      : ui.Rect.fromLTWH(0, 0, iw, ih);
  final width = square ? iconPixels : _layerWidth;
  final height = square ? iconPixels : (ih * _layerWidth / iw).round();

  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    image,
    from,
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  var resized = await recorder.endRecording().toImage(width, height);
  if (!square) resized = await _keyGreen(resized);

  final png = await resized.toByteData(format: ui.ImageByteFormat.png);
  final file = File(out);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(png!.buffer.asUint8List());
}

/// Makes a solid green background transparent, if any corner is green (so
/// art that's already transparent, or has no green screen, is left alone).
/// Soft edges keep part of their alpha, and green spill is taken out of
/// the edge pixels that resizing blended with the background.
Future<ui.Image> _keyGreen(ui.Image image) async {
  final data = (await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  ))!;
  final px = Uint8List.fromList(data.buffer.asUint8List());
  int greenness(int i) {
    final r = px[i], g = px[i + 1], b = px[i + 2];
    return g - (r > b ? r : b);
  }

  final w = image.width, h = image.height;
  final corners = [0, w - 1, (h - 1) * w, h * w - 1].map((p) => p * 4);
  if (!corners.any((i) => px[i + 3] == 255 && greenness(i) >= 80)) {
    return image;
  }

  for (var i = 0; i < px.length; i += 4) {
    final k = greenness(i);
    if (k <= 8) continue;
    final r = px[i], b = px[i + 2];
    px[i + 1] = r > b ? r : b; // Despill.
    // 30 → fully kept, 110 and above → fully clear.
    final alpha = (1 - (k - 30) / 80).clamp(0.0, 1.0);
    px[i + 3] = (px[i + 3] * alpha).round();
  }
  // decodeImageFromPixels takes premultiplied alpha.
  for (var i = 0; i < px.length; i += 4) {
    final a = px[i + 3];
    if (a == 255) continue;
    for (var c = 0; c < 3; c++) {
      px[i + c] = (px[i + c] * a / 255).round();
    }
  }
  final keyed = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    px,
    image.width,
    image.height,
    ui.PixelFormat.rgba8888,
    keyed.complete,
  );
  return keyed.future;
}
