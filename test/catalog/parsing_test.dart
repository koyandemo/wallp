// How the parser treats bad or unexpected data: the rules in
// docs/theme-api.md §5, §8 and §9 that keep a bad publish from breaking
// the app.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';

const _dir = 'assets/mock/catalog/v1';

/// A fresh, editable copy of the seed catalog JSON.
Map<String, dynamic> _seedCatalog() {
  final manifest =
      jsonDecode(File('$_dir/manifest.json').readAsStringSync()) as Map;
  return jsonDecode(File('$_dir/${manifest['catalog']}').readAsStringSync())
      as Map<String, dynamic>;
}

/// The theme's file at whatever rev the seed is on.
Map<String, dynamic> _seedTheme(String id) {
  final file = Directory('$_dir/themes')
      .listSync()
      .whereType<File>()
      .firstWhere((f) => RegExp('/$id\\.\\d+\\.json\$').hasMatch(f.path));
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Catalog _parse(Map<String, dynamic> json) =>
    Catalog.fromJson(JsonReader(json, 'catalog'));

List<Map<String, dynamic>> _list(Map<String, dynamic> json, String key) =>
    (json[key] as List).cast<Map<String, dynamic>>();

Matcher _formatError(String path) =>
    throwsA(isA<CatalogFormatException>().having((e) => e.path, 'path', path));

void main() {
  group('manifest', () {
    Map<String, dynamic> manifest(int schema) => {
      'schemaVersion': schema,
      'catalogVersion': '2026-10-15.1',
      'catalog': 'catalog.2026-10-15.1.json',
      'catalogSha256': 'x',
      'minAppVersion': '1.0.0',
      'publishedAt': '2026-10-15T14:00:00Z',
    };

    test('an unknown schemaVersion is refused, so the app keeps its cache', () {
      expect(
        () => Manifest.fromJson(JsonReader(manifest(2))),
        throwsA(isA<UnsupportedSchemaException>()),
      );
    });

    test('times must be UTC', () {
      expect(
        () => Manifest.fromJson(
          JsonReader({...manifest(1), 'publishedAt': '2026-10-15T14:00:00'}),
        ),
        _formatError(r'$.publishedAt'),
      );
    });
  });

  group('one bad item never takes the catalog down', () {
    test('a broken theme is skipped and reported with its path', () {
      final json = _seedCatalog();
      final themes = _list(json, 'themes');
      final total = themes.length;
      (themes[1]['palette'] as Map)['background'] = 'orange';

      final catalog = _parse(json);
      expect(catalog.themes, hasLength(total - 1));
      expect(
        catalog.issues.single.path,
        r'catalog.themes[1].palette.background',
      );
      expect(catalog.issues.single.message, contains('"#RRGGBB"'));
    });

    test('an unknown layer type skips only that theme', () {
      final json = _seedCatalog();
      final spider = _list(
        json,
        'themes',
      ).firstWhere((t) => t['id'] == 'spider-night');
      ((spider['scene'] as Map)['params']['layers'] as List).add({
        'type': 'video',
      });

      final catalog = _parse(json);
      expect(catalog.theme('spider-night'), isNull);
      expect(catalog.theme('halloween-night'), isNotNull);
      expect(catalog.wallpaper('red-moon-swing'), isNotNull);
    });

    test('a theme whose festival is missing is dropped', () {
      final json = _seedCatalog();
      _list(
        json,
        'themes',
      ).firstWhere((t) => t['id'] == 'thingyan-water')['festivalId'] = 'gone';

      final catalog = _parse(json);
      expect(catalog.theme('thingyan-water'), isNull);
      expect(
        catalog.issues.map((e) => e.message),
        contains('themes[thingyan-water].festivalId: no festival "gone"'),
      );
    });

    test('dropping a theme also drops the banner that opens it', () {
      final json = _seedCatalog();
      final haunted = _list(
        json,
        'themes',
      ).firstWhere((t) => t['id'] == 'halloween-night');
      haunted['iconPackId'] = 'no-such-pack';

      final catalog = _parse(json);
      expect(catalog.theme('halloween-night'), isNull);
      expect(catalog.banners.where((b) => b.id == 'halloween-2026'), isEmpty);
      expect(catalog.banners, isNotEmpty);
      // The festival it was the cover of stays: a cover is only decoration.
      expect(catalog.festival('halloween'), isNotNull);
      expect(catalog.themesIn('halloween'), isEmpty);
    });

    test('a missing cover or banner art is a soft reference: kept, reported '
        'only by the strict publish check', () {
      final json = _seedCatalog();
      _list(json, 'festivals').first['coverThemeId'] = 'gone';
      final catalog = _parse(json);
      expect(catalog.festival('halloween'), isNotNull);
      expect(catalog.issues, isEmpty);
      expect(catalog.validate(includeSoft: false), isEmpty);
      expect(
        catalog.validate(),
        contains('festivals[halloween].coverThemeId: no theme "gone"'),
      );
    });

    test('unknown extra fields are ignored (a newer optional field)', () {
      final json = _seedCatalog();
      _list(json, 'themes').first['access'] = 'premium';
      json['somethingNew'] = {'a': 1};
      expect(_parse(json).issues, isEmpty);
    });
  });

  group('engines this build can\'t draw are hidden (§5)', () {
    test('an old app without the layers engine sees only built-ins', () {
      final catalog = _parse(_seedCatalog()).supportedBy(EngineIds.builtIn);
      expect(catalog.themes.map((t) => t.id), [
        'halloween-night',
        'christmas-eve',
        'thingyan-water',
      ]);
      expect(
        catalog.wallpapers.every((w) => w.scene!.engine != EngineIds.layers),
        isTrue,
      );
      // The banner that opened Spider Night goes with it; the rest stay.
      expect(catalog.banners.map((b) => b.id), isNot(contains('spider-night')));
      expect(catalog.banners.map((b) => b.id), contains('halloween-2026'));
    });

    test('a theme on a future engine is hidden from this build', () {
      final json = _seedCatalog();
      final theme = _list(
        json,
        'themes',
      ).firstWhere((t) => t['id'] == 'spider-night');
      theme['scene'] = {'engine': 'rive', 'params': {}};
      final catalog = _parse(json)
          .supportedBy({...EngineIds.builtIn, EngineIds.layers});
      expect(catalog.theme('spider-night'), isNull);
      expect(catalog.theme('halloween-night'), isNotNull);
      // Its wallpapers are still on the layers engine, so they stay.
      expect(catalog.wallpaper('red-moon-swing'), isNotNull);
    });
  });

  group('theme file', () {
    ThemeDetail parse(Map<String, dynamic> json) =>
        ThemeDetail.fromJson(JsonReader(json, 'theme'));

    test('a variant can\'t point at an accent the theme doesn\'t have', () {
      final json = _seedTheme('christmas-eve');
      (json['variants'] as List)[1]['accentId'] = 'nope';
      expect(() => parse(json), _formatError('theme.variants[1].accentId'));
    });

    test('a variant only changes the colours it lists', () {
      final theme = parse(_seedTheme('christmas-eve'));
      final midnight = theme.paletteFor('midnight');
      expect(midnight.background.hex, '#10223D');
      expect(midnight.text, theme.palette.text);
      expect(theme.paletteFor(null).background, theme.palette.background);
      expect(theme.paletteFor('unknown').background, theme.palette.background);
    });

    test('a gradient accent needs 2–3 colours', () {
      final json = _seedTheme('halloween-night');
      (json['accents'] as List).last['colors'] = ['#FFB547'];
      expect(() => parse(json), _formatError('theme.accents[3].colors'));
    });

    test('the NEW badge lasts 14 days from publishing', () {
      final theme = parse(_seedTheme('spider-night'));
      final published = theme.publishedAt;
      expect(theme.isNew(published), isTrue);
      expect(
        theme.isNew(published.add(const Duration(days: 13, hours: 23))),
        isTrue,
      );
      expect(theme.isNew(published.add(const Duration(days: 14))), isFalse);
      // A clock set before publishing doesn't count as new.
      expect(
        theme.isNew(published.subtract(const Duration(hours: 1))),
        isFalse,
      );
    });

    test(
      'a theme with particles or moving shapes is live; still ones aren\'t',
      () {
        final json = _seedTheme('spider-night');
        expect(parse(json).isLive, isTrue);
        // The same scene without its particles and motion is still.
        final layers = (json['scene'] as Map)['params']['layers'] as List;
        layers.removeWhere((l) => (l as Map)['type'] == 'particles');
        for (final l in layers.cast<Map>()) {
          l.remove('motion');
        }
        expect(parse(json).isLive, isFalse);
        // Built-in painters always animate.
        expect(parse(_seedTheme('thingyan-water')).isLive, isTrue);
      },
    );
  });

  group('safety limits (§8)', () {
    Map<String, dynamic> asset({int bytes = 100, String? url}) {
      const sha =
          'ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12';
      return {
        'url': url ?? 'assets/$sha.png',
        'sha256': sha,
        'bytes': bytes,
        'format': 'png',
      };
    }

    test('refuses files over 10 MB', () {
      expect(
        () => AssetRef.fromJson(JsonReader(asset(bytes: 11 * 1024 * 1024))),
        _formatError(r'$.bytes'),
      );
    });

    test('an asset URL must be its own hash, so files can\'t be swapped', () {
      expect(
        () => AssetRef.fromJson(JsonReader(asset(url: 'assets/other.png'))),
        _formatError(r'$.url'),
      );
    });

    test('a particle layer can\'t ask for thousands of particles', () {
      final json = _seedTheme('spider-night');
      final layers = (json['scene'] as Map)['params']['layers'] as List;
      layers.last['count'] = 5000;
      expect(
        () => ThemeDetail.fromJson(JsonReader(json, 'theme')),
        throwsA(isA<CatalogFormatException>()),
      );
    });

    test('a wallpaper scene can\'t use palette tokens (it has no palette)', () {
      final json = _seedCatalog();
      final corner = _list(
        json,
        'wallpapers',
      ).firstWhere((w) => w['id'] == 'web-corner');
      ((corner['scene'] as Map)['params']['layers'] as List).first['colors'] = [
        '@accent',
        '#000000',
      ];
      final catalog = _parse(json);
      expect(catalog.wallpaper('web-corner'), isNull);
    });

    test('fonts must have a licence that allows redistribution', () {
      final json = _seedCatalog();
      _list(json, 'fonts').first['license'] = 'Proprietary';
      expect(_parse(json).font('creepster'), isNull);
    });

    test('banner links must be https', () {
      expect(
        () => BannerAction.fromJson(
          JsonReader({'type': 'url', 'url': 'http://example.com'}),
        ),
        _formatError(r'$.url'),
      );
    });
  });

  group('text and banners', () {
    test('localized text falls back to English', () {
      final text = LocalizedText.fromJson({
        'en': 'Water Festival',
        'my': 'သင်္ကြန်',
      }, 'p');
      expect(text.resolve('my'), 'သင်္ကြန်');
      expect(text.resolve('fr'), 'Water Festival');
    });

    test('English is required', () {
      expect(
        () => LocalizedText.fromJson({'my': 'သင်္ကြန်'}, 'p'),
        _formatError('p'),
      );
    });

    test('a banner shows only inside its window', () {
      final catalog = _parse(_seedCatalog());
      final halloween = catalog.banners.firstWhere(
        (b) => b.id == 'halloween-2026',
      );
      expect(halloween.isShowing(DateTime.utc(2026, 9, 30, 23, 59)), isFalse);
      expect(halloween.isShowing(DateTime.utc(2026, 10, 1)), isTrue);
      expect(halloween.isShowing(DateTime.utc(2026, 11, 1)), isFalse);
      expect(
        catalog.banners
            .firstWhere((b) => b.id == 'clock-fonts')
            .isShowing(DateTime.utc(2030)),
        isTrue,
      );
    });
  });

  test('a catalog written by toJson reads back identically', () {
    final catalog = _parse(_seedCatalog());
    final again = _parse(
      jsonDecode(jsonEncode(catalog.toJson())) as Map<String, dynamic>,
    );
    expect(jsonEncode(again.toJson()), jsonEncode(catalog.toJson()));
  });
}
