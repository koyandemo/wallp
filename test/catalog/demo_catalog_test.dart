// What's in the catalog the app shows (assets/mock/catalog/v1): three
// complete painted themes with their wallpapers, plus the script-made
// Spider Night kit (tool/seed/spider_night.dart). seed_catalog_test.dart
// checks its files, hashes and references.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/data/catalog/catalog_repository.dart';
import 'package:wallp/data/catalog/catalog_store.dart';
import 'package:wallp/data/catalog/mock_catalog_source.dart';

const _dir = 'assets/mock/catalog/v1';

Object? _read(String path) =>
    jsonDecode(File('$_dir/$path').readAsStringSync());

void main() {
  late Catalog catalog;

  setUpAll(() {
    final manifest = Manifest.fromJson(
      JsonReader.of(_read('manifest.json'), 'manifest'),
    );
    final bytes = File('$_dir/${manifest.catalog}').readAsBytesSync();
    expect(sha256.convert(bytes).toString(), manifest.catalogSha256);
    catalog = Catalog.fromJson(
      JsonReader.of(jsonDecode(utf8.decode(bytes)), 'demo'),
    );
  });

  test('Halloween, Christmas, Thingyan and the Spider Night kit', () {
    expect(
      [for (final t in catalog.themes) t.id],
      ['halloween-night', 'christmas-eve', 'thingyan-water', 'spider-night'],
    );
    expect(
      [for (final w in catalog.wallpapers) w.id],
      [
        'harvest-moon',
        'silent-night',
        'water-splash',
        'red-moon-swing',
        'web-corner',
      ],
    );
    expect(
      [for (final f in catalog.festivals) f.id],
      ['halloween', 'christmas', 'thingyan', 'heroes'],
    );
  });

  test('Spider Night is live, with a downloaded icon tile and scene '
      'pictures', () {
    final theme = catalog.theme('spider-night')!;
    expect(theme.isBuiltIn, isFalse);
    expect(theme.isLive, isTrue);
    expect(theme.scene.assets, hasLength(2));
    final pack = catalog.iconPack(theme.iconPackId)!;
    expect(pack.kind, IconPackKind.images);
    // Just the tile: every app keeps its own logo on it.
    expect(pack.assets, [pack.background]);
    final still = catalog.wallpapers.firstWhere((w) => w.id == 'web-corner');
    expect(still.scene!.isLive, isFalse);
  });

  test('the app loads it through its own asset bundle', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final repo = CatalogRepository(
      source: MockCatalogSource(),
      store: MemoryCatalogStore(),
    );
    await repo.start(refresh: false);
    expect(await repo.refresh(), RefreshOutcome.updated);
    expect(repo.catalog.themes, hasLength(4));
    expect((await repo.theme('thingyan-water')).subtitle?.en, 'သင်္ကြန်');
  });
}
