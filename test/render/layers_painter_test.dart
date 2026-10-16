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

void main() {
  final catalog = mockCatalog();

  PhoneTheme themeOf(String id, {String? variantId, Accent? accent}) {
    var look = AppliedLook.wholeTheme(
      catalog,
      mockTheme(id),
      at: designDay,
      variantId: variantId,
    );
    if (accent != null) look = look.withAccent(accent, at: designDay);
    return ResolvedLook.of(look, designDay).wallpaperTheme;
  }

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

  test('every dashboard theme and wallpaper draws, at any moment', () async {
    final layered = [
      for (final t in catalog.themes)
        if (!t.isBuiltIn) themeOf(t.id),
    ];
    expect(layered, hasLength(27));
    for (final theme in layered) {
      for (final t in [0.0, 1.2, 37.5]) {
        await _render(painterFor(theme, t: t));
      }
    }
    for (final w in catalog.wallpapers.where((w) => w.scene?.layers != null)) {
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
    // Gradient @surface → @background, top to bottom.
    final warm = await _render(painterFor(themeOf('cozy-cabin')));
    final snowedIn = await _render(
      painterFor(themeOf('cozy-cabin', variantId: 'snowed-in')),
    );
    final surface = Color(mockTheme('cozy-cabin').palette.surface.argb);
    expect(_close(_pixel(warm, 5, 1), surface), isTrue);
    final snowSurface = Color(
      mockTheme('cozy-cabin').paletteFor('snowed-in').surface.argb,
    );
    expect(_close(_pixel(snowedIn, 5, 1), snowSurface), isTrue);
  });

  test('@accent shapes follow the user\'s accent', () async {
    // Quiet Ink's moon is @motif; its crater is @deep. The tree star in
    // Midnight Snow is @accent at (0.5, 0.42).
    final rose = Accent(
      id: 'rose',
      name: LocalizedText.en('Rose'),
      colors: const [HexColor('#FF5FA2')],
    );
    final data = await _render(
      painterFor(themeOf('midnight-snow', accent: rose)),
    );
    final star = _pixel(
      data,
      (_size.width * 0.5).round(),
      (_size.height * 0.42).round(),
    );
    expect(
      _close(star, const Color(0xFFFF5FA2), tolerance: 30),
      isTrue,
      reason: '$star',
    );
  });

  test(
    'a still theme looks the same at every moment; a live one moves',
    () async {
      final still = themeOf('quiet-ink');
      expect(
        (await _render(painterFor(still, t: 1))).buffer.asUint8List(),
        (await _render(painterFor(still, t: 9))).buffer.asUint8List(),
      );
      final live = themeOf('cocoa-night'); // snow
      expect(
        (await _render(painterFor(live, t: 1))).buffer.asUint8List(),
        isNot((await _render(painterFor(live, t: 9))).buffer.asUint8List()),
      );
    },
  );

  test(
    'an image layer draws once its picture is loaded, and is skipped before',
    () async {
      final theme = themeOf('golden-pagoda');
      final ref = theme.layered!.images.single;
      final bytes = File('$mockDir/${ref.url}').readAsBytesSync();
      final codec = await ui.instantiateImageCodec(bytes);
      final pagoda = (await codec.getNextFrame()).image;

      final without = await _render(painterFor(theme));
      final with_ = await _render(
        painterFor(theme, images: {ref.sha256: pagoda}),
      );
      // The gold pagoda stands in the middle, above the ground.
      final x = (_size.width * 0.5).round(), y = (_size.height * 0.88).round();
      expect(
        _close(_pixel(with_, x, y), const Color(0xFFF2B33D), tolerance: 20),
        isTrue,
      );
      expect(
        _close(_pixel(without, x, y), const Color(0xFFF2B33D), tolerance: 20),
        isFalse,
      );
    },
  );

  test('scenePainterFor picks the layers painter for dashboard themes', () {
    final painter = scenePainterFor(
      themeOf('ember'),
      ValueNotifier(0),
      const Color(0xFFFFB547),
    );
    expect(painter, isA<LayersPainter>());
    final builtIn = ResolvedLook.of(
      AppliedLook.wholeTheme(
        catalog,
        mockTheme('halloween-night'),
        at: designDay,
      ),
      designDay,
    ).wallpaperTheme;
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
      // "Download" Golden Pagoda's files.
      for (final ref in catalog.assetsFor(mockTheme('golden-pagoda'))) {
        await cache.put(ref, File('$mockDir/${ref.url}').readAsBytesSync());
      }
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('SceneAssets decodes a picture once and shares it', () async {
      final ref = themeOf('golden-pagoda').layered!.images.single;
      final a = await assets.image(ref);
      final b = await assets.image(ref);
      expect(a, isNotNull);
      expect(identical(a, b), isTrue);
    });

    test('a file that isn\'t on the phone is null, not an error', () async {
      final missing = themeOf('cozy-cabin').layered!.images.single;
      expect(await assets.image(missing), isNull);
      expect(await assets.bytes(missing), isNull);
    });

    test('the wallpaper image includes the downloaded picture', () async {
      final png = await WallpaperRenderer.renderPng(
        theme: themeOf('golden-pagoda'),
        accent: const Color(0xFFF2B33D),
        pixelSize: _size,
        assets: assets,
      );
      final image = await (await ui.instantiateImageCodec(png)).getNextFrame();
      final data = (await image.image.toByteData())!;
      final x = (_size.width * 0.5).round(), y = (_size.height * 0.88).round();
      expect(
        _close(_pixel(data, x, y), const Color(0xFFF2B33D), tolerance: 20),
        isTrue,
      );
    });
  });
}
