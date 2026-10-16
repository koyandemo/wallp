// The whole flow: tap Apply on a dashboard theme → its files download →
// it's applied and pinned → it keeps working with no internet.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wallp/core/clock.dart';
import 'package:wallp/data/assets/asset_cache.dart';
import 'package:wallp/data/assets/download_manager.dart';
import 'package:wallp/data/assets/downloads.dart';
import 'package:wallp/data/catalog/catalog_repository.dart';
import 'package:wallp/data/catalog/catalog_store.dart';
import 'package:wallp/data/catalog/mock_catalog_source.dart';
import 'package:wallp/look/applied_look.dart';
import 'package:wallp/look/look_controller.dart';
import 'package:wallp/look/look_store.dart';

import '../catalog/fakes.dart';
import 'fixtures.dart';

void main() {
  late Directory dir;
  late TamperingSource source;
  late CatalogRepository catalog;
  late AssetCache cache;
  late DownloadManager downloads;
  late LookController looks;
  final catalogStore = MemoryCatalogStore();

  LookController controller() => LookController(
    catalog: catalog,
    clock: FixedClock(designDay),
    prepare: (next, label) => downloads.ensure(next.assets, label: label),
    pin: cache.pin,
  );

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    dir = Directory.systemTemp.createTempSync('wallp_apply_');
    source = TamperingSource();
    catalog = CatalogRepository(source: source, store: catalogStore);
    await catalog.start(refresh: false);
    await catalog.refresh();
    // Small enough that anything unpinned gets cleaned up at once.
    cache = AssetCache(dir, limitBytes: 0);
    downloads = DownloadManager(
      source: source,
      cache: cache,
      retryDelays: const [Duration.zero],
    );
    looks = controller();
    await looks.load();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// The app's real limit: themes the user switched away from stay cached.
  Future<void> useRoomyCache() async {
    cache = AssetCache(dir);
    downloads = DownloadManager(source: source, cache: cache);
    looks = controller();
    await looks.load();
  }

  test('apply downloads everything, then applies and pins it', () async {
    final look = await looks.applyTheme('cozy-cabin');
    expect(downloads.current!.label, 'Cozy Cabin');
    expect(downloads.current!.state, DownloadState.done);
    expect(await cache.missing(look.assets), isEmpty);
    expect(await cache.pinned(), {for (final a in look.assets) a.sha256});
  });

  test('offline before downloading: nothing is applied', () async {
    source.offline = true;
    await expectLater(
      looks.applyTheme('cozy-cabin'),
      throwsA(isA<DownloadFailedException>()),
    );
    expect(looks.isApplied, isFalse);
    expect(await LookStore().saved(), isNull);
  });

  test('once downloaded, it applies and draws with no internet', () async {
    await useRoomyCache();
    await looks.applyTheme('cozy-cabin');
    await looks.applyTheme('ember');
    // Go offline; Cozy Cabin's theme file and assets were cached before.
    source.offline = true;
    source.requests.clear();
    final again = await looks.applyTheme('cozy-cabin');
    expect(again.theme.id, 'cozy-cabin');
    expect(source.requests.keys.where((p) => p.startsWith('assets/')), isEmpty);
  });

  test(
    'the applied look\'s files survive a clean-up; old ones don\'t',
    () async {
      final cabin = await looks.applyTheme('cozy-cabin');
      final ember = await looks.applyTheme('ember');
      // limitBytes is 0: everything not pinned is gone.
      expect(await cache.missing(ember.assets), isEmpty);
      final onlyCabin = cabin.assets.difference(ember.assets);
      expect(await cache.missing(onlyCabin), hasLength(onlyCabin.length));
    },
  );

  test(
    'a pending apply\'s files are kept until wallp Home finishes it',
    () async {
      await looks.applyTheme('cozy-cabin');
      final pending = await looks.applyTheme(
        'festival-of-lights',
        asPending: true,
      );
      expect(await cache.missing(pending.assets), isEmpty);
      // The applied look is still Cozy Cabin, and still pinned too.
      expect(looks.look!.theme.id, 'cozy-cabin');
      expect(await cache.missing(looks.look!.assets), isEmpty);
    },
  );

  test('a cancelled apply changes nothing, and resumes next time', () async {
    source.conditions = const NetworkConditions(bytesPerSecond: 256 * 1024);
    final apply = looks.applyTheme('festival-of-lights');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    downloads.current!.cancel();
    await expectLater(apply, throwsA(isA<DownloadCancelledException>()));
    expect(looks.isApplied, isFalse);

    source.conditions = NetworkConditions.fast;
    final look = await looks.applyTheme('festival-of-lights');
    expect(look.theme.id, 'festival-of-lights');
  });

  test('repair() re-downloads a pinned file the phone lost', () async {
    final look = await looks.applyTheme('cozy-cabin');
    final lost = look.assets.first;
    await (await cache.fileFor(lost)).delete();

    final next = controller();
    await next.load();
    await next.repair();
    expect(await cache.has(lost), isTrue);
  });

  group('Me › Downloads', () {
    test(
      'lists downloaded themes; the applied one can\'t be deleted',
      () async {
        await looks.applyTheme('cozy-cabin');
        final list = await downloadedThemes(
          catalog: catalog,
          cache: cache,
          applied: looks.look,
        );
        expect(list.map((d) => d.theme.id), ['cozy-cabin']);
        expect(list.single.isApplied, isTrue);
        expect(await deleteDownload(list.single, cache), 0);
        expect(await cache.missing(list.single.files), isEmpty);
      },
    );

    test('a theme no longer applied can be deleted', () async {
      // Room for both, so switching doesn't clean Cabin up by itself.
      await useRoomyCache();
      await looks.applyTheme('cozy-cabin');
      await looks.applyTheme('ember');

      final list = await downloadedThemes(
        catalog: catalog,
        cache: cache,
        applied: looks.look,
      );
      final cabin = list.firstWhere((d) => d.theme.id == 'cozy-cabin');
      expect(cabin.isApplied, isFalse);
      expect(await deleteDownload(cabin, cache), greaterThan(0));
      final after = await downloadedThemes(
        catalog: catalog,
        cache: cache,
        applied: looks.look,
      );
      expect(after.map((d) => d.theme.id), ['ember']);
    });
  });

  test('the size shown before Apply is what\'s actually missing', () async {
    final detail = await catalog.theme('gold-ornaments');
    final files = catalog.catalog.assetsFor(detail);
    expect(await cache.missingBytes(files), detail.downloadBytes);
    await looks.applyTheme('gold-ornaments');
    expect(await cache.missingBytes(files), 0);
  });

  test('a wallpaper-only apply downloads only that theme\'s scene', () async {
    await looks.applyTheme('ember');
    source.requests.clear();
    await looks.applyTheme('cozy-cabin', option: ApplyOption.wallpaperOnly);
    final fetched = source.requests.keys.where((p) => p.startsWith('assets/'));
    // The hills image and Cabin's fonts, not its 20 icon pictures.
    expect(fetched.length, lessThan(10));
  });
}
