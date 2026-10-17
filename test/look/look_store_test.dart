import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wallp/look/applied_look.dart';
import 'package:wallp/look/look_store.dart';

import 'fixtures.dart';

void main() {
  late LookStore store;
  late SharedPreferencesAsync prefs;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    prefs = SharedPreferencesAsync();
    store = LookStore();
  });

  AppliedLook look(String id) =>
      AppliedLook.wholeTheme(mockCatalog(), mockTheme(id), at: designDay);

  group('nothing applied yet', () {
    test('shows the built-in theme of the soonest festival', () async {
      expect(await store.saved(), isNull);
      expect((await store.load(now: designDay)).theme.id, 'halloween-night');
      expect(
        (await store.load(now: DateTime(2026, 11, 2))).theme.id,
        'christmas-eve',
      );
      expect(
        (await store.load(now: DateTime(2027, 2, 1))).theme.id,
        'thingyan-water',
      );
    });

    test(
      'the default isn\'t saved, so it moves on with the festivals',
      () async {
        await store.load(now: designDay);
        expect(await prefs.getString(LookStore.lookKey), isNull);
      },
    );
  });

  test('a saved look comes back exactly, in any engine', () async {
    final saved = look('spider-night')
        .withIconPack(mockCatalog().iconPack('gold-ornament')!, at: designDay);
    await store.save(saved);
    final again = await LookStore().load();
    expect(jsonEncode(again.toJson()), jsonEncode(saved.toJson()));
  });

  test('a dashboard theme keeps working without any catalog', () async {
    // Nothing but the snapshot: no mock catalog, no network.
    await store.save(look('spider-night'));
    final again = await LookStore().load();
    expect(again.theme.scene.engine, 'layers');
    expect(again.icons.pack.id, 'web-slinger');
  });

  test('a damaged save falls back to the default and is cleared', () async {
    await prefs.setString(LookStore.lookKey, '{"v": 1, "theme": 7}');
    expect((await store.load(now: designDay)).theme.id, 'halloween-night');
    expect(await prefs.getString(LookStore.lookKey), isNull);
  });

  group('moving an old save over', () {
    test('same theme, and its accent of the same colour', () async {
      await prefs.setString(LookStore.legacyThemeKey, 'christmas-eve');
      await prefs.setInt(LookStore.legacyAccentKey, 0xFFB8862E);

      final migrated = await store.saved();
      expect(migrated!.theme.id, 'christmas-eve');
      expect(migrated.accent.id, 'gold');
      expect(await prefs.getString(LookStore.legacyThemeKey), isNull);
      expect(await prefs.getInt(LookStore.legacyAccentKey), isNull);
      // Saved in the new form.
      expect(await prefs.getString(LookStore.lookKey), isNotNull);
    });

    test('a colour the theme doesn\'t offer becomes a custom accent', () async {
      await prefs.setString(LookStore.legacyThemeKey, 'halloween-night');
      await prefs.setInt(LookStore.legacyAccentKey, 0xFF123456);
      final migrated = await store.saved();
      expect(migrated!.accent.id, 'custom');
      expect(migrated.accent.primary.hex, '#123456');
    });

    test('an old ID that no longer exists is dropped', () async {
      await prefs.setString(LookStore.legacyThemeKey, 'kpop-stage');
      expect(await store.saved(), isNull);
      expect(await prefs.getString(LookStore.legacyThemeKey), isNull);
    });
  });

  group('pending apply (switching the home app)', () {
    test('a recent one is handed over once', () async {
      await store.savePending(look('spider-night'), at: designDay);
      final taken = await store.takePending(
        now: designDay.add(const Duration(minutes: 2)),
      );
      expect(taken!.theme.id, 'spider-night');
      expect(await store.takePending(now: designDay), isNull);
    });

    test('a stale one is dropped', () async {
      await store.savePending(look('spider-night'), at: designDay);
      expect(
        await store.takePending(
          now: designDay.add(
            LookStore.pendingMaxAge + const Duration(minutes: 1),
          ),
        ),
        isNull,
      );
    });

    test('one from the future (clock changed) is dropped', () async {
      await store.savePending(look('spider-night'), at: designDay);
      expect(
        await store.takePending(
          now: designDay.subtract(const Duration(hours: 1)),
        ),
        isNull,
      );
    });

    test('a damaged one is dropped', () async {
      await prefs.setString(LookStore.pendingKey, 'not json');
      expect(await store.takePending(now: designDay), isNull);
      expect(await prefs.getString(LookStore.pendingKey), isNull);
    });
  });
}
