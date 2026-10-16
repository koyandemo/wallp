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
    final look = await looks.applyTheme('cozy-cabin', variantId: 'snowed-in');
    expect(looks.isApplied, isTrue);
    expect(looks.look, same(look));
    expect(look.palette.background.hex, '#2A3440');
    expect(notified, 1);
  });

  test('each part changes on its own and the rest stays', () async {
    await looks.applyTheme('cozy-cabin');
    await looks.applyTheme(
      'gold-ornaments',
      option: ApplyOption.wallpaperOnly,
      variantId: 'emerald',
    );
    await looks.applyTheme(
      'halloween-night',
      option: ApplyOption.clockFontOnly,
    );
    await looks.applyIconPack('quiet-line', shape: IconShape.circle);
    final preset = catalog.catalog.accentPresets.gradients.first;
    final look = await looks.setAccent(preset);

    expect(look.theme.id, 'cozy-cabin');
    expect(look.wallpaper.theme!.id, 'gold-ornaments');
    expect(look.wallpaper.variantId, 'emerald');
    expect(look.clock.fontId, 'creepster');
    expect(look.icons.pack.id, 'quiet-line');
    expect(look.icons.shape, IconShape.circle);
    expect(look.accent.id, preset.id);
  });

  test(
    'what the store applies is what wallp Home and the wallpaper read',
    () async {
      await looks.applyTheme('festival-of-lights');
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
      await looks.applyTheme('ember', asPending: true);
      expect(looks.isApplied, isFalse);
      expect(looks.look!.theme.id, 'halloween-night');
      final pending = await LookStore().takePending(now: designDay);
      expect(pending!.theme.id, 'ember');
    },
  );

  test('if preparing fails (say, a download), the old look stays', () async {
    final failing = controller(prepare: (_, _) => throw StateError('no space'));
    await failing.load();
    await expectLater(failing.applyTheme('ember'), throwsStateError);
    expect(failing.isApplied, isFalse);
    expect(await LookStore().saved(), isNull);
  });

  test('preparing sees the exact look about to be saved', () async {
    AppliedLook? prepared;
    final c = controller(prepare: (next, _) async => prepared = next);
    await c.load();
    final look = await c.applyTheme('slate');
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
      expect((await looks.applyTheme('ember')).theme.id, 'ember');
    },
  );

  test('a theme that can\'t load offline is refused; the look stays', () async {
    await looks.applyTheme('ember');
    source.offline = true;
    await expectLater(
      looks.applyTheme('gold-ornaments'),
      throwsA(isA<ThemeUnavailableException>()),
    );
    expect(looks.look!.theme.id, 'ember');
  });

  test('quick taps apply in order, none lost', () async {
    final a = looks.applyTheme('cozy-cabin');
    final b = looks.applyIconPack('mono-ember');
    final c = looks.applyClockFont('pacifico');
    await Future.wait([a, b, c]);
    final look = looks.look!;
    expect(look.theme.id, 'cozy-cabin');
    expect(look.icons.pack.id, 'mono-ember');
    expect(look.clock.fontId, 'pacifico');
  });
}
