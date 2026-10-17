// Writes the mock catalogs, each laid out exactly like the CDN
// (docs/theme-api.md §3), so the app's mock data source only swaps "where
// the bytes come from":
//
// * assets/mock/catalog/v1 — what the app shows and the tests check: the
//   Halloween, Christmas and Thingyan themes with their wallpapers, plus the
//   script-made kits (Spider Night, Neon Night).
// * assets/builtin/catalog — the first-launch catalog with no internet.
//
//   dart run tool/seed/generate.dart
//
// Fonts are fetched once from github.com/google/fonts into
// tool/seed/source/fonts/ (committed, with their licences). Icon and scene
// PNGs come from render_art_test.dart. Every run rebuilds the output folders
// from scratch, so deleted seed items never linger.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:wallp/catalog/catalog.dart';

import 'seed_data.dart';

const demoDir = 'assets/mock/catalog/v1';
const builtInDir = 'assets/builtin/catalog';

const _fontsRepo = 'https://raw.githubusercontent.com/google/fonts/main';
const _json = JsonEncoder.withIndent('  ');

Future<void> main() async {
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Run from the project root.');
    exitCode = 64;
    return;
  }
  await _fetchFonts();

  // Hashes each source file once; files are copied per catalog, so each
  // folder holds only what its catalog uses.
  final sources = <String, String>{}; // sha256 → source path
  final assets = <String, AssetRef>{};
  AssetRef asset(
    String sourcePath,
    AssetFormat format,
  ) => assets.putIfAbsent(sourcePath, () {
    final file = File(sourcePath);
    if (!file.existsSync()) {
      throw StateError(
        'Missing $sourcePath. Run: flutter test tool/seed/render_art_test.dart',
      );
    }
    final bytes = file.readAsBytesSync();
    final sha = sha256.convert(bytes).toString();
    sources[sha] = sourcePath;
    return AssetRef(
      url: 'assets/$sha.${format.name}',
      sha256: sha,
      bytes: bytes.length,
      format: format,
    );
  });

  final fonts = buildFonts(asset);
  final kits = [buildSpiderNight(asset), buildNeonNight(asset)];
  final drafts = [...buildThemes(), for (final k in kits) k.theme];
  Catalog catalogOf(List<ThemeDetail> themes) => Catalog(
    catalogVersion: '$catalogVersion-demo.$demoRevision',
    festivals: [...festivals, for (final k in kits) k.festival],
    themes: [for (final t in themes) t.toSummary()],
    wallpapers: [...buildWallpapers(), for (final k in kits) ...k.wallpapers],
    fonts: fonts,
    banners: [...banners, for (final k in kits) k.banner],
    iconPacks: [...buildIconPacks(), for (final k in kits) k.iconPack],
    accentPresets: accentPresets,
    searchSuggestions: searchSuggestions,
  );

  // Download sizes need the fonts and packs, so fill them in last.
  final lookup = catalogOf(drafts);
  final themes = [
    for (final t in drafts)
      t.withDownloadBytes(
        lookup.assetsFor(t).fold(0, (sum, a) => sum + a.bytes),
      ),
  ];
  final catalog = catalogOf(themes);
  final problems = catalog.validate();
  if (problems.isNotEmpty) {
    stderr.writeln('Seed has broken references:\n  ${problems.join('\n  ')}');
    exitCode = 1;
    return;
  }

  _writeCatalog(demoDir, catalog, themes, sources);
  _writeBuiltIn(catalog, themes);
}

void _writeCatalog(
  String dir,
  Catalog catalog,
  List<ThemeDetail> allThemes,
  Map<String, String> sources,
) {
  final out = Directory(dir);
  if (out.existsSync()) out.deleteSync(recursive: true);
  Directory('$dir/assets').createSync(recursive: true);
  Directory('$dir/themes').createSync(recursive: true);

  final details = [
    for (final t in allThemes)
      if (catalog.theme(t.id) != null) t,
  ];
  // Every file this catalog points at, once.
  final used = <AssetRef>{
    for (final t in details) ...catalog.assetsFor(t),
    for (final w in catalog.wallpapers) ...?w.scene?.assets,
    for (final f in catalog.fonts) ...f.files.map((f) => f.asset),
    for (final p in catalog.iconPacks) ...p.assets,
  };
  for (final ref in used) {
    File(sources[ref.sha256]!).copySync('$dir/${ref.url}');
  }

  for (final t in details) {
    _write(dir, 'themes/${t.id}.${t.rev}.json', t.toJson());
  }
  final catalogFile = Manifest.fileNameFor(catalog.catalogVersion);
  final catalogBytes = _write(dir, catalogFile, catalog.toJson());
  _write(
    dir,
    'manifest.json',
    Manifest(
      schemaVersion: Manifest.supportedSchemaVersion,
      catalogVersion: catalog.catalogVersion,
      catalog: catalogFile,
      catalogSha256: sha256.convert(catalogBytes).toString(),
      minAppVersion: '1.0.0',
      publishedAt: seedDate,
    ).toJson(),
  );
  _write(dir, 'engines.json', engines.toJson());
  _verify(dir, details.length);

  final total = used.fold(0, (sum, a) => sum + a.bytes);
  stdout.writeln(
    'Wrote $dir: ${catalog.festivals.length} festivals, '
    '${catalog.themes.length} themes, ${catalog.wallpapers.length} wallpapers, '
    '${catalog.fonts.length} fonts, ${catalog.iconPacks.length} icon packs, '
    '${catalog.banners.length} banners, ${used.length} files '
    '(${(total / 1024 / 1024).toStringAsFixed(1)} MB).',
  );
}

List<int> _write(String dir, String path, Object json) {
  final bytes = utf8.encode('${_json.convert(json)}\n');
  File('$dir/$path').writeAsBytesSync(bytes);
  return bytes;
}

void _writeBuiltIn(Catalog full, List<ThemeDetail> themes) {
  final dir = Directory(builtInDir);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  Directory('$builtInDir/themes').createSync(recursive: true);

  final builtInFestivals = {
    for (final t in full.themes)
      if (t.isBuiltIn) t.festivalId,
  };
  final builtIn = Catalog(
    // Never equal to a published version, so the first refresh always
    // replaces it.
    catalogVersion: 'built-in',
    // Only festivals with a theme here: no empty festivals offline.
    festivals: [
      for (final f in full.festivals)
        if (builtInFestivals.contains(f.id)) f,
    ],
    themes: [
      for (final t in full.themes)
        if (t.isBuiltIn) t,
    ],
    wallpapers: full.wallpapers,
    fonts: full.fonts,
    banners: full.banners,
    // Image packs need a download; offline they'd only fail.
    iconPacks: [
      for (final p in full.iconPacks)
        if (p.kind == IconPackKind.painted) p,
    ],
    accentPresets: full.accentPresets,
    searchSuggestions: full.searchSuggestions,
  ).supportedBy(EngineIds.builtIn);
  if (builtIn.validate(includeSoft: false).isNotEmpty) {
    throw StateError(
      'Built-in catalog: ${builtIn.validate(includeSoft: false)}',
    );
  }
  _write(builtInDir, 'catalog.json', builtIn.toJson());
  for (final t in themes.where((t) => t.isBuiltIn)) {
    _write(builtInDir, 'themes/${t.id}.${t.rev}.json', t.toJson());
  }
  stdout.writeln(
    'Wrote $builtInDir: ${builtIn.themes.length} themes, '
    '${builtIn.wallpapers.length} wallpapers, ${builtIn.banners.length} banners.',
  );
}

/// Reads everything back through the app's parser: if this passes, the app
/// can read the catalog.
void _verify(String dir, int themeCount) {
  Object? read(String path) =>
      jsonDecode(File('$dir/$path').readAsStringSync());

  final manifest = Manifest.fromJson(
    JsonReader.of(read('manifest.json'), 'manifest'),
  );
  final catalog = Catalog.fromJson(
    JsonReader.of(read(manifest.catalog), 'catalog'),
  );
  if (catalog.issues.isNotEmpty) {
    throw StateError(
      '$dir read back with issues:\n${catalog.issues.join('\n')}',
    );
  }
  if (catalog.themes.length != themeCount) {
    throw StateError('$dir lost themes on read-back');
  }
  for (final t in catalog.themes) {
    ThemeDetail.fromJson(
      JsonReader.of(read('themes/${t.id}.${t.rev}.json'), t.id),
    );
  }
}

Future<void> _fetchFonts() async {
  final client = HttpClient();
  try {
    for (final font in fontSources) {
      final names = [for (final (name, _, _) in font.files) name];
      final license = '${font.id}-${font.licenseFile}';
      for (final (file, repoFile) in [
        for (final n in names) (n, n),
        (license, font.licenseFile),
      ]) {
        final target = File(fontSourcePath(file));
        if (target.existsSync()) continue;
        final url =
            '$_fontsRepo/${font.repoDir}/${Uri.encodeComponent(repoFile)}';
        stdout.writeln('Fetching $url');
        final response = await (await client.getUrl(Uri.parse(url))).close();
        if (response.statusCode != 200) {
          throw HttpException(
            'HTTP ${response.statusCode}',
            uri: Uri.parse(url),
          );
        }
        await target.parent.create(recursive: true);
        await response.pipe(target.openWrite());
      }
    }
  } finally {
    client.close();
  }
}
