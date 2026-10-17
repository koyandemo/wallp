import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/data/catalog/catalog_repository.dart';

const _dir = CatalogRepository.builtInDir;

void main() {
  late Catalog catalog;

  setUpAll(() {
    catalog = Catalog.fromJson(
      JsonReader.of(
        jsonDecode(File('$_dir/catalog.json').readAsStringSync()),
        'built-in',
      ),
    );
  });

  test('parses cleanly with only the themes the app paints itself', () {
    expect(catalog.issues, isEmpty);
    expect(catalog.validate(includeSoft: false), isEmpty);
    expect(catalog.themes.every((t) => t.isBuiltIn), isTrue);
    expect(catalog.themes, hasLength(3));
  });

  test('is never mistaken for a published version', () {
    expect(catalog.catalogVersion, 'built-in');
  });

  test('needs no download to browse: painted icon packs only', () {
    expect(catalog.iconPacks, isNotEmpty);
    expect(
      catalog.iconPacks.every((p) => p.kind == IconPackKind.painted),
      isTrue,
    );
    expect(
      catalog.wallpapers.every(
        (w) => EngineIds.builtIn.contains(w.scene!.engine),
      ),
      isTrue,
    );
  });

  test('only festivals that have a theme: none empty offline', () {
    expect(catalog.festivals.map((f) => f.id), [
      'halloween',
      'christmas',
      'thingyan',
    ]);
  });

  test('has a full theme file for each built-in theme', () {
    for (final t in catalog.themes) {
      final detail = ThemeDetail.fromJson(
        JsonReader.of(
          jsonDecode(
            File('$_dir/themes/${t.id}.${t.rev}.json').readAsStringSync(),
          ),
          t.id,
        ),
      );
      expect(jsonEncode(detail.toSummary().toJson()), jsonEncode(t.toJson()));
    }
  });
}
