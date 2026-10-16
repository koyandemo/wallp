import 'package:flutter_test/flutter_test.dart';

import 'package:wallp/data/theme_catalog.dart';
import 'package:wallp/models/phone_theme.dart';

void main() {
  group('ThemeEvent.daysUntil', () {
    const halloween = ThemeEvent(name: 'Halloween', month: 10, day: 31);

    test('counts days to this year\'s date', () {
      expect(halloween.daysUntil(DateTime(2026, 10, 14, 21, 30)), 17);
    });

    test('is 0 on the day itself', () {
      expect(halloween.daysUntil(DateTime(2026, 10, 31, 23, 59)), 0);
    });

    test('countdownLabel matches the design and handles 1 / 0', () {
      expect(halloween.countdownLabel(DateTime(2026, 10, 14)), '17 days left');
      const nights = ThemeEvent(
        name: 'Halloween',
        month: 10,
        day: 31,
        unit: 'night',
      );
      expect(nights.countdownLabel(DateTime(2026, 10, 14)), '17 nights left');
      expect(nights.countdownLabel(DateTime(2026, 10, 30)), '1 night left');
      expect(nights.countdownLabel(DateTime(2026, 10, 31)), 'Happy Halloween!');
    });

    test('rolls over to next year once passed', () {
      expect(halloween.nextDate(DateTime(2026, 11, 1)), DateTime(2027, 10, 31));
    });
  });

  test(
    'every theme belongs to a category that exists and is not coming soon',
    () {
      for (final theme in ThemeCatalog.themes) {
        final category = ThemeCatalog.categories.where(
          (c) => c.id == theme.categoryId,
        );
        expect(category, hasLength(1), reason: theme.id);
        expect(category.first.comingSoon, isFalse, reason: theme.id);
      }
    },
  );

  test('nextUp picks the soonest festival', () {
    expect(ThemeCatalog.nextUp(DateTime(2026, 10, 15)).id, 'halloween-night');
    expect(ThemeCatalog.nextUp(DateTime(2026, 11, 1)).id, 'christmas-eve');
    expect(ThemeCatalog.nextUp(DateTime(2027, 1, 2)).id, 'thingyan-water');
  });

  test('theme ids are unique', () {
    final ids = ThemeCatalog.themes.map((t) => t.id).toSet();
    expect(ids, hasLength(ThemeCatalog.themes.length));
  });
}
