import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/look/applied_look.dart';

import 'fixtures.dart';

void main() {
  final catalog = mockCatalog();
  final at = designDay;

  AppliedLook whole(String id, {String? variantId, Accent? accent}) =>
      AppliedLook.wholeTheme(
        catalog,
        mockTheme(id),
        at: at,
        variantId: variantId,
        accent: accent,
      );

  AppliedLook roundTrip(AppliedLook look) => AppliedLook.fromJson(
    JsonReader.of(jsonDecode(jsonEncode(look.toJson())), 'look'),
  );

  group('whole theme', () {
    test('takes the theme\'s accent, icons, festival and display font', () {
      final look = whole('halloween-night');
      expect(look.theme.id, 'halloween-night');
      expect(look.festival.id, 'halloween');
      expect(look.accent.id, look.theme.defaultAccent.id);
      expect(look.icons.pack.id, 'spooky-glow');
      expect(look.icons.shape, look.icons.pack.shape);
      expect(look.clock.fontId, 'creepster');
      expect(
        look.clock.color.isAccent,
        isTrue,
        reason: 'Halloween clocks glow',
      );
      expect(look.clock.places, const ClockPlaces());
      expect(look.wallpaper.followsTheme, isTrue);
    });

    test('a theme without an accent clock draws it in the text colour', () {
      expect(whole('christmas-eve').clock.color.isText, isTrue);
    });

    test('a variant brings its own accent', () {
      final look = whole('christmas-eve', variantId: 'berry');
      expect(look.accent.id, 'gold');
      expect(look.palette.background.hex, '#4A1020');
    });

    test('carries every font it draws with, and nothing else', () {
      expect(whole('spider-night').fonts.keys.toSet(), {
        'bebas-neue',
        'space-grotesk',
      });
    });

    test('rejects a variant the theme doesn\'t have', () {
      expect(
        () => whole('christmas-eve', variantId: 'neon'),
        throwsArgumentError,
      );
    });
  });

  group('partial applies keep everything else', () {
    final base = whole('spider-night');

    test('wallpaper only: another theme\'s scene, same icons and clock', () {
      final next = base.apply(
        catalog,
        mockTheme('christmas-eve'),
        ApplyOption.wallpaperOnly,
        at: at,
        variantId: 'berry',
      );
      expect(next.theme.id, 'spider-night');
      expect(next.icons.pack.id, base.icons.pack.id);
      expect(next.clock.fontId, base.clock.fontId);
      expect(next.wallpaper.theme!.id, 'christmas-eve');
      expect(next.wallpaper.variantId, 'berry');
      expect(next.wallpaper.accent!.primary.hex, '#B8862E');
      // The other theme's fonts come along for its scene.
      expect(next.fonts.keys, containsAll(['playfair-display', 'dm-sans']));
    });

    test('clock font only: just the font; size, colour and places stay', () {
      final styled = base.withClockFont(
        catalog.font('bebas-neue')!,
        at: at,
        size: ClockSize.large,
        color: ClockColor.fixed(const HexColor('#A970FF')),
        places: const ClockPlaces(homeClock: false, appLabels: true),
      );
      final next = styled.apply(
        catalog,
        mockTheme('halloween-night'),
        ApplyOption.clockFontOnly,
        at: at,
      );
      expect(next.theme.id, 'spider-night');
      expect(next.clock.fontId, 'creepster');
      expect(next.clock.size, ClockSize.large);
      expect(next.clock.color.hex?.hex, '#A970FF');
      expect(next.clock.places.appLabels, isTrue);
      expect(next.wallpaper.followsTheme, isTrue);
    });

    test('an icon pack, with the user\'s tile shape', () {
      final next = base.withIconPack(
        catalog.iconPack('gold-ornament')!,
        at: at,
        shape: IconShape.leaf,
      );
      expect(next.icons.pack.id, 'gold-ornament');
      expect(next.icons.shape, IconShape.leaf);
      expect(next.theme.id, 'spider-night');
    });

    test('a stand-alone wallpaper, then back to the theme\'s own', () {
      final next = base.withWallpaper(
        WallpaperChoice.standalone(catalog.wallpaper('harvest-moon')!),
        at: at,
      );
      expect(next.wallpaper.wallpaper!.id, 'harvest-moon');
      expect(
        next
            .withWallpaper(WallpaperChoice.followTheme, at: at)
            .wallpaper
            .followsTheme,
        isTrue,
      );
    });

    test('fonts nothing uses any more are dropped', () {
      final a = base.withClockFont(catalog.font('playfair-display')!, at: at);
      final b = a.withClockFont(catalog.font('creepster')!, at: at);
      expect(a.fonts.keys, contains('playfair-display'));
      expect(b.fonts.keys, isNot(contains('playfair-display')));
      expect(b.fonts.keys, contains('creepster'));
    });
  });

  group('saved form', () {
    test('every part survives a round trip', () {
      final look = whole('christmas-eve', variantId: 'midnight')
          .apply(
            catalog,
            mockTheme('spider-night'),
            ApplyOption.wallpaperOnly,
            at: at,
          )
          .withClockFont(catalog.font('padauk')!, at: at, size: ClockSize.small)
          .withIconPack(catalog.iconPack('web-slinger')!, at: at);
      expect(jsonEncode(roundTrip(look).toJson()), jsonEncode(look.toJson()));
    });

    test('a stand-alone wallpaper survives a round trip', () {
      final look = whole('halloween-night').withWallpaper(
        WallpaperChoice.standalone(catalog.wallpaper('web-corner')!),
        at: at,
      );
      expect(roundTrip(look).wallpaper.wallpaper!.id, 'web-corner');
    });

    test('works without the catalog: everything is in the snapshot', () {
      final look = roundTrip(whole('spider-night'));
      expect(look.clockFont.family, 'Bebas Neue');
      expect(look.icons.pack.background, isNotNull);
      final thingyan = roundTrip(whole('thingyan-water'));
      expect(thingyan.festival.countdown(designDay).isAnyTime, isFalse);
    });

    test('a look from a newer app version is refused', () {
      final json = whole('spider-night').toJson()..['v'] = 2;
      expect(
        () => AppliedLook.fromJson(JsonReader(json)),
        throwsA(isA<CatalogFormatException>()),
      );
    });

    test('a clock with no place to show is refused', () {
      final json = whole('spider-night').toJson();
      (json['clock']! as Map)['places'] = {
        'lockScreen': false,
        'homeClock': false,
        'appLabels': false,
      };
      expect(
        () => AppliedLook.fromJson(
          JsonReader.of(jsonDecode(jsonEncode(json)), 'look'),
        ),
        throwsA(isA<CatalogFormatException>()),
      );
    });
  });

  test('lists every file it needs on disk', () {
    final look = whole('spider-night').apply(
      catalog,
      mockTheme('halloween-night'),
      ApplyOption.wallpaperOnly,
      at: at,
    );
    final assets = look.assets.map((a) => a.url).toSet();
    // Spider Night's skyline and web, every icon picture and every font
    // file, Halloween's Creepster among them.
    expect(look.fonts.keys, contains('creepster'));
    for (final a in [
      ...mockTheme('spider-night').scene.assets,
      ...look.icons.pack.assets,
      for (final f in look.fonts.values) ...f.files.map((f) => f.asset),
    ]) {
      expect(assets, contains(a.url));
    }
  });
}
