// Writes the mock catalog under assets/mock/catalog/v1/, laid out exactly
// like the CDN (docs/theme-api.md §3), so the app's mock data source only
// swaps "where the bytes come from".
//
//   dart run tool/seed/generate.dart
//
// Fonts are fetched once from github.com/google/fonts into
// tool/seed/source/fonts/ (committed, with their licences). Icon and scene
// PNGs come from render_art_test.dart. Every run rebuilds the output folder
// from scratch, so deleted seed items never linger.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:wallp/catalog/catalog.dart';

import 'seed_data.dart';

const outDir = 'assets/mock/catalog/v1';

/// What the app ships with for a first launch with no internet: only the
/// themes its own painters draw, in the same format.
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

  final out = Directory(outDir);
  if (out.existsSync()) out.deleteSync(recursive: true);
  Directory('$outDir/assets').createSync(recursive: true);
  Directory('$outDir/themes').createSync(recursive: true);

  // Copies each source file once, named by its hash, like the CDN.
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
    final url = 'assets/$sha.${format.name}';
    File('$outDir/$url').writeAsBytesSync(bytes);
    return AssetRef(url: url, sha256: sha, bytes: bytes.length, format: format);
  });

  final fonts = buildFonts(asset);
  final iconPacks = buildIconPacks(asset);
  final wallpapers = buildWallpapers(asset);
  final drafts = buildThemes(asset);

  // Download sizes need the fonts and packs, so fill them in last.
  final lookup = Catalog(
    catalogVersion: catalogVersion,
    festivals: festivals,
    themes: [for (final t in drafts) t.toSummary()],
    wallpapers: wallpapers,
    fonts: fonts,
    banners: banners,
    iconPacks: iconPacks,
  );
  final themes = [
    for (final t in drafts)
      t.withDownloadBytes(
        lookup.assetsFor(t).fold(0, (sum, a) => sum + a.bytes),
      ),
  ];

  final catalog = Catalog(
    catalogVersion: catalogVersion,
    festivals: festivals,
    themes: [for (final t in themes) t.toSummary()],
    wallpapers: wallpapers,
    fonts: fonts,
    banners: banners,
    iconPacks: iconPacks,
    accentPresets: accentPresets,
    searchSuggestions: searchSuggestions,
  );
  final problems = catalog.validate();
  if (problems.isNotEmpty) {
    stderr.writeln('Seed has broken references:\n  ${problems.join('\n  ')}');
    exitCode = 1;
    return;
  }

  for (final t in themes) {
    _write('themes/${t.id}.${t.rev}.json', t.toJson());
  }
  final catalogFile = Manifest.fileNameFor(catalogVersion);
  final catalogBytes = _write(catalogFile, catalog.toJson());
  _write(
    'manifest.json',
    Manifest(
      schemaVersion: Manifest.supportedSchemaVersion,
      catalogVersion: catalogVersion,
      catalog: catalogFile,
      catalogSha256: sha256.convert(catalogBytes).toString(),
      minAppVersion: '1.0.0',
      publishedAt: seedDate,
    ).toJson(),
  );
  _write('engines.json', engines.toJson());
  _verify(themes.length);

  _writeBuiltIn(catalog, themes);

  final total = assets.values.fold(0, (sum, a) => sum + a.bytes);
  stdout.writeln(
    'Wrote $outDir: ${festivals.length} festivals, ${themes.length} themes '
    '(${themes.where((t) => t.isBuiltIn).length} built-in), '
    '${wallpapers.length} wallpapers, ${fonts.length} fonts, '
    '${iconPacks.length} icon packs, ${banners.length} banners, '
    '${assets.length} files (${(total / 1024 / 1024).toStringAsFixed(1)} MB).',
  );
}

List<int> _write(String path, Object json, {String dir = outDir}) {
  final bytes = utf8.encode('${_json.convert(json)}\n');
  File('$dir/$path').writeAsBytesSync(bytes);
  return bytes;
}

void _writeBuiltIn(Catalog full, List<ThemeDetail> themes) {
  final dir = Directory(builtInDir);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  Directory('$builtInDir/themes').createSync(recursive: true);

  final builtIn = Catalog(
    // Never equal to a published version, so the first refresh always
    // replaces it.
    catalogVersion: 'built-in',
    festivals: full.festivals,
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
  _write('catalog.json', builtIn.toJson(), dir: builtInDir);
  for (final t in themes.where((t) => t.isBuiltIn)) {
    _write('themes/${t.id}.${t.rev}.json', t.toJson(), dir: builtInDir);
  }
  stdout.writeln(
    'Wrote $builtInDir: ${builtIn.themes.length} themes, '
    '${builtIn.wallpapers.length} wallpapers, ${builtIn.banners.length} banners.',
  );
}

/// Reads everything back through the app's parser: if this passes, the app
/// can read the mock catalog.
void _verify(int themeCount) {
  Object? read(String path) =>
      jsonDecode(File('$outDir/$path').readAsStringSync());

  final manifest = Manifest.fromJson(
    JsonReader.of(read('manifest.json'), 'manifest'),
  );
  final catalog = Catalog.fromJson(
    JsonReader.of(read(manifest.catalog), 'catalog'),
  );
  if (catalog.issues.isNotEmpty) {
    throw StateError(
      'Catalog read back with issues:\n${catalog.issues.join('\n')}',
    );
  }
  if (catalog.themes.length != themeCount) {
    throw StateError('Lost themes on read-back');
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
