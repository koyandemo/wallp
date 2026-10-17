import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/core/clock.dart';
import 'package:wallp/data/catalog/catalog_repository.dart';
import 'package:wallp/data/catalog/catalog_store.dart';
import 'package:wallp/look/applied_look.dart';
import 'package:wallp/look/look_controller.dart';
import 'package:wallp/look/look_store.dart';

import '../catalog/fakes.dart';
import 'fixtures.dart';

void main() {
  late TamperingSource source;
  late CatalogRepository catalog;
  late LookController looks;
  final clock = FixedClock(designDay);

  LookController controller({PrepareLook? prepare}) =>
      LookController(catalog: catalog, clock: clock, prepare: prepare);

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    source = TamperingSource();
    catalog = CatalogRepository(source: source, store: MemoryCatalogStore());
    await catalog.start(refresh: false);
    await catalog.refresh();
    looks = controller();
    await looks.load();
  });

  test('starts on the default look, with nothing applied', () {
    expect(looks.isApplied, isFalse);
    expect(looks.look!.theme.id, 'halloween-night');
  });

  test('applying a whole theme saves it and tells listeners', () async {
    var notified = 0;
    looks.addListener(() => notified++);
    final look = await looks.applyTheme('christmas-eve', variantId: 'midnight');
    expect(looks.isApplied, isTrue);
    expect(looks.look, same(look));
    expect(look.palette.background.hex, '#10223D');
    expect(notified, 1);
  });

  test('each part changes on its own and the rest stays', () async {
    await looks.applyTheme('spider-night');
    await looks.applyTheme(
      'christmas-eve',
      option: ApplyOption.wallpaperOnly,
      variantId: 'midnight',
    );
    await looks.applyTheme(
      'halloween-night',
      option: ApplyOption.clockFontOnly,
    );
    final look = await looks.applyIconPack(
      'spooky-glow',
      shape: IconShape.circle,
    );

    expect(look.theme.id, 'spider-night');
    expect(look.wallpaper.theme!.id, 'christmas-eve');
    expect(look.wallpaper.variantId, 'midnight');
    expect(look.clock.fontId, 'creepster');
    expect(look.icons.pack.id, 'spooky-glow');
    expect(look.icons.shape, IconShape.circle);
  });

  test(
    'what the store applies is what wallp Home and the wallpaper read',
    () async {
      await looks.applyTheme('thingyan-water');
      await looks.applyClockFont(
        'bebas-neue',
        size: ClockSize.small,
        places: const ClockPlaces(lockScreen: false),
      );
      await looks.applyWallpaper('silent-night');

      // A separate engine: its own LookStore, no catalog, no controller.
      final seen = await LookStore().load();
      expect(jsonEncode(seen.toJson()), jsonEncode(looks.look!.toJson()));
    },
  );

  test(
    'a pending apply waits for wallp Home and changes nothing yet',
    () async {
      await looks.applyTheme('spider-night', asPending: true);
      expect(looks.isApplied, isFalse);
      expect(looks.look!.theme.id, 'halloween-night');
      final pending = await LookStore().takePending(now: designDay);
      expect(pending!.theme.id, 'spider-night');
    },
  );

  test('if preparing fails (say, a download), the old look stays', () async {
    final failing = controller(prepare: (_, _) => throw StateError('no space'));
    await failing.load();
    await expectLater(failing.applyTheme('spider-night'), throwsStateError);
    expect(failing.isApplied, isFalse);
    expect(await LookStore().saved(), isNull);
  });

  test('preparing sees the exact look about to be saved', () async {
    AppliedLook? prepared;
    final c = controller(prepare: (next, _) async => prepared = next);
    await c.load();
    final look = await c.applyTheme('christmas-eve');
    expect(prepared, same(look));
  });

  test(
    'something not in the catalog is refused, and later changes still run',
    () async {
      await expectLater(
        looks.applyWallpaper('no-such-wallpaper'),
        throwsA(isA<NotInCatalogException>()),
      );
      await expectLater(
        looks.applyIconPack('nope'),
        throwsA(isA<NotInCatalogException>()),
      );
      expect((await looks.applyTheme('spider-night')).theme.id, 'spider-night');
    },
  );

  test('a theme that can\'t load offline is refused; the look stays', () async {
    await looks.applyTheme('christmas-eve');
    source.offline = true;
    // Never opened, and not built in.
    await expectLater(
      looks.applyTheme('spider-night'),
      throwsA(isA<ThemeUnavailableException>()),
    );
    expect(looks.look!.theme.id, 'christmas-eve');
  });

  test('quick taps apply in order, none lost', () async {
    final a = looks.applyTheme('spider-night');
    final b = looks.applyIconPack('gold-ornament');
    final c = looks.applyClockFont('playfair-display');
    await Future.wait([a, b, c]);
    final look = looks.look!;
    expect(look.theme.id, 'spider-night');
    expect(look.icons.pack.id, 'gold-ornament');
    expect(look.clock.fontId, 'playfair-display');
  });
}
