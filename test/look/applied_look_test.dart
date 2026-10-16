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
      expect(whole('cozy-cabin').fonts.keys.toSet(), {'caveat', 'dm-sans'});
    });

    test('rejects a variant the theme doesn\'t have', () {
      expect(
        () => whole('christmas-eve', variantId: 'neon'),
        throwsArgumentError,
      );
    });
  });

  group('partial applies keep everything else', () {
    final base = whole('cozy-cabin');

    test('wallpaper only: another theme\'s scene, same icons and clock', () {
      final next = base.apply(
        catalog,
        mockTheme('gold-ornaments'),
        ApplyOption.wallpaperOnly,
        at: at,
        variantId: 'navy',
      );
      expect(next.theme.id, 'cozy-cabin');
      expect(next.icons.pack.id, base.icons.pack.id);
      expect(next.clock.fontId, base.clock.fontId);
      expect(next.wallpaper.theme!.id, 'gold-ornaments');
      expect(next.wallpaper.variantId, 'navy');
      expect(next.wallpaper.accent!.primary.hex, '#F2B33D');
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
      expect(next.theme.id, 'cozy-cabin');
      expect(next.clock.fontId, 'creepster');
      expect(next.clock.size, ClockSize.large);
      expect(next.clock.color.hex?.hex, '#A970FF');
      expect(next.clock.places.appLabels, isTrue);
      expect(next.wallpaper.followsTheme, isTrue);
    });

    test('an icon pack, with the user\'s tile shape', () {
      final next = base.withIconPack(
        catalog.iconPack('mono-ember')!,
        at: at,
        shape: IconShape.leaf,
      );
      expect(next.icons.pack.id, 'mono-ember');
      expect(next.icons.shape, IconShape.leaf);
      expect(next.theme.id, 'cozy-cabin');
    });

    test('a stand-alone wallpaper, then back to the theme\'s own', () {
      final next = base.withWallpaper(
        WallpaperChoice.standalone(catalog.wallpaper('lanterns')!),
        at: at,
      );
      expect(next.wallpaper.wallpaper!.id, 'lanterns');
      expect(
        next
            .withWallpaper(WallpaperChoice.followTheme, at: at)
            .wallpaper
            .followsTheme,
        isTrue,
      );
    });

    test('changing variant resets the accent unless asked to keep it', () {
      final custom = Accent(
        id: 'mine-1',
        name: LocalizedText.en('Mine 1'),
        colors: const [HexColor('#FF7A1A'), HexColor('#E0245E')],
        angle: 135,
      );
      final picked = base.withAccent(custom, at: at);
      expect(picked.withVariant('snowed-in', at: at).accent.id, 'snow');
      expect(
        picked.withVariant('snowed-in', at: at, keepAccent: true).accent.id,
        'mine-1',
      );
    });

    test('fonts nothing uses any more are dropped', () {
      final a = base.withClockFont(catalog.font('pacifico')!, at: at);
      final b = a.withClockFont(catalog.font('bebas-neue')!, at: at);
      expect(a.fonts.keys, contains('pacifico'));
      expect(b.fonts.keys, isNot(contains('pacifico')));
      expect(b.fonts.keys, contains('bebas-neue'));
    });
  });

  group('saved form', () {
    test('every part survives a round trip', () {
      final look = whole('cozy-cabin', variantId: 'snowed-in')
          .apply(catalog, mockTheme('ember'), ApplyOption.wallpaperOnly, at: at)
          .withClockFont(catalog.font('padauk')!, at: at, size: ClockSize.small)
          .withIconPack(catalog.iconPack('lantern-light')!, at: at);
      expect(jsonEncode(roundTrip(look).toJson()), jsonEncode(look.toJson()));
    });

    test('a stand-alone wallpaper survives a round trip', () {
      final look = whole('quiet-ink').withWallpaper(
        WallpaperChoice.standalone(catalog.wallpaper('snowy-cabin')!),
        at: at,
      );
      expect(roundTrip(look).wallpaper.wallpaper!.id, 'snowy-cabin');
    });

    test('works without the catalog: everything is in the snapshot', () {
      final look = roundTrip(whole('festival-of-lights'));
      expect(look.festival.countdown(designDay).isAnyTime, isFalse);
      expect(look.clockFont.family, 'Caveat');
      expect(look.icons.pack.glyphs, hasLength(GlyphKeys.all.length));
    });

    test('a look from a newer app version is refused', () {
      final json = whole('ember').toJson()..['v'] = 2;
      expect(
        () => AppliedLook.fromJson(JsonReader(json)),
        throwsA(isA<CatalogFormatException>()),
      );
    });

    test('a clock with no place to show is refused', () {
      final json = whole('ember').toJson();
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
    final look = whole('cozy-cabin').apply(
      catalog,
      mockTheme('festival-of-lights'),
      ApplyOption.wallpaperOnly,
      at: at,
    );
    final assets = look.assets.map((a) => a.url).toSet();
    // Cabin's hills, the lantern garland, every icon and every font file.
    for (final a in [
      ...mockTheme('cozy-cabin').scene.assets,
      ...mockTheme('festival-of-lights').scene.assets,
      ...look.icons.pack.glyphs.values,
      for (final f in look.fonts.values) ...f.files.map((f) => f.asset),
    ]) {
      expect(assets, contains(a.url));
    }
  });
}
