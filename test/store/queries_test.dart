import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/store/logic/queries.dart';

import '../look/fixtures.dart';

void main() {
  final catalog = mockCatalog();
  final now = designDay; // 15 Oct 2026

  List<String> ids(Iterable<ThemeBase> list) => [for (final t in list) t.id];

  group('badges', () {
    final cabin = catalog.theme('cozy-cabin')!; // new and still
    final ember = catalog.theme('ember')!; // old and live
    final ink = catalog.theme('quiet-ink')!; // old and still

    test('APPLIED beats NEW beats LIVE', () {
      expect(
        themeBadge(cabin, appliedId: 'cozy-cabin', now: now),
        CardBadge.applied,
      );
      expect(themeBadge(cabin, now: now), CardBadge.isNew);
      expect(themeBadge(ember, now: now), CardBadge.live);
      expect(themeBadge(ink, now: now), isNull);
    });

    test('NEW wears off after 14 days', () {
      expect(themeBadge(cabin, now: now.add(const Duration(days: 30))), isNull);
    });

    test('wallpapers: IN USE beats LIVE', () {
      final lanterns = catalog.wallpaper('lanterns')!;
      expect(wallpaperBadge(lanterns, inUseId: 'lanterns'), CardBadge.inUse);
      expect(wallpaperBadge(lanterns), CardBadge.live);
      expect(wallpaperBadge(catalog.wallpaper('quiet-ink')!), isNull);
    });
  });

  group('festivals', () {
    test('soonest first, collections last, coming soon left out', () {
      expect(
        [for (final f in festivalsBySoonest(catalog, now)) f.id],
        ['halloween', 'christmas', 'thingyan', 'thadingyut', 'minimal'],
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
        expect(all, hasLength(30));
        expect(all.first, 'halloween-night');
        expect(all.last, 'slate', reason: 'Minimal has no date');
      },
    );

    test('Myanmar: Thingyan and Thadingyut only', () {
      final myanmar = themesTab(
        catalog,
        filter: ThemesFilter.myanmar,
        sort: ThemesSort.soonest,
        favourites: const {},
        now: now,
      );
      expect(myanmar, hasLength(9));
      expect(
        {for (final t in myanmar) t.festivalId},
        {'thingyan', 'thadingyut'},
      );
    });

    test('Minimal: the undated collection', () {
      expect(
        tab(ThemesFilter.minimal),
        unorderedEquals(['quiet-ink', 'ember', 'slate']),
      );
    });

    test('Favourites: only the ones the user hearted', () {
      expect(tab(ThemesFilter.favourites, favs: {'ember', 'cozy-cabin'}), [
        'cozy-cabin',
        'ember',
      ]);
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
        'gingerbread',
      );
    });

    test('style and Live chips', () {
      expect(
        ids(
          festivalThemes(
            catalog,
            'christmas',
            style: const OneStyle(ThemeStyle.cozy),
          ),
        ),
        unorderedEquals(['cozy-cabin', 'cocoa-night']),
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
          'thadingyut',
          style: const OneStyle(ThemeStyle.minimal),
        ),
        isEmpty,
      );
    });

    test('quick look steps through and wraps around', () {
      final list = festivalThemes(catalog, 'thadingyut');
      expect(stepThrough(list, list.last, 1).id, list.first.id);
      expect(stepThrough(list, list.first, -1).id, list.last.id);
    });
  });

  group('wallpapers, fonts, icon packs', () {
    test('wallpaper chips: Live and per festival', () {
      expect(wallpapersTab(catalog), hasLength(12));
      expect(
        wallpapersTab(catalog, filter: 'live').every((w) => w.isLive),
        isTrue,
      );
      expect(wallpapersTab(catalog, filter: 'thingyan'), hasLength(3));
      expect(
        [for (final f in wallpaperFestivals(catalog, now)) f.id],
        ['halloween', 'christmas', 'thingyan', 'thadingyut', 'minimal'],
      );
    });

    test('font chips by category', () {
      expect(fontsTab(catalog), hasLength(10));
      expect(
        [
          for (final f in fontsTab(catalog, category: FontCategory.myanmar))
            f.id,
        ],
        ['padauk'],
      );
      expect(
        fontsTab(catalog, category: FontCategory.handwritten),
        hasLength(3),
      );
    });

    test('icon pack chips: New and per festival', () {
      expect(iconPacksTab(catalog, now: now), hasLength(9));
      expect([
        for (final p in iconPacksTab(catalog, filter: 'new', now: now)) p.id,
      ], unorderedEquals(['moonlit', 'candy-cane', 'lantern-light']));
      expect(iconPacksTab(catalog, filter: 'minimal', now: now), hasLength(2));
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
      expect(search(catalog, 'Thadingyut').themes, hasLength(3));
    });

    test('Burmese names work too', () {
      expect(
        ids(search(catalog, 'သင်္ကြန်').themes),
        contains('thingyan-water'),
      );
    });

    test('"handwritten" finds fonts by category; "live" finds what moves', () {
      expect(search(catalog, 'handwritten').fonts, hasLength(3));
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
