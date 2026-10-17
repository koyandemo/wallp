// Draws the Spider Night kit the way the app will, from the generated demo
// catalog, into build/spider-night-preview/:
//
// * scene-<t>.png: the live wallpaper at a few moments of its animation,
//   drawn by the app's own LayersPainter.
// * still.png: the Web Corner still wallpaper.
// * icons.png: every Web Slinger icon on the wallpaper.
//
//   flutter test tool/seed/spider_night_preview_test.dart
//
// Run generate.dart first (tool/seed/spider_night.sh does both).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/render/layered_scene.dart';
import 'package:wallp/render/layers_painter.dart';

import 'seed_data.dart' show spiderThemeId;

const _dir = 'assets/mock/catalog/v1';
const _out = 'build/spider-night-preview';
const _w = 540, _h = 1170;

Object? _read(String path) =>
    jsonDecode(File('$_dir/$path').readAsStringSync());

Future<ui.Image> _decode(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

Future<void> _save(String name, void Function(ui.Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final image = await recorder.endRecording().toImage(_w, _h);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('$_out/$name');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(png!.buffer.asUint8List());
}

void main() {
  late Catalog catalog;
  late ThemeDetail theme;
  final images = <String, ui.Image>{};

  setUpAll(() async {
    final manifest = Manifest.fromJson(
      JsonReader.of(_read('manifest.json'), 'manifest'),
    );
    catalog = Catalog.fromJson(
      JsonReader.of(_read(manifest.catalog), 'catalog'),
    );
    final summary = catalog.theme(spiderThemeId)!;
    theme = ThemeDetail.fromJson(
      JsonReader.of(_read('themes/${summary.id}.${summary.rev}.json'), 'theme'),
    );
    for (final ref in {
      ...theme.scene.assets,
      ...catalog.iconPack(theme.iconPackId)!.glyphs.values,
    }) {
      images[ref.sha256] = await _decode('$_dir/${ref.url}');
    }
  });

  Color c(HexColor h) => Color(h.argb);

  LayersPainter painter(List<Layer> layers, double t) {
    final p = theme.palette;
    final accent = theme.accents.first;
    return LayersPainter(
      time: ValueNotifier(t),
      accent: c(accent.primary),
      images: images,
      scene: LayeredScene(
        layers: layers,
        tokens: {
          '@background': c(p.background),
          '@deep': c(p.deep),
          '@surface': c(p.surface),
          '@text': c(p.text),
          '@motif': c(p.motif ?? p.text),
          '@accent': c(accent.primary),
        },
      ),
    );
  }

  const size = Size(_w * 1.0, _h * 1.0);

  test('live wallpaper frames', () async {
    for (final t in [0.0, 1.3, 2.6]) {
      await _save(
        'scene-${t.toStringAsFixed(1)}.png',
        (canvas) => painter(theme.scene.layers!, t).paint(canvas, size),
      );
    }
  });

  test('still wallpaper', () async {
    final still = catalog.wallpapers.firstWhere((w) => w.id == 'web-corner');
    await _save(
      'still.png',
      (canvas) => painter(still.scene!.layers!, 0).paint(canvas, size),
    );
  });

  test('icon pack on the wallpaper', () async {
    final pack = catalog.iconPack(theme.iconPackId)!;
    await _save('icons.png', (canvas) {
      painter(theme.scene.layers!, 1.3).paint(canvas, size);
      const cols = 4, icon = 96.0, gap = (_w - cols * icon) / (cols + 1);
      for (final (i, ref) in pack.glyphs.values.indexed) {
        final image = images[ref.sha256]!;
        final x = gap + (i % cols) * (icon + gap);
        final y = 150 + (i ~/ cols) * (icon + gap * 1.1);
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width * 1.0, image.height * 1.0),
          Rect.fromLTWH(x, y, icon, icon),
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
    });
  });
}
