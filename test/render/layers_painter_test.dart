import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/data/assets/asset_cache.dart';
import 'package:wallp/look/applied_look.dart';
import 'package:wallp/look/resolved_look.dart';
import 'package:wallp/models/phone_theme.dart';
import 'package:wallp/render/layered_scene.dart';
import 'package:wallp/render/layers_painter.dart';
import 'package:wallp/render/scene_assets.dart';
import 'package:wallp/scenes/scene_view.dart';
import 'package:wallp/services/wallpaper_renderer.dart';

import '../catalog/fakes.dart';
import '../look/fixtures.dart';

const _size = Size(195, 422); // Half the design size: quick to render.

/// Renders [painter] and returns its RGBA pixels.
Future<ByteData> _render(LayersPainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(ui.Canvas(recorder), _size);
  final image = await recorder.endRecording().toImage(
    _size.width.toInt(),
    _size.height.toInt(),
  );
  final data = await image.toByteData();
  image.dispose();
  return data!;
}

Color _pixel(ByteData data, int x, int y) {
  final i = (y * _size.width.toInt() + x) * 4;
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

bool _close(Color a, Color b, {int tolerance = 6}) =>
    ((a.r - b.r) * 255).abs() <= tolerance &&
    ((a.g - b.g) * 255).abs() <= tolerance &&
    ((a.b - b.b) * 255).abs() <= tolerance;

/// Average brightness (0..255) of the bottom tenth of [data].
double _bottomBrightness(ByteData data) {
  final w = _size.width.toInt(), h = _size.height.toInt();
  var sum = 0.0, n = 0;
  for (var y = (h * 0.9).round(); y < h; y++) {
    for (var x = 0; x < w; x += 3) {
      final c = _pixel(data, x, y);
      sum += (c.r + c.g + c.b) / 3 * 255;
      n++;
    }
  }
  return sum / n;
}

void main() {
  final catalog = mockCatalog();

  /// Spider Night's theme file, editable: the only theme on the layers
  /// engine, so tests add what they need to it (a variant, a layer).
  Map<String, dynamic> spiderJson() {
    final rev = catalog.theme('spider-night')!.rev;
    return jsonDecode(
      File('$mockDir/themes/spider-night.$rev.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  }

  List<dynamic> layersOf(Map<String, dynamic> json) =>
      (json['scene'] as Map)['params']['layers'] as List;

  PhoneTheme themeOf(ThemeDetail theme, {String? variantId, Accent? accent}) {
    var look = AppliedLook.wholeTheme(
      catalog,
      theme,
      at: designDay,
      variantId: variantId,
    );
    if (accent != null) look = look.withAccent(accent, at: designDay);
    return ResolvedLook.of(look, designDay).wallpaperTheme;
  }

  ThemeDetail parse(Map<String, dynamic> json) =>
      ThemeDetail.fromJson(JsonReader(json, 'theme'));

  PhoneTheme spider() => themeOf(mockTheme('spider-night'));

  LayersPainter painterFor(
    PhoneTheme theme, {
    double t = 1.2,
    Map<String, ui.Image> images = const {},
  }) => LayersPainter(
    time: ValueNotifier(t),
    accent: theme.palette.accent,
    scene: theme.layered!,
    images: images,
  );

  /// The skyline picture along Spider Night's bottom edge.
  AssetRef skyline() =>
      mockTheme('spider-night').scene.layers!
          .whereType<ImageLayer>()
          .firstWhere((l) => l.anchor == ImageAnchor.bottom)
          .image;

  Future<Map<String, ui.Image>> decoded(Iterable<AssetRef> refs) async => {
    for (final ref in refs)
      ref.sha256: (await (await ui.instantiateImageCodec(
        File('$mockDir/${ref.url}').readAsBytesSync(),
      )).getNextFrame()).image,
  };

  test('every dashboard theme and wallpaper draws, at any moment', () async {
    final layered = [
      for (final t in catalog.themes)
        if (!t.isBuiltIn) themeOf(mockTheme(t.id)),
    ];
    expect(layered, hasLength(1));
    for (final theme in layered) {
      for (final t in [0.0, 1.2, 37.5]) {
        await _render(painterFor(theme, t: t));
      }
    }
    final wallpapers = catalog.wallpapers.where((w) => w.scene?.layers != null);
    expect(wallpapers, hasLength(2));
    for (final w in wallpapers) {
      final scene = LayeredScene(layers: w.scene!.layers!, tokens: const {});
      await _render(
        LayersPainter(
          time: ValueNotifier(1.2),
          accent: const Color(0xFFFFFFFF),
          scene: scene,
        ),
      );
    }
  });

  test('the sky is the palette\'s colours, following the variant', () async {
    // Gradient @background → @surface → #3A1030, top to bottom.
    final json = spiderJson()
      ..['variants'] = [
        {
          'id': 'night',
          'name': {'en': 'Night'},
        },
        {
          'id': 'dusk',
          'name': {'en': 'Dusk'},
          'palette': {'background': '#402060'},
        },
      ];
    final theme = parse(json);
    final night = await _render(painterFor(themeOf(theme)));
    final dusk = await _render(painterFor(themeOf(theme, variantId: 'dusk')));
    expect(
      _close(_pixel(night, 5, 1), Color(theme.palette.background.argb)),
      isTrue,
    );
    expect(_close(_pixel(dusk, 5, 1), const Color(0xFF402060)), isTrue);
  });

  test('@accent shapes follow the user\'s accent', () async {
    final json = spiderJson();
    layersOf(json).add({
      'type': 'shape',
      'shape': 'circle',
      'x': 0.5,
      'y': 0.6,
      'width': 0.2,
      'color': '@accent',
    });
    final rose = Accent(
      id: 'rose',
      name: LocalizedText.en('Rose'),
      colors: const [HexColor('#FF5FA2')],
    );
    final data = await _render(painterFor(themeOf(parse(json), accent: rose)));
    final dot = _pixel(
      data,
      (_size.width * 0.5).round(),
      (_size.height * 0.6).round(),
    );
    expect(
      _close(dot, const Color(0xFFFF5FA2), tolerance: 30),
      isTrue,
      reason: '$dot',
    );
  });

  test(
    'a still theme looks the same at every moment; a live one moves',
    () async {
      final json = spiderJson();
      layersOf(json).removeWhere((l) => (l as Map)['type'] == 'particles');
      for (final l in layersOf(json).cast<Map>()) {
        l.remove('motion');
      }
      final still = themeOf(parse(json));
      expect(
        (await _render(painterFor(still, t: 1))).buffer.asUint8List(),
        (await _render(painterFor(still, t: 9))).buffer.asUint8List(),
      );
      final live = spider(); // rain, a pulsing moon, a swinging spider
      expect(
        (await _render(painterFor(live, t: 1))).buffer.asUint8List(),
        isNot((await _render(painterFor(live, t: 9))).buffer.asUint8List()),
      );
    },
  );

  test(
    'an image layer draws once its picture is loaded, and is skipped before',
    () async {
      final theme = spider();
      final images = await decoded([skyline()]);
      final without = await _render(painterFor(theme));
      final with_ = await _render(painterFor(theme, images: images));
      // The near-black buildings fill the bottom edge.
      expect(
        _bottomBrightness(with_),
        lessThan(_bottomBrightness(without) - 5),
      );
    },
  );

  test('scenePainterFor picks the layers painter for dashboard themes', () {
    final painter = scenePainterFor(
      spider(),
      ValueNotifier(0),
      const Color(0xFFE23636),
    );
    expect(painter, isA<LayersPainter>());
    final builtIn = themeOf(mockTheme('halloween-night'));
    expect(
      scenePainterFor(builtIn, ValueNotifier(0), const Color(0xFFFFB547)),
      isNot(isA<LayersPainter>()),
    );
  });

  group('with downloaded files', () {
    late Directory dir;
    late SceneAssets assets;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('wallp_render_');
      final cache = AssetCache(dir);
      assets = SceneAssets(cache);
      // "Download" Spider Night's files.
      for (final ref in catalog.assetsFor(mockTheme('spider-night'))) {
        await cache.put(ref, File('$mockDir/${ref.url}').readAsBytesSync());
      }
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('SceneAssets decodes a picture once and shares it', () async {
      final a = await assets.image(skyline());
      final b = await assets.image(skyline());
      expect(a, isNotNull);
      expect(identical(a, b), isTrue);
    });

    test('a file that isn\'t on the phone is null, not an error', () async {
      const sha =
          'ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12';
      const missing = AssetRef(
        url: 'assets/$sha.png',
        sha256: sha,
        bytes: 100,
        format: AssetFormat.png,
      );
      expect(await assets.image(missing), isNull);
      expect(await assets.bytes(missing), isNull);
    });

    test('the wallpaper image includes the downloaded pictures', () async {
      Future<ByteData> render(SceneAssets from) async {
        final png = await WallpaperRenderer.renderPng(
          theme: spider(),
          accent: const Color(0xFFE23636),
          pixelSize: _size,
          assets: from,
        );
        final image = await (await ui.instantiateImageCodec(png))
            .getNextFrame();
        return (await image.image.toByteData())!;
      }

      final empty = Directory.systemTemp.createTempSync('wallp_render_none_');
      addTearDown(() => empty.deleteSync(recursive: true));
      final with_ = await render(assets);
      final without = await render(SceneAssets(AssetCache(empty)));
      expect(
        _bottomBrightness(with_),
        lessThan(_bottomBrightness(without) - 5),
      );
    });
  });
}
