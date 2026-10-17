import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/look/applied_look.dart';
import 'package:wallp/look/resolved_look.dart';
import 'package:wallp/models/phone_theme.dart';

import 'fixtures.dart';

void main() {
  final catalog = mockCatalog();
  final at = designDay;

  AppliedLook whole(String id) =>
      AppliedLook.wholeTheme(catalog, mockTheme(id), at: at);

  ResolvedLook resolve(AppliedLook look, [DateTime? now]) =>
      ResolvedLook.of(look, now ?? at);

  test('a built-in theme draws with its own painter, icons and fonts', () {
    final r = resolve(whole('halloween-night'));
    expect(r.wallpaperTheme.scene, SceneKind.halloween);
    expect(r.homeTheme.hasIconPack, isTrue);
    expect(r.homeTheme.iconStyle, SceneKind.halloween);
    expect(r.lockTheme.displayFont, 'Creepster');
    expect(r.homeTheme.bodyFont, 'Creepster');
    expect(
      r.clockColor,
      r.accent,
      reason: 'Halloween\'s clock uses the accent',
    );
    expect(r.lockTheme.event!.countdownLabel(at), '16 nights left');
    expect(r.lockTheme.eventIcon, Icons.nightlight_round);
  });

  test(
    'a dashboard theme gets a placeholder scene and plain icons, for now',
    () {
      final r = resolve(whole('spider-night'));
      expect(r.wallpaperTheme.scene, isNull);
      expect(r.homeTheme.hasIconPack, isFalse);
      expect(r.wallpaperTheme.palette.background, const Color(0xFF0B1026));
    },
  );

  test('a built-in icon pack on a dashboard theme draws painted icons', () {
    final r = resolve(
      whole('spider-night')
          .withIconPack(catalog.iconPack('gold-ornament')!, at: at),
    );
    expect(r.homeTheme.iconStyle, SceneKind.christmas);
    expect(r.homeTheme.hasIconPack, isTrue);
    // The wallpaper still has no painter.
    expect(r.wallpaperTheme.scene, isNull);
  });

  group('the clock font goes only where the user put it', () {
    final playfair = catalog.font('playfair-display')!;

    test('lock screen only', () {
      final r = resolve(
        whole('halloween-night').withClockFont(
          playfair,
          at: at,
          places: const ClockPlaces(homeClock: false),
        ),
      );
      expect(r.lockTheme.displayFont, 'Playfair Display');
      expect(r.homeTheme.displayFont, 'Creepster');
      expect(r.homeTheme.bodyFont, 'Creepster');
    });

    test('app labels only', () {
      final r = resolve(
        whole('halloween-night').withClockFont(
          playfair,
          at: at,
          places: const ClockPlaces(
            lockScreen: false,
            homeClock: false,
            appLabels: true,
          ),
        ),
      );
      expect(r.lockTheme.displayFont, 'Creepster');
      expect(r.homeTheme.displayFont, 'Creepster');
      expect(r.homeTheme.bodyFont, 'Playfair Display');
    });

    test('size and colour', () {
      final r = resolve(
        whole('halloween-night').withClockFont(
          playfair,
          at: at,
          size: ClockSize.large,
          color: ClockColor.fixed(const HexColor('#A970FF')),
        ),
      );
      expect(r.clockScale, 1.25);
      expect(r.clockColor, const Color(0xFFA970FF));
      expect(
        resolve(
          whole('halloween-night')
              .withClockFont(playfair, at: at, color: const ClockColor.text()),
        ).clockColor,
        r.lockTheme.palette.text,
      );
    });
  });

  group('wallpaper', () {
    test('wallpaper only: another theme\'s scene and accent', () {
      final look = whole('spider-night').apply(
        catalog,
        mockTheme('halloween-night'),
        ApplyOption.wallpaperOnly,
        at: at,
      );
      final r = resolve(look);
      expect(r.wallpaperTheme.id, 'halloween-night');
      expect(r.wallpaperTheme.scene, SceneKind.halloween);
      expect(r.wallpaperAccent, const Color(0xFFFF8A2A));
      // Clock and icons still Spider Night's.
      expect(r.lockTheme.displayFont, 'Bebas Neue');
    });

    test('a stand-alone wallpaper uses its own sky colours', () {
      final r = resolve(
        whole('halloween-night').withWallpaper(
          WallpaperChoice.standalone(catalog.wallpaper('web-corner')!),
          at: at,
        ),
      );
      expect(r.wallpaperTheme.id, 'web-corner');
      expect(r.wallpaperTheme.scene, isNull);
      // The bottom of its sky gradient, not Haunted Moon's palette.
      expect(r.wallpaperTheme.palette.background, const Color(0xFF3A1030));
    });

    test('a built-in stand-alone wallpaper uses its painter', () {
      final r = resolve(
        whole('spider-night').withWallpaper(
          WallpaperChoice.standalone(catalog.wallpaper('silent-night')!),
          at: at,
        ),
      );
      expect(r.wallpaperTheme.scene, SceneKind.christmas);
    });
  });

  group('countdown', () {
    test('undated collections have none', () {
      expect(resolve(whole('spider-night')).lockTheme.event, isNull);
    });

    test('says "Happy Thingyan!" on every day it runs', () {
      final look = whole('thingyan-water');
      for (final day in [13, 14, 15, 16]) {
        final now = DateTime(2027, 4, day, 9);
        expect(
          resolve(look, now).lockTheme.event!.countdownLabel(now),
          'Happy Thingyan!',
          reason: '$day April',
        );
      }
    });
  });

  test('a gradient accent draws as its first colour until Phase 6', () {
    final look = whole('halloween-night').withAccent(
      mockTheme('halloween-night').accentById('pumpkin-glow')!,
      at: at,
    );
    expect(resolve(look).accent, const Color(0xFFFFB547));
  });
}
