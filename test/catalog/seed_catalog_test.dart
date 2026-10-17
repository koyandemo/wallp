// Checks the generated mock catalog (assets/mock/catalog/v1) end to end:
// the same checks the app's download code and the dashboard's publish step
// rely on. Regenerate with `dart run tool/seed/generate.dart`.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';

const _dir = 'assets/mock/catalog/v1';

Object? _read(String path) =>
    jsonDecode(File('$_dir/$path').readAsStringSync());

void main() {
  late Manifest manifest;
  late Catalog catalog;
  late Map<String, ThemeDetail> details;

  setUpAll(() {
    manifest = Manifest.fromJson(
      JsonReader.of(_read('manifest.json'), 'manifest'),
    );
    catalog = Catalog.fromJson(
      JsonReader.of(_read(manifest.catalog), 'catalog'),
    );
    details = {
      for (final t in catalog.themes)
        t.id: ThemeDetail.fromJson(
          JsonReader.of(_read('themes/${t.id}.${t.rev}.json'), t.id),
        ),
    };
  });

  group('manifest', () {
    test('points at the catalog file and matches its hash', () {
      final bytes = File('$_dir/${manifest.catalog}').readAsBytesSync();
      expect(sha256.convert(bytes).toString(), manifest.catalogSha256);
      expect(manifest.schemaVersion, Manifest.supportedSchemaVersion);
    });

    test('the catalog stays under the app\'s 2 MB limit', () {
      expect(
        File('$_dir/${manifest.catalog}').lengthSync(),
        lessThan(2 * 1024 * 1024),
      );
    });
  });

  group('catalog', () {
    test('parses with no skipped items or broken references', () {
      expect(catalog.issues, isEmpty);
      expect(catalog.validate(), isEmpty);
    });

    test('has the design\'s theme counts per festival', () {
      int count(String id) => catalog.themesIn(id).length;
      expect(count('halloween'), 1);
      expect(count('christmas'), 1);
      expect(count('thingyan'), 1);
      expect(count('heroes'), 1);
      expect(count('neon'), 1);
      expect(catalog.themes.where((t) => t.isBuiltIn), hasLength(3));
    });

    test('coming-soon festivals have no themes', () {
      for (final f in catalog.festivals.where((f) => f.comingSoon)) {
        expect(catalog.themesIn(f.id), isEmpty, reason: f.id);
      }
    });

    test('every festival look keeps muted text readable (4.5:1)', () {
      for (final f in catalog.festivals) {
        expect(
          _contrast(f.look.muted, f.look.background),
          greaterThanOrEqualTo(4.5),
          reason: f.id,
        );
      }
    });

    test('has a live and a NEW theme to show each badge', () {
      final now = DateTime.utc(2026, 10, 15, 14);
      expect(catalog.themes.where((t) => t.isLive), isNotEmpty);
      expect(catalog.themes.where((t) => t.isNew(now)).map((t) => t.id), [
        'spider-night',
        'neon-night',
      ]);
    });

    test('banners with a window show only inside it', () {
      final now = DateTime.utc(2026, 10, 15, 14);
      expect(catalog.banners.every((b) => b.isShowing(now)), isTrue);
      final halloween = catalog.banners.firstWhere(
        (b) => b.id == 'halloween-2026',
      );
      expect(halloween.isShowing(DateTime.utc(2026, 11, 2)), isFalse);
      expect(halloween.isShowing(DateTime.utc(2026, 9, 30)), isFalse);
    });

    test('engines.json lists every engine the catalog uses', () {
      final engines = Engines.fromJson(
        JsonReader.of(_read('engines.json'), 'engines'),
      ).engines.map((e) => e.id).toSet();
      final used = {
        for (final t in catalog.themes) t.scene.engine,
        for (final w in catalog.wallpapers) ?w.scene?.engine,
        for (final p in catalog.iconPacks) ?p.painter,
      };
      expect(engines.containsAll(used), isTrue, reason: '$used');
    });
  });

  group('theme files', () {
    test('every summary is exactly what its full theme summarizes to', () {
      for (final t in catalog.themes) {
        expect(
          jsonEncode(t.toJson()),
          jsonEncode(details[t.id]!.toSummary().toJson()),
          reason: t.id,
        );
      }
    });

    test('downloadBytes is the sum of every file a whole apply needs', () {
      for (final d in details.values) {
        final assets = catalog.assetsFor(d);
        expect(
          d.downloadBytes,
          assets.fold<int>(0, (s, a) => s + a.bytes),
          reason: d.id,
        );
        expect(d.downloadBytes, greaterThan(0), reason: d.id);
      }
    });

    test('dashboard themes need downloaded icons; built-ins paint theirs', () {
      for (final d in details.values) {
        final pack = catalog.iconPackFor(d);
        expect(
          pack.kind,
          d.isBuiltIn ? IconPackKind.painted : IconPackKind.images,
          reason: d.id,
        );
      }
    });

    test('variants only point at accents the theme has', () {
      for (final d in details.values) {
        for (final v in d.variants) {
          if (v.accentId != null) {
            expect(d.accentById(v.accentId!), isNotNull, reason: d.id);
          }
        }
      }
    });

    test('related wallpapers exist', () {
      for (final d in details.values) {
        for (final id in d.wallpaperIds) {
          expect(catalog.wallpaper(id), isNotNull, reason: '${d.id} → $id');
        }
      }
    });
  });

  group('asset files', () {
    late List<AssetRef> refs;

    setUpAll(() {
      refs = {
        for (final d in details.values) ...catalog.assetsFor(d),
        for (final w in catalog.wallpapers) ...?w.scene?.assets,
        for (final f in catalog.fonts) ...f.files.map((f) => f.asset),
        for (final p in catalog.iconPacks) ...p.assets,
      }.toList();
    });

    test('every referenced file exists with the right size and hash', () {
      for (final ref in refs) {
        final file = File('$_dir/${ref.url}');
        expect(file.existsSync(), isTrue, reason: ref.url);
        final bytes = file.readAsBytesSync();
        expect(bytes.length, ref.bytes, reason: ref.url);
        expect(sha256.convert(bytes).toString(), ref.sha256, reason: ref.url);
      }
    });

    test('no file in assets/ is unused', () {
      final used = refs.map((r) => r.url).toSet();
      final onDisk = Directory('$_dir/assets')
          .listSync()
          .map((f) => 'assets/${f.uri.pathSegments.last}')
          .toSet();
      expect(onDisk.difference(used), isEmpty);
    });

    test('image packs have their background tile', () {
      for (final p in catalog.iconPacks.where(
        (p) => p.kind == IconPackKind.images,
      )) {
        expect(p.background, isNotNull, reason: p.id);
      }
    });
  });

  test('every theme file in themes/ is listed in the catalog', () {
    final listed = {for (final t in catalog.themes) '${t.id}.${t.rev}.json'};
    final onDisk = Directory('$_dir/themes')
        .listSync()
        .map((f) => f.uri.pathSegments.last)
        .toSet();
    expect(onDisk, listed);
  });
}

double _contrast(HexColor a, HexColor b) {
  double lum(HexColor c) {
    double ch(int v) {
      final x = v / 255;
      return x <= 0.03928
          ? x / 12.92
          : math.pow((x + 0.055) / 1.055, 2.4).toDouble();
    }

    final n = c.argb;
    return 0.2126 * ch((n >> 16) & 255) +
        0.7152 * ch((n >> 8) & 255) +
        0.0722 * ch(n & 255);
  }

  final x = lum(a), y = lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}
