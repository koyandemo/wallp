import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/data/assets/asset_cache.dart';
import 'package:wallp/data/assets/download_manager.dart';
import 'package:wallp/data/catalog/catalog_source.dart';
import 'package:wallp/data/catalog/mock_catalog_source.dart';

import '../catalog/fakes.dart';
import '../look/fixtures.dart';

/// The mock CDN, counting requests and how many run at once, and able to
/// fail the first few requests for chosen files.
class _Source extends CatalogSource {
  NetworkConditions conditions = NetworkConditions.fast;
  late final _inner = fixtureSource(
    conditions: () => conditions,
    random: Random(7),
  );

  final requests = <String, int>{};
  final failFirst = <String, int>{};
  int running = 0, maxRunning = 0;

  @override
  Stream<List<int>> open(String path) async* {
    requests.update(path, (n) => n + 1, ifAbsent: () => 1);
    running++;
    maxRunning = max(maxRunning, running);
    try {
      final fails = failFirst[path] ?? 0;
      if (fails > 0) {
        failFirst[path] = fails - 1;
        throw CatalogFetchException(FetchFailure.server, path, 'HTTP 503');
      }
      yield* _inner.open(path);
    } finally {
      running--;
    }
  }
}

void main() {
  late Directory dir;
  late AssetCache cache;
  late _Source source;
  late List<AssetRef> cabin;

  DownloadManager manager({int parallel = 3}) => DownloadManager(
    source: source,
    cache: cache,
    parallel: parallel,
    retryDelays: const [Duration.zero, Duration.zero],
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wallp_dl_');
    cache = AssetCache(dir);
    source = _Source();
    // Cozy Cabin: hills, 20 icon pictures and two fonts (~0.75 MB).
    cabin = mockCatalog().assetsFor(mockTheme('cozy-cabin'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  int total(Iterable<AssetRef> refs) => refs.fold(0, (s, r) => s + r.bytes);

  /// Half-downloaded files left behind. (The cache's own index.json.part
  /// can exist for a moment while it saves the index: that's its safe
  /// write, not a leftover download.)
  List<String> partFiles() => [
    for (final f in dir.listSync())
      if (f.path.endsWith('.part') && !f.path.endsWith('index.json.part'))
        f.path,
  ];

  test('downloads every file, with progress that adds up', () async {
    final m = manager();
    final task = await m.start(cabin, label: 'Cozy Cabin');
    final seen = <int>[];
    task.addListener(() => seen.add(task.receivedBytes));
    await task.done;

    expect(task.state, DownloadState.done);
    expect(task.totalBytes, total(cabin));
    expect(task.receivedBytes, task.totalBytes);
    expect(task.doneFiles, cabin.length);
    expect(task.progress, 1);
    expect(seen.length, greaterThan(cabin.length), reason: 'chunk by chunk');
    expect(await cache.missing(cabin), isEmpty);
    expect(partFiles(), isEmpty);
  });

  test('files already on the phone aren\'t downloaded again', () async {
    await manager().ensure(cabin, label: 'Cozy Cabin');
    source.requests.clear();
    final task = await manager().start(cabin, label: 'Cozy Cabin');
    expect(task.state, DownloadState.done);
    expect(task.totalBytes, 0);
    expect(source.requests, isEmpty);
  });

  test('only what\'s missing counts toward the total', () async {
    final cocoa = mockCatalog().assetsFor(mockTheme('cocoa-night'));
    await manager().ensure(cabin, label: 'Cozy Cabin');
    // Cocoa Night shares the hills and the Candy Cane icons.
    final task = await manager().start(cocoa, label: 'Cocoa Night');
    final shared = cocoa.where(cabin.contains);
    expect(shared, isNotEmpty);
    expect(task.totalBytes, total(cocoa) - total(shared));
    await task.done;
  });

  test(
    'offline: fails with the sheet\'s message and keeps nothing half done',
    () async {
      source.conditions = NetworkConditions.offlineNow;
      final m = manager();
      await expectLater(
        m.ensure(cabin, label: 'Cozy Cabin'),
        throwsA(
          isA<DownloadFailedException>()
              .having((e) => e.isOffline, 'isOffline', isTrue)
              .having(
                (e) => e.message,
                'message',
                "Couldn't download Cozy Cabin. Check your connection.",
              ),
        ),
      );
      expect(m.current!.state, DownloadState.failed);
      expect(partFiles(), isEmpty);
    },
  );

  test(
    'a brief server error is retried and the download still finishes',
    () async {
      source.failFirst[cabin.first.url] = 2;
      await manager().ensure(cabin, label: 'Cozy Cabin');
      expect(source.requests[cabin.first.url], 3);
      expect(await cache.missing(cabin), isEmpty);
    },
  );

  test(
    'a file that keeps failing fails the task; the rest stay cached',
    () async {
      final broken = cabin.first;
      source.failFirst[broken.url] = 99;
      final m = manager();
      final task = await m.start(cabin, label: 'Cozy Cabin');
      await expectLater(task.done, throwsA(isA<DownloadFailedException>()));
      expect(task.receivedBytes, lessThanOrEqualTo(task.totalBytes));

      // Trying again continues where it stopped: only what's missing.
      source.failFirst.clear();
      source.requests.clear();
      final retry = await m.start(cabin, label: 'Cozy Cabin');
      await retry.done;
      expect(retry.files.length, lessThan(cabin.length));
      expect(retry.files, contains(broken));
      expect(await cache.missing(cabin), isEmpty);
    },
  );

  test('a damaged file is caught by its hash and not retried', () async {
    source.conditions = const NetworkConditions(corrupt: true);
    final m = manager();
    await expectLater(
      m.ensure(cabin, label: 'Cozy Cabin'),
      throwsA(
        isA<DownloadFailedException>().having(
          (e) => e.cause,
          'cause',
          isA<AssetCheckException>(),
        ),
      ),
    );
    expect(await cache.missing(cabin), hasLength(cabin.length));
    expect(source.requests.values.every((n) => n == 1), isTrue);
  });

  test('a connection dropped half way gives back its progress', () async {
    source.conditions = const NetworkConditions(dropAfter: 0.5);
    final m = manager(parallel: 1);
    final task = await m.start(cabin, label: 'Cozy Cabin');
    await expectLater(task.done, throwsA(isA<DownloadFailedException>()));
    // Nothing of the dropped file is counted or left on disk.
    expect(task.receivedBytes, 0);
    expect(partFiles(), isEmpty);
  });

  test('cancel stops the download; nothing half done is left', () async {
    source.conditions = const NetworkConditions(bytesPerSecond: 256 * 1024);
    final m = manager(parallel: 1);
    final task = await m.start(cabin, label: 'Cozy Cabin');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    task.cancel();
    await expectLater(task.done, throwsA(isA<DownloadCancelledException>()));
    expect(task.state, DownloadState.cancelled);
    expect(task.doneFiles, lessThan(cabin.length));
    expect(partFiles(), isEmpty);
    // Finished files are kept for next time.
    expect((await cache.missing(cabin)).length, cabin.length - task.doneFiles);
  });

  test('downloads at most [parallel] files at once', () async {
    // A little latency, so downloads overlap.
    source.conditions = const NetworkConditions(
      latency: Duration(milliseconds: 20),
    );
    await manager(parallel: 2).ensure(cabin, label: 'Cozy Cabin');
    expect(source.maxRunning, 2);
  });

  test('asking twice while it runs shares one download', () async {
    source.conditions = const NetworkConditions(bytesPerSecond: 1024 * 1024);
    final m = manager();
    final a = await m.start(cabin, label: 'Cozy Cabin');
    final b = await m.start(cabin.take(5), label: 'Cozy Cabin');
    expect(identical(a, b), isTrue);
    await a.done;
    expect(source.requests.values.every((n) => n == 1), isTrue);
  });
}
