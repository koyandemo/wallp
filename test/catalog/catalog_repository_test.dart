import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/data/catalog/catalog_repository.dart';
import 'package:wallp/data/catalog/catalog_source.dart';
import 'package:wallp/data/catalog/catalog_store.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TamperingSource source;
  late MemoryCatalogStore store;

  CatalogRepository repo({
    Set<String> engines = CatalogRepository.supportedEngines,
    String appVersion = '1.0.0',
    Duration timeout = const Duration(seconds: 5),
    CatalogSource? from,
  }) => CatalogRepository(
    source: from ?? source,
    store: store,
    engines: engines,
    appVersion: appVersion,
    timeout: timeout,
  );

  setUp(() {
    source = TamperingSource();
    store = MemoryCatalogStore();
  });

  group('first launch', () {
    test('offline: shows the built-in themes and says why it failed', () async {
      source.offline = true;
      final r = repo();
      await r.start(refresh: false);
      expect(r.origin, CatalogOrigin.builtIn);
      expect(r.catalog.themes.map((t) => t.id), [
        'halloween-night',
        'christmas-eve',
        'thingyan-water',
      ]);

      expect(await r.refresh(), RefreshOutcome.failed);
      expect(r.origin, CatalogOrigin.builtIn);
      expect(
        r.lastError,
        isA<CatalogFetchException>().having(
          (e) => e.failure,
          'failure',
          FetchFailure.offline,
        ),
      );
      expect(store.files, isEmpty);
    });

    test('online: downloads the catalog and saves it', () async {
      final r = repo();
      await r.start(refresh: false);
      expect(await r.refresh(), RefreshOutcome.updated);
      expect(r.origin, CatalogOrigin.network);
      expect(r.catalog.themes, hasLength(4));
      expect(r.catalogVersion, seedManifestJson()['catalogVersion']);
      expect(r.lastError, isNull);
      expect(store.files.keys, containsAll(['manifest.json', 'catalog.json']));
    });

    test('start() refreshes in the background by default', () async {
      final r = repo();
      await r.start();
      expect(r.origin, CatalogOrigin.builtIn);
      // The refresh started by start() is the one in flight.
      expect(await r.refresh(), RefreshOutcome.updated);
      expect(source.requests['manifest.json'], 1);
    });
  });

  group('later launches', () {
    setUp(() async => repo().refresh());

    test('show the saved catalog at once, even offline', () async {
      source.offline = true;
      final r = repo();
      await r.start(refresh: false);
      expect(r.origin, CatalogOrigin.cache);
      expect(r.catalog.themes, hasLength(4));
      expect(await r.refresh(), RefreshOutcome.failed);
      expect(r.catalog.themes, hasLength(4));
    });

    test(
      'download nothing but the manifest when the version is the same',
      () async {
        final catalogFile = seedManifestJson()['catalog'] as String;
        final r = repo();
        await r.start(refresh: false);
        expect(await r.refresh(), RefreshOutcome.upToDate);
        expect(
          source.requests[catalogFile],
          1,
          reason: 'only the first launch',
        );
        expect(source.requests['manifest.json'], 2);
      },
    );

    test('pick up a newly published version', () async {
      final json = seedCatalogJson();
      (json['themes'] as List).removeWhere((t) => t['id'] == 'spider-night');
      source.publish(json, '2026-10-16.1');

      final r = repo();
      await r.start(refresh: false);
      expect(await r.refresh(), RefreshOutcome.updated);
      expect(r.catalogVersion, '2026-10-16.1');
      expect(r.catalog.theme('spider-night'), isNull);
    });

    test('a damaged saved catalog is discarded, not trusted', () async {
      final bytes = store.files['catalog.json']!;
      store.files['catalog.json'] = Uint8List.fromList(bytes)..[10] ^= 1;
      source.offline = true;

      final r = repo();
      await r.start(refresh: false);
      expect(r.origin, CatalogOrigin.builtIn);
      expect(store.files.containsKey('catalog.json'), isFalse);
    });

    test('forgetSaved() goes back to a fresh install', () async {
      final r = repo();
      await r.start(refresh: false);
      await r.theme('spider-night');
      await r.forgetSaved();
      expect(r.origin, CatalogOrigin.builtIn);
      expect(store.files, isEmpty);
    });
  });

  group('broken storage never stops the store opening', () {
    test(
      'reads and writes that throw are treated as "nothing saved"',
      () async {
        final r = CatalogRepository(source: source, store: _BrokenStore());
        await r.start(refresh: false);
        expect(r.origin, CatalogOrigin.builtIn);
        expect(await r.refresh(), RefreshOutcome.updated);
        expect(r.catalog.themes, hasLength(4));
        expect((await r.theme('spider-night')).id, 'spider-night');
        await r.forgetSaved();
      },
    );
  });

  group('a bad publish keeps the catalog on screen', () {
    late CatalogRepository r;

    setUp(() async {
      r = repo();
      await r.start(refresh: false);
      await r.refresh();
    });

    test('catalog bytes that don\'t match the manifest hash', () async {
      source.publish(seedCatalogJson(), '2026-10-16.1');
      final name = 'catalog.2026-10-16.1.json';
      source.files[name] = Uint8List.fromList(source.files[name]!)..[5] ^= 1;

      expect(await r.refresh(), RefreshOutcome.failed);
      expect(
        (r.lastError! as CatalogFetchException).failure,
        FetchFailure.integrity,
      );
      expect(r.catalog.themes, hasLength(4));
    });

    test('a catalog file whose version disagrees with the manifest', () async {
      source.publish(seedCatalogJson(), '2026-10-16.1');
      // Re-publish the same bytes under the manifest of another version.
      final json = seedCatalogJson()..['catalogVersion'] = 'something-else';
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      source.publish(seedCatalogJson(), '2026-10-16.2');
      source.files['catalog.2026-10-16.2.json'] = bytes;
      final manifest = jsonDecode(utf8.decode(source.files['manifest.json']!));
      manifest['catalogSha256'] = _sha(bytes);
      source.files['manifest.json'] = _bytes(manifest);

      expect(await r.refresh(), RefreshOutcome.failed);
      expect(r.lastError, isA<CatalogFormatException>());
      expect(r.catalogVersion, seedManifestJson()['catalogVersion']);
    });

    test('a catalog that isn\'t JSON', () async {
      source.publish(seedCatalogJson(), '2026-10-16.1');
      final bad = Uint8List.fromList(utf8.encode('<html>502</html>'));
      source.files['catalog.2026-10-16.1.json'] = bad;
      final manifest = jsonDecode(utf8.decode(source.files['manifest.json']!));
      manifest['catalogSha256'] = _sha(bad);
      source.files['manifest.json'] = _bytes(manifest);

      expect(await r.refresh(), RefreshOutcome.failed);
      expect(r.catalog.themes, hasLength(4));
    });

    test('a manifest over the size limit', () async {
      source.files['manifest.json'] = Uint8List(
        CatalogRepository.maxManifestBytes + 1,
      );
      expect(await r.refresh(), RefreshOutcome.failed);
      expect(
        (r.lastError! as CatalogFetchException).failure,
        FetchFailure.tooLarge,
      );
    });

    test('a newer schema: keep ours and suggest updating the app', () async {
      source.publish(seedCatalogJson(), '2027-01-01.1', schemaVersion: 2);
      expect(await r.refresh(), RefreshOutcome.unsupported);
      expect(r.updateRecommended, isTrue);
      expect(r.catalog.themes, hasLength(4));
    });
  });

  group('app versions', () {
    test('a manifest asking for a newer app suggests an update', () async {
      source.publish(seedCatalogJson(), '2026-10-16.1', minAppVersion: '1.4.0');
      final r = repo();
      await r.start(refresh: false);
      await r.refresh();
      expect(r.updateRecommended, isTrue);
      expect(r.catalog.themes, hasLength(4), reason: 'still usable');
    });

    test('themes that need a newer app are hidden and counted', () async {
      final json = seedCatalogJson();
      (json['themes'] as List).firstWhere(
        (t) => t['id'] == 'spider-night',
      )['minAppVersion'] = '2.0.0';
      source.publish(json, '2026-10-16.1');

      final r = repo();
      await r.start(refresh: false);
      await r.refresh();
      expect(r.catalog.theme('spider-night'), isNull);
      expect(r.hiddenForUpdate, 1);

      final newer = repo(appVersion: '2.0.0');
      await newer.start(refresh: false);
      expect(newer.catalog.theme('spider-night'), isNotNull);
      expect(newer.hiddenForUpdate, 0);
    });

    test(
      'a build without the layers engine shows only its own themes',
      () async {
        final r = repo(engines: EngineIds.builtIn);
        await r.start(refresh: false);
        await r.refresh();
        expect(r.catalog.themes.map((t) => t.id), [
          'halloween-night',
          'christmas-eve',
          'thingyan-water',
        ]);
      },
    );
  });

  group('refresh', () {
    test('calls while one is running share it', () async {
      final r = repo();
      await r.start(refresh: false);
      final a = r.refresh(), b = r.refresh();
      expect(identical(a, b), isTrue);
      await a;
      expect(source.requests['manifest.json'], 1);
    });

    test('tells listeners when it starts and ends', () async {
      final r = repo();
      await r.start(refresh: false);
      final seen = <bool>[];
      r.addListener(() => seen.add(r.isRefreshing));
      await r.refresh();
      expect(seen, [true, false]);
      expect(r.lastCheckedAt, isNotNull);
    });

    test('gives up on a server that never answers', () async {
      final r = repo(
        from: HangingSource(),
        timeout: const Duration(milliseconds: 50),
      );
      await r.start(refresh: false);
      expect(await r.refresh(), RefreshOutcome.failed);
      expect(
        (r.lastError! as CatalogFetchException).failure,
        FetchFailure.timeout,
      );
    });
  });

  group('full theme files', () {
    late CatalogRepository r;

    setUp(() async {
      r = repo();
      await r.start(refresh: false);
      await r.refresh();
    });

    test('download once, then come from memory', () async {
      final a = await r.theme('christmas-eve');
      final b = await r.theme('christmas-eve');
      expect(identical(a, b), isTrue);
      expect(a.variants, hasLength(3));
      expect(source.requests[_themeFile('christmas-eve')], 1);
      expect(r.cachedTheme('christmas-eve'), same(a));
    });

    test('two pages opening the same theme share one download', () async {
      final results = await Future.wait([
        r.theme('spider-night'),
        r.theme('spider-night'),
      ]);
      expect(identical(results[0], results[1]), isTrue);
      expect(source.requests[_themeFile('spider-night')], 1);
    });

    test('a theme opened once still opens offline next launch', () async {
      await r.theme('spider-night');
      source.offline = true;
      final next = repo();
      await next.start(refresh: false);
      final theme = await next.theme('spider-night');
      expect(theme.name.en, 'Spider Night');
    });

    test('a theme never opened can\'t open offline, and says why', () async {
      source.offline = true;
      await expectLater(
        r.theme('spider-night'),
        throwsA(
          isA<ThemeUnavailableException>().having(
            (e) => e.isOffline,
            'isOffline',
            isTrue,
          ),
        ),
      );
    });

    test('built-in themes open offline from the app itself', () async {
      source.offline = true;
      final theme = await r.theme('thingyan-water');
      expect(theme.subtitle?.en, 'သင်္ကြန်');
    });

    test('a file for the wrong theme or rev is rejected', () async {
      final file = _themeFile('spider-night');
      source.files[file] = _bytes(
        jsonDecode(
          File('$mockDir/${_themeFile('halloween-night')}').readAsStringSync(),
        ),
      );
      await expectLater(
        r.theme('spider-night'),
        throwsA(isA<ThemeUnavailableException>()),
      );
      expect(store.files.containsKey(file), isFalse);
    });

    test('an ID the catalog doesn\'t list', () async {
      await expectLater(
        r.theme('no-such-theme'),
        throwsA(
          isA<ThemeUnavailableException>().having(
            (e) => e.notListed,
            'notListed',
            isTrue,
          ),
        ),
      );
    });

    test('files for themes a new version removed are deleted', () async {
      await r.theme('spider-night');
      await r.theme('halloween-night');
      final spider = _themeFile('spider-night');
      final haunted = _themeFile('halloween-night');
      final json = seedCatalogJson();
      (json['themes'] as List).removeWhere((t) => t['id'] == 'spider-night');
      source.publish(json, '2026-10-16.1');
      await r.refresh();
      await pumpEventQueue();
      expect(store.files.containsKey(spider), isFalse);
      expect(store.files.containsKey(haunted), isTrue);
    });
  });
}

/// A theme's file in the mock catalog, at whatever rev it's on.
String _themeFile(String id) {
  final theme = (seedCatalogJson()['themes'] as List).firstWhere(
    (t) => t['id'] == id,
  );
  return 'themes/$id.${theme['rev']}.json';
}

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

Uint8List _bytes(Object? json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

/// A disk that fails at everything.
class _BrokenStore implements CatalogStore {
  @override
  Future<Uint8List?> read(String path) =>
      throw const FileSystemException('no disk');

  @override
  Future<void> write(String path, List<int> bytes) =>
      throw const FileSystemException('disk full');

  @override
  Future<void> delete(String path) =>
      throw const FileSystemException('no disk');

  @override
  Future<List<String>> list(String prefix) =>
      throw const FileSystemException('no disk');
}
