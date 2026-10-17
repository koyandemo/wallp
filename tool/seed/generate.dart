// Writes the mock catalogs, each laid out exactly like the CDN
// (docs/theme-api.md §3), so the app's mock data source only swaps "where
// the bytes come from":
//
// * assets/mock/catalog/v1    — what the app shows: the demo catalog, three
//   complete themes (Halloween, Christmas, Thingyan) and three wallpapers,
//   for testing the app step by step.
// * test/fixtures/catalog/v1  — the full catalog (30 themes, dashboard-made
//   themes, downloaded icon packs) that the tests check every feature with.
// * assets/builtin/catalog    — the first-launch catalog with no internet.
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
const fullDir = 'test/fixtures/catalog/v1';
const builtInDir = 'assets/builtin/catalog';

/// The demo catalog's themes and wallpapers: one complete theme and one
/// wallpaper per festival, plus the Spider Night kit.
const demoThemes = {
  'halloween-night',
  'christmas-eve',
  'thingyan-water',
  spiderThemeId,
};
const demoWallpapers = {
  'harvest-moon',
  'silent-night',
  'water-splash',
  ...spiderWallpaperIds,
};

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
  final iconPacks = buildIconPacks(asset);
  final wallpapers = buildWallpapers(asset);
  final drafts = buildThemes(asset);
  // Kits go in the demo only, so the full fixture keeps the counts the
  // tests check.
  final kits = [buildSpiderNight(asset)];

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
  final kitThemes = [
    for (final k in kits)
      k.theme.withDownloadBytes(
        Catalog(
          catalogVersion: catalogVersion,
          festivals: [k.festival],
          themes: [k.theme.toSummary()],
          wallpapers: k.wallpapers,
          fonts: fonts,
          banners: const [],
          iconPacks: [k.iconPack],
        ).assetsFor(k.theme).fold(0, (sum, a) => sum + a.bytes),
      ),
  ];

  final full = Catalog(
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
  final problems = full.validate();
  if (problems.isNotEmpty) {
    stderr.writeln('Seed has broken references:\n  ${problems.join('\n  ')}');
    exitCode = 1;
    return;
  }

  final withKits = Catalog(
    catalogVersion: catalogVersion,
    festivals: [...festivals, for (final k in kits) k.festival],
    themes: [...full.themes, for (final t in kitThemes) t.toSummary()],
    wallpapers: [...wallpapers, for (final k in kits) ...k.wallpapers],
    fonts: fonts,
    banners: [...banners, for (final k in kits) k.banner],
    iconPacks: [...iconPacks, for (final k in kits) k.iconPack],
    accentPresets: accentPresets,
    searchSuggestions: searchSuggestions,
  );
  final kitProblems = withKits.validate();
  if (kitProblems.isNotEmpty) {
    stderr.writeln(
      'Kits have broken references:\n  ${kitProblems.join('\n  ')}',
    );
    exitCode = 1;
    return;
  }

  final allThemes = [...themes, ...kitThemes];
  _writeCatalog(fullDir, full, allThemes, sources);
  _writeCatalog(demoDir, _demo(withKits), allThemes, sources);
  _writeBuiltIn(full, themes);
}

/// The full catalog (with kits) cut down to [demoThemes] and [demoWallpapers], with
/// only the festivals, icon packs, fonts and banners they need.
Catalog _demo(Catalog full) {
  final themes = [
    for (final t in full.themes)
      if (demoThemes.contains(t.id)) t,
  ];
  final festivalIds = {for (final t in themes) t.festivalId};
  final festivals = [
    for (final f in full.festivals)
      if (festivalIds.contains(f.id)) f,
  ];
  final fontIds = <String>{
    for (final t in themes) t.displayFont,
    for (final f in festivals) f.look.displayFont,
  };
  // Body and label fonts come from the full theme files.
  for (final t in themes) {
    fontIds.addAll(_detailFonts[t.id] ?? const {});
  }
  final candidate = Catalog(
    catalogVersion: '$catalogVersion-demo.$demoRevision',
    festivals: festivals,
    themes: themes,
    wallpapers: [
      for (final w in full.wallpapers)
        if (demoWallpapers.contains(w.id)) w,
    ],
    fonts: [
      for (final f in full.fonts)
        if (fontIds.contains(f.id) || f.id == 'padauk') f,
    ],
    banners: full.banners,
    iconPacks: [
      for (final p in full.iconPacks)
        if (themes.any((t) => t.iconPackId == p.id)) p,
    ],
    accentPresets: full.accentPresets,
    searchSuggestions: const [
      'Halloween',
      'Christmas',
      'Thingyan',
      'moon',
      'snow',
      'spider',
      'live',
    ],
  );
  // Drops banners whose targets were cut (e.g. Thadingyut's).
  final demo = candidate.filtered();
  // Banner fonts must be listed too; add them, then check nothing's broken.
  final bannerFonts = {for (final b in demo.banners) b.look.font};
  final withFonts = Catalog(
    catalogVersion: demo.catalogVersion,
    festivals: demo.festivals,
    themes: demo.themes,
    wallpapers: demo.wallpapers,
    fonts: [
      for (final f in full.fonts)
        if (demo.fonts.any((d) => d.id == f.id) || bannerFonts.contains(f.id))
          f,
    ],
    banners: demo.banners,
    iconPacks: demo.iconPacks,
    accentPresets: demo.accentPresets,
    searchSuggestions: demo.searchSuggestions,
  );
  final broken = withFonts.validate(includeSoft: false);
  if (broken.isNotEmpty) throw StateError('Demo catalog: $broken');
  return withFonts;
}

/// Fonts each theme file uses (display, body, labels), filled in while
/// writing the full catalog.
final _detailFonts = <String, Set<String>>{};

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
  for (final t in allThemes) {
    _detailFonts[t.id] = t.fonts.ids;
  }

  // Every file this catalog points at, once.
  final used = <AssetRef>{
    for (final t in details) ...catalog.assetsFor(t),
    for (final w in catalog.wallpapers) ...?w.scene?.assets,
    for (final f in catalog.fonts) ...f.files.map((f) => f.asset),
    for (final p in catalog.iconPacks) ...p.glyphs.values,
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
