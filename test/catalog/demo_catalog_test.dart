// The small catalog the app shows (assets/mock/catalog/v1): three complete
// themes and three wallpapers, for testing the app step by step, plus the
// script-made Spider Night kit (tool/seed/spider_night.dart).
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

  test('Spider Night is live, with downloaded icons and scene pictures', () {
    final theme = catalog.theme('spider-night')!;
    expect(theme.isBuiltIn, isFalse);
    expect(theme.isLive, isTrue);
    expect(theme.scene.assets, hasLength(2));
    final pack = catalog.iconPack(theme.iconPackId)!;
    expect(pack.kind, IconPackKind.images);
    expect(pack.glyphs.keys, unorderedEquals(GlyphKeys.all));
    final still = catalog.wallpapers.firstWhere((w) => w.id == 'web-corner');
    expect(still.scene!.isLive, isFalse);
  });

  test('nothing points at what was cut', () {
    expect(catalog.issues, isEmpty);
    expect(catalog.validate(), isEmpty);
    expect(catalog.banners, isNotEmpty);
  });

  test('each theme is complete: painter, icons, fonts, full file', () {
    for (final t in catalog.themes) {
      expect(
        catalog.iconPack(t.iconPackId)?.kind,
        t.isBuiltIn ? IconPackKind.painted : IconPackKind.images,
        reason: t.id,
      );
      final detail = ThemeDetail.fromJson(
        JsonReader.of(_read('themes/${t.id}.${t.rev}.json'), t.id),
      );
      expect(
        catalog.assetsFor(detail),
        isNotEmpty,
        reason: 'its fonts download',
      );
      expect(detail.downloadBytes, greaterThan(0), reason: t.id);
    }
  });

  test('every file is there, with the right hash, and nothing extra', () {
    final used = <AssetRef>{
      for (final f in catalog.fonts) ...f.files.map((f) => f.asset),
      for (final p in catalog.iconPacks) ...p.glyphs.values,
      for (final t in catalog.themes) ...t.scene.assets,
      for (final w in catalog.wallpapers) ...?w.scene?.assets,
    };
    for (final ref in used) {
      final bytes = File('$_dir/${ref.url}').readAsBytesSync();
      expect(sha256.convert(bytes).toString(), ref.sha256, reason: ref.url);
    }
    final onDisk = Directory('$_dir/assets').listSync().length;
    expect(onDisk, used.length);
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
