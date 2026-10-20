import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/store/logic/queries.dart';

import '../look/fixtures.dart';

void main() {
  final catalog = mockCatalog();
  final now = designDay; // 15 Oct 2026

  List<String> ids(Iterable<ThemeBase> list) => [for (final t in list) t.id];

  group('badges', () {
    final spider = catalog.theme('spider-night')!; // new and live
    final haunted = catalog.theme('halloween-night')!; // old and live
    // Old and still: Spider Night as if published long ago, with its
    // particles and motion taken out.
    final still = () {
      final json =
          jsonDecode(jsonEncode(spider.toJson())) as Map<String, dynamic>;
      final layers = (json['scene'] as Map)['params']['layers'] as List;
      layers.removeWhere((l) => (l as Map)['type'] == 'particles');
      for (final l in layers.cast<Map>()) {
        l.remove('motion');
      }
      json['publishedAt'] = '2026-01-01T00:00:00.000Z';
      return ThemeSummary.fromJson(JsonReader(json));
    }();

    test('APPLIED beats NEW beats LIVE', () {
      expect(
        themeBadge(spider, appliedId: 'spider-night', now: now),
        CardBadge.applied,
      );
      expect(themeBadge(spider, now: now), CardBadge.isNew);
      expect(themeBadge(haunted, now: now), CardBadge.live);
      expect(themeBadge(still, now: now), isNull);
    });

    test('NEW wears off after 14 days', () {
      expect(
        themeBadge(spider, now: now.add(const Duration(days: 30))),
        CardBadge.live,
      );
    });

    test('wallpapers: IN USE beats LIVE', () {
      final swing = catalog.wallpaper('red-moon-swing')!;
      expect(wallpaperBadge(swing, inUseId: 'red-moon-swing'), CardBadge.inUse);
      expect(wallpaperBadge(swing), CardBadge.live);
      expect(wallpaperBadge(catalog.wallpaper('web-corner')!), isNull);
    });

    test('APP: only what the built-in catalog ships', () {
      final shipped = Catalog.fromJson(
        JsonReader.of(
          jsonDecode(
            File('assets/builtin/catalog/catalog.json').readAsStringSync(),
          ),
          'built-in',
        ),
      );
      expect(shipped.hasTheme('halloween-night'), isTrue);
      expect(shipped.hasTheme('spider-night'), isFalse);
      expect(shipped.hasWallpaper('harvest-moon'), isTrue);
      expect(shipped.hasWallpaper('red-moon-swing'), isFalse);
      expect(shipped.hasFont('creepster'), isTrue);
      expect(shipped.hasIconPack('spooky-glow'), isTrue);
      // Not read yet: no badges.
      const Catalog? none = null;
      expect(none.hasTheme('halloween-night'), isFalse);
      expect(CardBadge.app.label, 'APP');
    });
  });

  group('festivals', () {
    test('soonest first, collections last, coming soon left out', () {
      expect(
        [for (final f in festivalsBySoonest(catalog, now)) f.id],
        ['halloween', 'christmas', 'thingyan', 'heroes', 'neon'],
      );
    });

    test('a festival running today comes first', () {
      final duringThingyan = DateTime(2027, 4, 14);
      expect(festivalsBySoonest(catalog, duringThingyan).first.id, 'thingyan');
    });
  });

  group('Themes tab', () {
    List<String> tab(
      ThemesFilter filter, {
      ThemesSort sort = ThemesSort.soonest,
      Set<String> favs = const {},
    }) => ids(
      themesTab(
        catalog,
        filter: filter,
        sort: sort,
        favourites: favs,
        now: now,
      ),
    );

    test(
      'All: every theme, soonest festival first, most popular first within',
      () {
        final all = tab(ThemesFilter.all);
        expect(all, hasLength(5));
        expect(all.first, 'halloween-night');
        expect(all.last, 'neon-night', reason: 'Neon has no date');
      },
    );

    test('Myanmar: festivals tagged myanmar only', () {
      final myanmar = themesTab(
        catalog,
        filter: ThemesFilter.myanmar,
        sort: ThemesSort.soonest,
        favourites: const {},
        now: now,
      );
      expect([for (final t in myanmar) t.id], ['thingyan-water']);
    });

    test('Minimal: the undated collections', () {
      expect(tab(ThemesFilter.minimal), ['spider-night', 'neon-night']);
    });

    test('Favourites: only the ones the user hearted', () {
      expect(
        tab(ThemesFilter.favourites, favs: {'spider-night', 'christmas-eve'}),
        ['christmas-eve', 'spider-night'],
      );
      expect(tab(ThemesFilter.favourites), isEmpty);
    });

    test('A–Z sorts by name', () {
      final az = themesTab(
        catalog,
        filter: ThemesFilter.all,
        sort: ThemesSort.az,
        favourites: const {},
        now: now,
      );
      final names = [for (final t in az) t.name.en.toLowerCase()];
      expect(names, [...names]..sort());
    });
  });

  group('a festival\'s page', () {
    test('Popular: rank 1 first', () {
      expect(festivalThemes(catalog, 'christmas').first.id, 'christmas-eve');
    });

    test('New: most recently published first', () {
      expect(
        festivalThemes(
          catalog,
          'christmas',
          sort: FestivalSort.newest,
        ).first.id,
        'christmas-eve',
      );
    });

    test('style and Live chips', () {
      expect(
        ids(
          festivalThemes(
            catalog,
            'christmas',
            style: const OneStyle(ThemeStyle.classic),
          ),
        ),
        ['christmas-eve'],
      );
      expect(
        festivalThemes(
          catalog,
          'christmas',
          style: const LiveOnly(),
        ).every((t) => t.isLive),
        isTrue,
      );
    });

    test('a style with no themes is empty (the page shows a message)', () {
      expect(
        festivalThemes(
          catalog,
          'christmas',
          style: const OneStyle(ThemeStyle.minimal),
        ),
        isEmpty,
      );
    });

    test('quick look steps through and wraps around', () {
      final list = themesTab(
        catalog,
        filter: ThemesFilter.all,
        sort: ThemesSort.soonest,
        favourites: const {},
        now: now,
      );
      expect(stepThrough(list, list.first, 1).id, list[1].id);
      expect(stepThrough(list, list.last, 1).id, list.first.id);
      expect(stepThrough(list, list.first, -1).id, list.last.id);
    });
  });

  group('wallpapers, fonts, icon packs', () {
    test('wallpaper chips: Live and per festival', () {
      expect(wallpapersTab(catalog), hasLength(6));
      expect(
        wallpapersTab(catalog, filter: 'live').every((w) => w.isLive),
        isTrue,
      );
      expect(wallpapersTab(catalog, filter: 'heroes'), hasLength(2));
      expect(
        [for (final f in wallpaperFestivals(catalog, now)) f.id],
        ['halloween', 'christmas', 'thingyan', 'heroes', 'neon'],
      );
    });

    test('font chips by category', () {
      expect(fontsTab(catalog), hasLength(8));
      expect(
        [
          for (final f in fontsTab(catalog, category: FontCategory.myanmar))
            f.id,
        ],
        ['padauk'],
      );
      expect(fontsTab(catalog, category: FontCategory.display), hasLength(5));
      expect(fontsTab(catalog, category: FontCategory.handwritten), isEmpty);
    });

    test('icon pack chips: New and per festival', () {
      expect(iconPacksTab(catalog, now: now), hasLength(5));
      expect(
        [for (final p in iconPacksTab(catalog, filter: 'new', now: now)) p.id],
        ['web-slinger', 'neon-glow'],
      );
      expect(
        iconPacksTab(catalog, filter: 'christmas', now: now),
        hasLength(1),
      );
    });
  });

  group('search', () {
    test('finds themes, wallpapers and fonts by name or tag', () {
      final moon = search(catalog, 'moon');
      expect(ids(moon.themes), contains('halloween-night'));
      expect([for (final w in moon.wallpapers) w.id], contains('harvest-moon'));
      expect(moon.fonts, isEmpty);
    });

    test('a festival\'s name finds its themes', () {
      expect(ids(search(catalog, 'Heroes').themes), ['spider-night']);
    });

    test('Burmese names work too', () {
      expect(
        ids(search(catalog, 'သင်္ကြန်').themes),
        contains('thingyan-water'),
      );
    });

    test('"display" finds fonts by category; "live" finds what moves', () {
      expect(search(catalog, 'display').fonts, hasLength(5));
      final live = search(catalog, 'live');
      expect(live.themes.every((t) => t.isLive), isTrue);
      expect(live.themes, isNotEmpty);
    });

    test('blank finds nothing; nonsense finds nothing', () {
      expect(search(catalog, '   ').isEmpty, isTrue);
      expect(search(catalog, 'zzqx').total, 0);
    });

    test('recent searches: newest first, no repeats, five at most', () {
      var recent = <String>[];
      for (final q in ['moon', 'snow', 'Moon', 'a', 'b', 'c', 'd']) {
        recent = rememberSearch(recent, q);
      }
      expect(recent, ['d', 'c', 'b', 'a', 'Moon']);
      expect(rememberSearch(recent, '  '), recent);
    });
  });

  test('sizes and plurals read naturally', () {
    expect(formatBytes(786432), '768 KB');
    expect(formatBytes(2516582), '2.4 MB');
    expect(formatBytes(460000), '450 KB');
    expect(plural(1, 'theme'), '1 theme');
    expect(plural(8, 'theme'), '8 themes');
  });
}
