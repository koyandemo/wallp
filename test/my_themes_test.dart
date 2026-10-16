import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:wallp/core/date_format.dart';
import 'package:wallp/data/theme_catalog.dart';
import 'package:wallp/services/my_themes.dart';
import 'package:wallp/services/theme_prefs.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  final halloween = ThemeCatalog.byId('halloween-night')!;
  final christmas = ThemeCatalog.byId('christmas-eve')!;
  final thingyan = ThemeCatalog.byId('thingyan-water')!;

  test('favourites toggle, keep catalog order and survive a reload', () async {
    final my = MyThemes();
    await my.load();
    await my.toggleFavorite(thingyan);
    await my.toggleFavorite(halloween);
    expect(my.favorites, [halloween, thingyan]);
    await my.toggleFavorite(thingyan);
    expect(my.isFavorite(thingyan), isFalse);

    final reloaded = MyThemes();
    await reloaded.load();
    expect(reloaded.favorites, [halloween]);
  });

  test('history: newest first, one per theme, capped, and saved', () async {
    final my = MyThemes();
    await my.load();
    final purple = halloween.palette.accentOptions[2];
    await my.recordApplied(halloween, halloween.palette.accent);
    await my.recordApplied(christmas, christmas.palette.accent);
    await my.recordApplied(halloween, purple);

    expect(my.history.map((e) => e.theme), [halloween, christmas]);
    expect(my.current!.accent, purple);
    expect(my.accentFor(halloween), purple);

    // wallp Home reads the same applied theme.
    final applied = await ThemePrefs().load();
    expect(applied.theme, halloween);
    expect(applied.accent, purple);

    final reloaded = MyThemes();
    await reloaded.load();
    expect(reloaded.history.map((e) => e.theme), [halloween, christmas]);
    expect(reloaded.current!.accent, purple);
    expect(
      MyThemes.historyLimit,
      greaterThanOrEqualTo(ThemeCatalog.themes.length),
    );
  });

  test('remembers the last-picked accent per theme', () async {
    final my = MyThemes();
    await my.load();
    expect(my.accentFor(thingyan), thingyan.palette.accent);
    await my.rememberAccent(thingyan, thingyan.palette.accentOptions[2]);

    final reloaded = MyThemes();
    await reloaded.load();
    expect(reloaded.accentFor(thingyan), thingyan.palette.accentOptions[2]);
  });

  test('DateFormatX.ago', () {
    final now = DateTime(2026, 10, 15, 18, 30);
    expect(DateFormatX.ago(now, now), 'Just now');
    expect(DateFormatX.ago(DateTime(2026, 10, 15, 18, 5), now), '25 min ago');
    expect(DateFormatX.ago(DateTime(2026, 10, 15, 9, 7), now), 'Today, 09:07');
    expect(DateFormatX.ago(DateTime(2026, 10, 14, 23), now), 'Yesterday');
    expect(DateFormatX.ago(DateTime(2026, 10, 10, 12), now), 'Sat 10 Oct');
  });

  group('pending apply (switching the home app to wallp)', () {
    test('wallp Home finishes a recent pending apply once', () async {
      final at = DateTime(2026, 10, 15, 20);
      final red = christmas.palette.accentOptions[1];
      await ThemePrefs().savePending(christmas, red, at: at);

      final my = MyThemes();
      final applied = await my.applyPending(
        now: at.add(const Duration(minutes: 1)),
      );

      expect(applied, christmas);
      expect(my.current!.theme, christmas);
      expect(my.current!.accent, red);
      final prefs = await ThemePrefs().load();
      expect(prefs.theme, christmas);
      expect(prefs.accent, red);
      // Taken: a second start of wallp Home applies nothing.
      expect(await MyThemes().applyPending(now: at), isNull);
    });

    test('drops a stale pending apply', () async {
      final at = DateTime(2026, 10, 15, 20);
      await ThemePrefs().savePending(
        christmas,
        christmas.palette.accent,
        at: at,
      );

      final applied = await MyThemes().applyPending(
        now: at.add(ThemePrefs.pendingMaxAge + const Duration(minutes: 1)),
      );

      expect(applied, isNull);
      expect(await ThemePrefs().takePending(now: at), isNull);
    });

    test(
      'clearPending drops it (the store finished or was declined)',
      () async {
        final my = MyThemes();
        await my.savePending(christmas, christmas.palette.accent);
        await my.clearPending();

        expect(await my.applyPending(), isNull);
      },
    );
  });
}
