import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/data/catalog/catalog_source.dart';
import 'package:wallp/data/catalog/mock_catalog_source.dart';

import 'fakes.dart';

Matcher _fails(FetchFailure failure) => throwsA(
  isA<CatalogFetchException>().having((e) => e.failure, 'failure', failure),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MockCatalogSource source(NetworkConditions c, {Random? random}) =>
      fixtureSource(conditions: () => c, random: random);

  /// The biggest file in the mock catalog (a font), so it takes many chunks.
  late String bigAsset;
  late List<int> bigBytes;

  setUpAll(() {
    final files = Directory('$mockDir/assets').listSync().cast<File>()
      ..sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
    bigAsset = 'assets/${files.first.uri.pathSegments.last}';
    bigBytes = files.first.readAsBytesSync();
  });

  test('serves the bundled files byte for byte, as the CDN would', () async {
    final bytes = await source(NetworkConditions.fast)
        .get(bigAsset, maxBytes: 10 << 20);
    expect(bytes, bigBytes);
  });

  test('streams in chunks, so downloads can show progress', () async {
    final chunks = await source(NetworkConditions.fast).open(bigAsset).toList();
    expect(chunks.length, greaterThan(10));
    expect(
      chunks.every((c) => c.length <= MockCatalogSource.chunkSize),
      isTrue,
    );
  });

  test('offline fails every request', () {
    expect(
      source(NetworkConditions.offlineNow)
          .get('manifest.json', maxBytes: 1 << 20),
      _fails(FetchFailure.offline),
    );
  });

  test('a slow network takes about as long as its speed says', () async {
    const c = NetworkConditions(bytesPerSecond: 512 * 1024);
    final watch = Stopwatch()..start();
    await source(c).get(bigAsset, maxBytes: 10 << 20);
    final expected = bigBytes.length / (512 * 1024);
    expect(
      watch.elapsedMilliseconds / 1000,
      closeTo(expected, expected * 0.5 + 0.2),
    );
  });

  test('a flaky network fails some requests, not all', () async {
    final s = source(
      const NetworkConditions(failureRate: 0.5),
      random: Random(1),
    );
    var failed = 0;
    for (var i = 0; i < 20; i++) {
      try {
        await s.get('manifest.json', maxBytes: 1 << 20);
      } on CatalogFetchException catch (e) {
        expect(e.failure, FetchFailure.server);
        expect(e.isTransient, isTrue);
        failed++;
      }
    }
    expect(failed, inInclusiveRange(4, 16));
  });

  test('a dropped connection delivers part of the file, then fails', () async {
    final received = <int>[];
    final s = source(const NetworkConditions(dropAfter: 0.4));
    await expectLater(
      s.open(bigAsset).forEach(received.addAll),
      _fails(FetchFailure.server),
    );
    expect(received.length, (bigBytes.length * 0.4).floor());
    expect(received, bigBytes.sublist(0, received.length));
  });

  test('"corrupt" damages assets so their hash check fails', () async {
    final s = source(const NetworkConditions(corrupt: true));
    final bytes = await s.get(bigAsset, maxBytes: 10 << 20);
    final expected = bigAsset.split('/').last.split('.').first;
    expect(sha256.convert(bytes).toString(), isNot(expected));
    expect(sha256.convert(bigBytes).toString(), expected);
    // Catalog JSON is left alone.
    final manifest = await s.get('manifest.json', maxBytes: 1 << 20);
    expect(manifest, File('$mockDir/manifest.json').readAsBytesSync());
  });

  test('a missing file is a 404', () {
    expect(
      source(NetworkConditions.fast)
          .get('themes/nope.1.json', maxBytes: 1 << 20),
      _fails(FetchFailure.notFound),
    );
  });

  test('paths can\'t leave the catalog folder', () {
    for (final bad in ['../pubspec.yaml', '/etc/hosts', 'themes//x', 'a\\b']) {
      expect(
        () => CatalogSource.checkPath(bad),
        throwsA(isA<CatalogFetchException>()),
        reason: bad,
      );
    }
  });

  test('get() stops reading once a file is over the limit', () {
    expect(
      source(NetworkConditions.fast).get(bigAsset, maxBytes: 1024),
      _fails(FetchFailure.tooLarge),
    );
  });
}
