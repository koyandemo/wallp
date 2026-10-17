import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/core/clock.dart';
import 'package:wallp/data/assets/asset_cache.dart';

/// A made-up file of [size] bytes, and its catalog reference.
(AssetRef, List<int>) fakeAsset(int seed, {int size = 1000}) {
  final bytes = List<int>.generate(size, (i) => (i * 31 + seed) & 0xFF);
  final sha = sha256.convert(bytes).toString();
  return (
    AssetRef(
      url: 'assets/$sha.png',
      sha256: sha,
      bytes: size,
      format: AssetFormat.png,
    ),
    bytes,
  );
}

void main() {
  late Directory dir;
  final clock = FixedClock(DateTime.utc(2026, 10, 15));

  AssetCache cache({int limit = AssetCache.defaultLimit}) =>
      AssetCache(dir, limitBytes: limit, clock: clock);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wallp_cache_');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  List<String> partFiles() => [
    for (final f in dir.listSync())
      // index.json.part is the index's own safe write, not a leftover.
      if (f.path.endsWith('.part') && !f.path.endsWith('index.json.part'))
        f.path,
  ];

  test('keeps a file only after its size and hash check out', () async {
    final c = cache();
    final (ref, bytes) = fakeAsset(1);
    expect(await c.has(ref), isFalse);
    await c.put(ref, bytes);
    expect(await c.has(ref), isTrue);
    expect(await (await c.fileFor(ref)).readAsBytes(), bytes);
    expect(partFiles(), isEmpty);
  });

  test('a file with the wrong bytes is refused and leaves nothing', () async {
    final c = cache();
    final (ref, bytes) = fakeAsset(1);
    final wrong = [...bytes]..[0] ^= 1;
    await expectLater(c.put(ref, wrong), throwsA(isA<AssetCheckException>()));
    expect(await c.has(ref), isFalse);
    expect(
      dir.listSync().whereType<File>().where((f) => f.path.endsWith('.png')),
      isEmpty,
    );
    expect(partFiles(), isEmpty);
  });

  test(
    'a file bigger than the catalog says is refused as it arrives',
    () async {
      final c = cache();
      final (ref, bytes) = fakeAsset(1);
      final incoming = await c.incoming(ref);
      incoming.add(bytes);
      expect(() => incoming.add([1]), throwsA(isA<AssetCheckException>()));
      await incoming.discard();
      expect(partFiles(), isEmpty);
    },
  );

  test('a file cut short is refused', () async {
    final c = cache();
    final (ref, bytes) = fakeAsset(1);
    await expectLater(
      c.put(ref, bytes.sublist(0, 500)),
      throwsA(isA<AssetCheckException>()),
    );
  });

  test('what\'s stored and pinned survives a restart', () async {
    final (a, aBytes) = fakeAsset(1);
    final (b, bBytes) = fakeAsset(2);
    final first = cache();
    await first.put(a, aBytes);
    await first.put(b, bBytes);
    await first.pin(AssetCache.appliedOwner, {a});

    final again = cache();
    expect(await again.has(a), isTrue);
    expect(await again.pinned(), {a.sha256});
    expect((await again.usage()).total, 2000);
    expect((await again.usage()).unpinned, 1000);
  });

  test('missing() and missingBytes() count only what\'s not here', () async {
    final c = cache();
    final (a, aBytes) = fakeAsset(1);
    final (b, _) = fakeAsset(2, size: 2500);
    await c.put(a, aBytes);
    expect(await c.missing([a, b, b]), [b]);
    expect(await c.missingBytes([a, b]), 2500);
  });

  group('eviction', () {
    test('drops the least recently used unpinned files first', () async {
      final c = cache(limit: 2500);
      final (a, aBytes) = fakeAsset(1);
      final (b, bBytes) = fakeAsset(2);
      final (x, xBytes) = fakeAsset(3);
      clock.moment = DateTime.utc(2026, 10, 1);
      await c.put(a, aBytes);
      clock.moment = DateTime.utc(2026, 10, 2);
      await c.put(b, bBytes);
      clock.moment = DateTime.utc(2026, 10, 3);
      await c.put(x, xBytes);
      // a was used again since, so b is now the oldest.
      clock.moment = DateTime.utc(2026, 10, 4);
      await c.touch([a]);

      await c.evict();
      expect(await c.has(b), isFalse);
      expect(await c.has(a), isTrue);
      expect(await c.has(x), isTrue);
    });

    test('never drops a pinned file, however old or big', () async {
      final c = cache(limit: 0);
      final (a, aBytes) = fakeAsset(1);
      final (b, bBytes) = fakeAsset(2);
      await c.put(a, aBytes);
      await c.put(b, bBytes);
      await c.pin(AssetCache.appliedOwner, {a});
      expect(await c.has(a), isTrue);
      expect(await c.has(b), isFalse);
    });

    test('re-pinning releases the old files to normal eviction', () async {
      final c = cache(limit: 0);
      final (a, aBytes) = fakeAsset(1);
      final (b, bBytes) = fakeAsset(2);
      await c.put(a, aBytes);
      await c.put(b, bBytes);
      await c.pin(AssetCache.pendingOwner, {b});
      await c.pin(AssetCache.appliedOwner, {a});
      expect(await c.has(b), isTrue, reason: 'a pending apply keeps it');
      await c.pin(AssetCache.appliedOwner, {b});
      await c.pin(AssetCache.pendingOwner, const {});
      expect(await c.has(a), isFalse);
      expect(await c.has(b), isTrue);
    });

    test('keep: protects files a download just fetched', () async {
      final c = cache(limit: 0);
      final (a, aBytes) = fakeAsset(1);
      await c.put(a, aBytes);
      await c.evict(keep: {a.sha256});
      expect(await c.has(a), isTrue);
    });
  });

  test('deleteUnpinned frees space but keeps pinned files', () async {
    final c = cache();
    final (a, aBytes) = fakeAsset(1);
    final (b, bBytes) = fakeAsset(2, size: 1500);
    await c.put(a, aBytes);
    await c.put(b, bBytes);
    await c.pin(AssetCache.appliedOwner, {a});
    expect(await c.deleteUnpinned([a, b]), 1500);
    expect(await c.has(a), isTrue);
    expect(await c.has(b), isFalse);
  });

  group('when things go wrong on disk', () {
    test('a file deleted behind our back counts as missing', () async {
      final c = cache();
      final (a, aBytes) = fakeAsset(1);
      await c.put(a, aBytes);
      await (await c.fileFor(a)).delete();
      expect(await c.has(a), isFalse);
    });

    test('a damaged index is rebuilt from the files on disk', () async {
      final (a, aBytes) = fakeAsset(1);
      await cache().put(a, aBytes);
      File('${dir.path}/index.json').writeAsStringSync('{"files": [');
      final again = cache();
      expect(await again.has(a), isTrue);
      // Pins are lost; the look controller pins again on launch (repair).
      expect(await again.pinned(), isEmpty);
    });

    test('verify() drops files whose bytes changed on disk', () async {
      final c = cache();
      final (a, aBytes) = fakeAsset(1);
      final (b, bBytes) = fakeAsset(2);
      await c.put(a, aBytes);
      await c.put(b, bBytes);
      final file = await c.fileFor(b);
      file.writeAsBytesSync(utf8.encode('x' * 1000));
      expect(await c.verify(), 1);
      expect(await c.has(a), isTrue);
      expect(await c.has(b), isFalse);
    });
  });
}
