import '../json.dart';
import 'common.dart';
import 'content.dart';
import 'festival.dart';
import 'theme.dart';

/// `manifest.json`: the only catalog file that changes in place.
class Manifest {
  const Manifest({
    required this.schemaVersion,
    required this.catalogVersion,
    required this.catalog,
    required this.catalogSha256,
    required this.minAppVersion,
    required this.publishedAt,
  });

  /// Throws [UnsupportedSchemaException] for a schema this app can't read,
  /// so the caller keeps its cached catalog instead.
  factory Manifest.fromJson(JsonReader r) {
    final schema = r.integer('schemaVersion');
    if (schema != supportedSchemaVersion) {
      throw UnsupportedSchemaException(schema);
    }
    final version = r.string('catalogVersion');
    final catalog = r.string('catalog');
    if (catalog != fileNameFor(version)) {
      r.fail('catalog', 'expected "${fileNameFor(version)}"');
    }
    return Manifest(
      schemaVersion: schema,
      catalogVersion: version,
      catalog: catalog,
      catalogSha256: r.string('catalogSha256'),
      minAppVersion: r.string('minAppVersion'),
      publishedAt: r.time('publishedAt'),
    );
  }

  static const supportedSchemaVersion = 1;

  static String fileNameFor(String catalogVersion) =>
      'catalog.$catalogVersion.json';

  final int schemaVersion;
  final String catalogVersion;

  /// The catalog file's name next to this manifest.
  final String catalog;
  final String catalogSha256;
  final String minAppVersion;
  final DateTime publishedAt;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'catalogVersion': catalogVersion,
    'catalog': catalog,
    'catalogSha256': catalogSha256,
    'minAppVersion': minAppVersion,
    'publishedAt': publishedAt.toIso8601String(),
  };
}

class UnsupportedSchemaException implements Exception {
  const UnsupportedSchemaException(this.schemaVersion);

  final int schemaVersion;

  @override
  String toString() =>
      'UnsupportedSchemaException: schema $schemaVersion, '
      'this app reads ${Manifest.supportedSchemaVersion}';
}

/// Accent choices offered on every theme's accent picker, after the theme's
/// own accents.
class AccentPresets {
  const AccentPresets({required this.solids, required this.gradients});

  factory AccentPresets.fromJson(JsonReader r) {
    final solids = r.objects('solids', Accent.fromJson, required: true);
    final gradients = r.objects('gradients', Accent.fromJson, required: true);
    if (solids.any((a) => a.type != AccentType.solid)) {
      r.fail('solids', 'every entry must be a solid colour');
    }
    if (gradients.any((a) => a.type != AccentType.gradient)) {
      r.fail('gradients', 'every entry must be a gradient');
    }
    return AccentPresets(solids: solids, gradients: gradients);
  }

  static const empty = AccentPresets(solids: [], gradients: []);

  final List<Accent> solids;
  final List<Accent> gradients;

  Map<String, Object?> toJson() => {
    'solids': [for (final a in solids) a.toJson()],
    'gradients': [for (final a in gradients) a.toJson()],
  };
}

/// `catalog.<version>.json`: everything the store lists.
class Catalog {
  Catalog({
    required this.catalogVersion,
    required this.festivals,
    required this.themes,
    required this.wallpapers,
    required this.fonts,
    required this.banners,
    required this.iconPacks,
    this.accentPresets = AccentPresets.empty,
    this.searchSuggestions = const [],
    this.issues = const [],
  });

  /// Parses leniently: a broken item is skipped and listed in [issues], so
  /// one bad theme can't take the store down. Items that point at missing
  /// festivals, fonts or packs are dropped the same way (see [validate]).
  factory Catalog.fromJson(JsonReader r) {
    final issues = <CatalogFormatException>[];
    final presets = r.optObject('accentPresets');
    final catalog = Catalog(
      catalogVersion: r.string('catalogVersion'),
      festivals: r.objectsLenient('festivals', Festival.fromJson, issues),
      themes: r.objectsLenient('themes', ThemeSummary.fromJson, issues),
      wallpapers: r.objectsLenient('wallpapers', Wallpaper.fromJson, issues),
      fonts: r.objectsLenient('fonts', CatalogFont.fromJson, issues),
      banners: r.objectsLenient('banners', Banner.fromJson, issues),
      iconPacks: r.objectsLenient('iconPacks', IconPack.fromJson, issues),
      accentPresets: presets == null
          ? AccentPresets.empty
          : AccentPresets.fromJson(presets),
      searchSuggestions: r.strings('searchSuggestions'),
      issues: issues,
    );
    return catalog._withoutBrokenReferences();
  }

  final String catalogVersion;
  final List<Festival> festivals;
  final List<ThemeSummary> themes;
  final List<Wallpaper> wallpapers;
  final List<CatalogFont> fonts;
  final List<Banner> banners;
  final List<IconPack> iconPacks;
  final AccentPresets accentPresets;

  /// "Popular searches" on the Search screen.
  final List<String> searchSuggestions;

  /// What was skipped while parsing; empty for a healthy catalog.
  final List<CatalogFormatException> issues;

  late final _festivals = {for (final f in festivals) f.id: f};
  late final _themes = {for (final t in themes) t.id: t};
  late final _wallpapers = {for (final w in wallpapers) w.id: w};
  late final _fonts = {for (final f in fonts) f.id: f};
  late final _iconPacks = {for (final p in iconPacks) p.id: p};

  Festival? festival(String id) => _festivals[id];
  ThemeSummary? theme(String id) => _themes[id];
  Wallpaper? wallpaper(String id) => _wallpapers[id];
  CatalogFont? font(String id) => _fonts[id];
  IconPack? iconPack(String id) => _iconPacks[id];

  List<ThemeSummary> themesIn(String festivalId) => [
    for (final t in themes)
      if (t.festivalId == festivalId) t,
  ];

  /// Only themes and wallpapers whose engine this app build can draw.
  /// Unknown engines are hidden, per theme-api.md §5.
  Catalog supportedBy(Set<String> engines) {
    bool ok(String engine) => engines.contains(engine);
    return filtered(
      theme: (t) => ok(t.scene.engine),
      wallpaper: (w) => w.scene == null || ok(w.scene!.engine),
      iconPack: (p) => p.painter == null || ok(p.painter!),
    );
  }

  /// Keeps only the items the tests accept, then drops whatever pointed at
  /// a removed item (a banner that opened a hidden theme).
  Catalog filtered({
    bool Function(ThemeSummary)? theme,
    bool Function(Wallpaper)? wallpaper,
    bool Function(IconPack)? iconPack,
  }) => Catalog(
    catalogVersion: catalogVersion,
    festivals: festivals,
    themes: theme == null ? themes : themes.where(theme).toList(),
    wallpapers: wallpaper == null
        ? wallpapers
        : wallpapers.where(wallpaper).toList(),
    fonts: fonts,
    banners: banners,
    iconPacks: iconPack == null
        ? iconPacks
        : iconPacks.where(iconPack).toList(),
    accentPresets: accentPresets,
    searchSuggestions: searchSuggestions,
    issues: issues,
  )._withoutBrokenReferences();

  /// Every reference that points at nothing, e.g.
  /// `themes[cozy-cabin].iconPackId: no icon pack "x"`.
  ///
  /// Publishing wants none at all. The app, reading a catalog, only acts on
  /// *hard* references (an item can't work without its target). *Soft* ones
  /// are decoration with a fallback: a festival's cover theme, a banner's
  /// art, a font's fallback for other scripts. Leave them out with
  /// [includeSoft] false.
  List<String> validate({bool includeSoft = true}) {
    final problems = <String>[];
    void check(
      String where,
      String? id,
      Object? Function(String) find,
      String what, {
      bool soft = false,
    }) {
      if (id != null && find(id) == null && (includeSoft || !soft)) {
        problems.add('$where: no $what "$id"');
      }
    }

    for (final (name, ids) in [
      ('festivals', festivals.map((f) => f.id)),
      ('themes', themes.map((t) => t.id)),
      ('wallpapers', wallpapers.map((w) => w.id)),
      ('fonts', fonts.map((f) => f.id)),
      ('banners', banners.map((b) => b.id)),
      ('iconPacks', iconPacks.map((p) => p.id)),
    ]) {
      final seen = <String>{};
      for (final id in ids) {
        if (!seen.add(id)) problems.add('$name: duplicate ID "$id"');
      }
    }
    for (final f in festivals) {
      check(
        'festivals[${f.id}].look.displayFont',
        f.look.displayFont,
        font,
        'font',
      );
      check(
        'festivals[${f.id}].coverThemeId',
        f.coverThemeId,
        theme,
        'theme',
        soft: true,
      );
    }
    for (final t in themes) {
      check('themes[${t.id}].festivalId', t.festivalId, festival, 'festival');
      check('themes[${t.id}].displayFont', t.displayFont, font, 'font');
      check('themes[${t.id}].iconPackId', t.iconPackId, iconPack, 'icon pack');
    }
    for (final w in wallpapers) {
      check(
        'wallpapers[${w.id}].festivalId',
        w.festivalId,
        festival,
        'festival',
      );
    }
    for (final p in iconPacks) {
      check(
        'iconPacks[${p.id}].festivalId',
        p.festivalId,
        festival,
        'festival',
      );
    }
    for (final f in fonts) {
      f.fallbackFor.forEach(
        (lang, id) => check(
          'fonts[${f.id}].fallbackFor.$lang',
          id,
          font,
          'font',
          soft: true,
        ),
      );
    }
    for (final b in banners) {
      check('banners[${b.id}].look.font', b.look.font, font, 'font');
      check(
        'banners[${b.id}].look.artThemeId',
        b.look.artThemeId,
        theme,
        'theme',
        soft: true,
      );
      final id = b.action.id;
      switch (b.action.type) {
        case BannerActionType.theme:
          check('banners[${b.id}].action.id', id, theme, 'theme');
        case BannerActionType.festival ||
            BannerActionType.wallpapers ||
            BannerActionType.iconPacks:
          check('banners[${b.id}].action.id', id, festival, 'festival');
        case BannerActionType.fonts || BannerActionType.url:
          break;
      }
    }
    return problems;
  }

  /// Drops items whose references are broken, recording why in [issues].
  /// Repeats, because dropping a theme can break a banner that opens it.
  Catalog _withoutBrokenReferences() {
    final problems = validate(includeSoft: false);
    final broken = <String>{};
    for (final p in problems) {
      final m = RegExp(r'^(\w+)\[([a-z0-9-]+)\]').firstMatch(p);
      if (m != null) broken.add('${m[1]}/${m[2]}');
    }
    // Duplicates can't be fixed by dropping one side; leave them to
    // validate() and the tests.
    if (broken.isEmpty) return this;
    bool keep(String list, String id) => !broken.contains('$list/$id');
    final next = Catalog(
      catalogVersion: catalogVersion,
      festivals: [
        for (final f in festivals)
          if (keep('festivals', f.id)) f,
      ],
      themes: [
        for (final t in themes)
          if (keep('themes', t.id)) t,
      ],
      wallpapers: [
        for (final w in wallpapers)
          if (keep('wallpapers', w.id)) w,
      ],
      fonts: [
        for (final f in fonts)
          if (keep('fonts', f.id)) f,
      ],
      banners: [
        for (final b in banners)
          if (keep('banners', b.id)) b,
      ],
      iconPacks: [
        for (final p in iconPacks)
          if (keep('iconPacks', p.id)) p,
      ],
      accentPresets: accentPresets,
      searchSuggestions: searchSuggestions,
      issues: [
        ...issues,
        for (final p in problems)
          if (RegExp(r'^\w+\[').hasMatch(p))
            CatalogFormatException('reference', p),
      ],
    );
    return next._withoutBrokenReferences();
  }

  /// Every file a whole-theme apply of [theme] needs on disk: its scene's
  /// images, its icon pack's pictures and its fonts. Duplicates removed.
  /// Throws [StateError] if the theme points at a font or pack that's gone.
  List<AssetRef> assetsFor(ThemeDetail theme) => {
    ...theme.scene.assets,
    ...iconPackFor(theme).assets,
    for (final id in theme.fonts.ids) ...fontFor(id).files.map((f) => f.asset),
  }.toList();

  IconPack iconPackFor(ThemeDetail theme) =>
      iconPack(theme.iconPackId) ??
      (throw StateError('${theme.id}: no icon pack "${theme.iconPackId}"'));

  CatalogFont fontFor(String id) =>
      font(id) ?? (throw StateError('no font "$id"'));

  Map<String, Object?> toJson() => {
    'catalogVersion': catalogVersion,
    'festivals': [for (final f in festivals) f.toJson()],
    'themes': [for (final t in themes) t.toJson()],
    'wallpapers': [for (final w in wallpapers) w.toJson()],
    'fonts': [for (final f in fonts) f.toJson()],
    'iconPacks': [for (final p in iconPacks) p.toJson()],
    'banners': [for (final b in banners) b.toJson()],
    'accentPresets': accentPresets.toJson(),
    'searchSuggestions': searchSuggestions,
  };
}
