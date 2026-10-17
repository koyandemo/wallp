import '../json.dart';
import 'common.dart';
import 'scene.dart';

enum ThemeStyle { classic, cozy, minimal, cute }

/// A theme's colours on the lock, home and live screens.
class Palette {
  const Palette({
    required this.background,
    required this.deep,
    required this.surface,
    required this.text,
    required this.textMuted,
    this.motif,
  });

  factory Palette.fromJson(JsonReader r) => Palette(
    background: r.color('background'),
    deep: r.color('deep'),
    surface: r.color('surface'),
    text: r.color('text'),
    textMuted: r.color('textMuted'),
    motif: r.optColor('motif'),
  );

  /// Sky / backdrop.
  final HexColor background;

  /// Darkest shade: silhouettes and ground.
  final HexColor deep;

  /// Cards and icon tiles.
  final HexColor surface;
  final HexColor text;
  final HexColor textMuted;

  /// The scene's main shape (moon, tree). Defaults to [text].
  final HexColor? motif;

  Palette apply(PaletteOverride? o) => o == null
      ? this
      : Palette(
          background: o.background ?? background,
          deep: o.deep ?? deep,
          surface: o.surface ?? surface,
          text: o.text ?? text,
          textMuted: o.textMuted ?? textMuted,
          motif: o.motif ?? motif,
        );

  Map<String, Object?> toJson() => compact({
    'background': background.hex,
    'deep': deep.hex,
    'surface': surface.hex,
    'text': text.hex,
    'textMuted': textMuted.hex,
    'motif': motif?.hex,
  });
}

/// The palette fields a variant changes; the rest come from the theme.
class PaletteOverride {
  const PaletteOverride({
    this.background,
    this.deep,
    this.surface,
    this.text,
    this.textMuted,
    this.motif,
  });

  factory PaletteOverride.fromJson(JsonReader r) => PaletteOverride(
    background: r.optColor('background'),
    deep: r.optColor('deep'),
    surface: r.optColor('surface'),
    text: r.optColor('text'),
    textMuted: r.optColor('textMuted'),
    motif: r.optColor('motif'),
  );

  final HexColor? background;
  final HexColor? deep;
  final HexColor? surface;
  final HexColor? text;
  final HexColor? textMuted;
  final HexColor? motif;

  Map<String, Object?> toJson() => compact({
    'background': background?.hex,
    'deep': deep?.hex,
    'surface': surface?.hex,
    'text': text?.hex,
    'textMuted': textMuted?.hex,
    'motif': motif?.hex,
  });
}

/// A colour variant of a theme ("Midnight", "Berry").
class Variant {
  const Variant({
    required this.id,
    required this.name,
    this.palette,
    this.accentId,
  });

  factory Variant.fromJson(JsonReader r) {
    final palette = r.optObject('palette');
    return Variant(
      id: r.id('id'),
      name: r.text('name'),
      palette: palette == null ? null : PaletteOverride.fromJson(palette),
      accentId: r.optId('accentId'),
    );
  }

  final String id;
  final LocalizedText name;

  /// Null for the theme's own colours.
  final PaletteOverride? palette;

  /// The accent this variant starts with; null = the theme's first.
  final String? accentId;

  Map<String, Object?> toJson() => compact({
    'id': id,
    'name': name.toJson(),
    'palette': palette?.toJson(),
    'accentId': accentId,
  });
}

/// Font IDs from the catalog's fonts list.
class ThemeFonts {
  const ThemeFonts({
    required this.display,
    required this.body,
    required this.labels,
  });

  factory ThemeFonts.fromJson(JsonReader r) => ThemeFonts(
    display: r.id('display'),
    body: r.id('body'),
    labels: r.id('labels'),
  );

  /// Clock and headings.
  final String display;
  final String body;

  /// App names under icons on wallp Home.
  final String labels;

  Set<String> get ids => {display, body, labels};

  Map<String, Object?> toJson() => {
    'display': display,
    'body': body,
    'labels': labels,
  };
}

/// Fields shared by the catalog summary and the full theme file.
abstract class ThemeBase {
  const ThemeBase({
    required this.id,
    required this.rev,
    required this.festivalId,
    required this.name,
    required this.style,
    required this.publishedAt,
    required this.scene,
    required this.palette,
    required this.iconPackId,
    required this.downloadBytes,
    this.subtitle,
    this.tags = const [],
    this.popularity = 0,
    this.minAppVersion = '1.0.0',
    this.previewImage,
  });

  final String id;

  /// Goes up on every publish; the app re-downloads the theme file when it
  /// changes.
  final int rev;
  final String festivalId;
  final LocalizedText name;
  final LocalizedText? subtitle;
  final ThemeStyle style;
  final List<String> tags;

  /// Drives the NEW badge (published within [newFor]).
  final DateTime publishedAt;

  /// Rank, 1 = most applied. 0 = no data yet (sorts last).
  final int popularity;
  final String minAppVersion;
  final SceneSpec scene;
  final Palette palette;
  final String iconPackId;

  /// Everything a whole-theme apply downloads, before any of it is cached.
  /// The app shows it on the Apply button ("Apply · 2.4 MB").
  final int downloadBytes;

  /// Optional small picture for app versions that can't draw [scene].
  final AssetRef? previewImage;

  static const newFor = Duration(days: 14);

  bool get isLive => scene.isLive;

  /// Built-in themes are drawn by Dart painters; the rest need a download.
  bool get isBuiltIn => EngineIds.builtIn.contains(scene.engine);

  bool isNew(DateTime now) {
    final age = now.difference(publishedAt);
    return !age.isNegative && age < newFor;
  }

  /// Popularity rank for sorting: unranked themes go last.
  int get popularityRank => popularity == 0 ? 1 << 30 : popularity;
}

/// A theme as listed in the catalog: enough for cards, filters, search and
/// the festival page without downloading the full file.
class ThemeSummary extends ThemeBase {
  const ThemeSummary({
    required super.id,
    required super.rev,
    required super.festivalId,
    required super.name,
    required super.style,
    required super.publishedAt,
    required super.scene,
    required super.palette,
    required super.iconPackId,
    required super.downloadBytes,
    required this.accent,
    required this.displayFont,
    this.variantSwatches = const [],
    super.subtitle,
    super.tags,
    super.popularity,
    super.minAppVersion,
    super.previewImage,
  });

  factory ThemeSummary.fromJson(JsonReader r) => ThemeSummary(
    id: r.id('id'),
    rev: r.integer('rev'),
    festivalId: r.id('festivalId'),
    name: r.text('name'),
    subtitle: r.optText('subtitle'),
    style: r.enumValue('style', ThemeStyle.values),
    tags: r.strings('tags'),
    publishedAt: r.time('publishedAt'),
    popularity: r.integer('popularity', orElse: 0),
    minAppVersion: r.optString('minAppVersion') ?? '1.0.0',
    scene: SceneSpec.fromJson(r.object('scene')),
    palette: Palette.fromJson(r.object('palette')),
    accent: Accent.fromJson(r.object('accent')),
    displayFont: r.id('displayFont'),
    variantSwatches: r.colors('variantSwatches', required: false),
    iconPackId: r.id('iconPackId'),
    downloadBytes: r.integer('downloadBytes'),
    previewImage: _optAsset(r, 'previewImage'),
  );

  /// The default accent, for drawing cards.
  final Accent accent;
  final String displayFont;

  /// Each variant's background, for the colour dots under a card.
  final List<HexColor> variantSwatches;

  Map<String, Object?> toJson() => compact({
    'id': id,
    'rev': rev,
    'festivalId': festivalId,
    'name': name.toJson(),
    'subtitle': subtitle?.toJson(),
    'style': style.name,
    'tags': tags,
    'isLive': isLive,
    'publishedAt': publishedAt.toIso8601String(),
    'popularity': popularity,
    'minAppVersion': minAppVersion,
    'scene': scene.toJson(),
    'palette': palette.toJson(),
    'accent': accent.toJson(),
    'displayFont': displayFont,
    'variantSwatches': variantSwatches.length < 2
        ? null
        : [for (final c in variantSwatches) c.hex],
    'iconPackId': iconPackId,
    'downloadBytes': downloadBytes,
    'previewImage': previewImage?.toJson(),
  });
}

/// A theme's full definition: `themes/<id>.<rev>.json`.
class ThemeDetail extends ThemeBase {
  const ThemeDetail({
    required super.id,
    required super.rev,
    required super.festivalId,
    required super.name,
    required super.style,
    required super.publishedAt,
    required super.scene,
    required super.palette,
    required super.iconPackId,
    required super.downloadBytes,
    required this.accents,
    required this.fonts,
    this.variants = const [],
    this.accentClock = false,
    this.labelColor,
    this.eventIcon = 'event',
    this.wallpaperIds = const [],
    super.subtitle,
    super.tags,
    super.popularity,
    super.minAppVersion,
    super.previewImage,
  });

  factory ThemeDetail.fromJson(JsonReader r) {
    final accents = r.objects('accents', Accent.fromJson, required: true);
    if (accents.isEmpty) r.fail('accents', 'needs at least one accent');
    _unique(r, 'accents', accents.map((a) => a.id));
    final variants = r.objects('variants', Variant.fromJson);
    _unique(r, 'variants', variants.map((v) => v.id));
    for (final (i, v) in variants.indexed) {
      if (v.accentId != null && !accents.any((a) => a.id == v.accentId)) {
        throw CatalogFormatException(
          '${r.at('variants')}[$i].accentId',
          'no accent "${v.accentId}" in this theme',
        );
      }
    }
    return ThemeDetail(
      id: r.id('id'),
      rev: r.integer('rev'),
      festivalId: r.id('festivalId'),
      name: r.text('name'),
      subtitle: r.optText('subtitle'),
      style: r.enumValue('style', ThemeStyle.values),
      tags: r.strings('tags'),
      publishedAt: r.time('publishedAt'),
      popularity: r.integer('popularity', orElse: 0),
      minAppVersion: r.optString('minAppVersion') ?? '1.0.0',
      scene: SceneSpec.fromJson(r.object('scene')),
      palette: Palette.fromJson(r.object('palette')),
      accents: accents,
      variants: variants,
      fonts: ThemeFonts.fromJson(r.object('fonts')),
      accentClock: r.object('clock').boolean('useAccent', orElse: false),
      labelColor: r.optObject('labels')?.optColor('color'),
      eventIcon: r.optString('eventIcon') ?? 'event',
      iconPackId: r.id('iconPackId'),
      wallpaperIds: r.strings('wallpaperIds'),
      downloadBytes: r.integer('downloadBytes'),
      previewImage: _optAsset(r, 'previewImage'),
    );
  }

  /// First = default.
  final List<Accent> accents;
  final List<Variant> variants;
  final ThemeFonts fonts;

  /// Draw the lock clock in the accent instead of the text colour.
  final bool accentClock;

  /// App names on wallp Home; null = white (with a shadow), the default.
  final HexColor? labelColor;

  /// A name from the app's icon allowlist, e.g. `nightlight_round`.
  final String eventIcon;
  final List<String> wallpaperIds;

  Accent get defaultAccent => accents.first;

  Accent? accentById(String id) {
    for (final a in accents) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// The palette with [variantId]'s changes, or the theme's own.
  Palette paletteFor(String? variantId) {
    for (final v in variants) {
      if (v.id == variantId) return palette.apply(v.palette);
    }
    return palette;
  }

  /// This theme with its download size filled in, once publishing knows
  /// every file it needs (see Catalog.assetsFor).
  ThemeDetail withDownloadBytes(int bytes) => ThemeDetail(
    id: id,
    rev: rev,
    festivalId: festivalId,
    name: name,
    subtitle: subtitle,
    style: style,
    tags: tags,
    publishedAt: publishedAt,
    popularity: popularity,
    minAppVersion: minAppVersion,
    scene: scene,
    palette: palette,
    accents: accents,
    variants: variants,
    fonts: fonts,
    accentClock: accentClock,
    labelColor: labelColor,
    eventIcon: eventIcon,
    iconPackId: iconPackId,
    wallpaperIds: wallpaperIds,
    downloadBytes: bytes,
    previewImage: previewImage,
  );

  /// The catalog entry for this theme. The seed generator and the dashboard
  /// build summaries this way, so the two files can't disagree.
  ThemeSummary toSummary() => ThemeSummary(
    id: id,
    rev: rev,
    festivalId: festivalId,
    name: name,
    subtitle: subtitle,
    style: style,
    tags: tags,
    publishedAt: publishedAt,
    popularity: popularity,
    minAppVersion: minAppVersion,
    scene: scene,
    palette: palette,
    accent: defaultAccent,
    displayFont: fonts.display,
    variantSwatches: [for (final v in variants) paletteFor(v.id).background],
    iconPackId: iconPackId,
    downloadBytes: downloadBytes,
    previewImage: previewImage,
  );

  Map<String, Object?> toJson() => compact({
    'id': id,
    'rev': rev,
    'festivalId': festivalId,
    'name': name.toJson(),
    'subtitle': subtitle?.toJson(),
    'style': style.name,
    'tags': tags,
    'isLive': isLive,
    'publishedAt': publishedAt.toIso8601String(),
    'popularity': popularity,
    'minAppVersion': minAppVersion,
    'scene': scene.toJson(),
    'palette': palette.toJson(),
    'accents': [for (final a in accents) a.toJson()],
    'variants': variants.isEmpty
        ? null
        : [for (final v in variants) v.toJson()],
    'fonts': fonts.toJson(),
    'clock': {'useAccent': accentClock},
    'labels': labelColor == null ? null : {'color': labelColor!.hex},
    'eventIcon': eventIcon,
    'iconPackId': iconPackId,
    'wallpaperIds': wallpaperIds,
    'downloadBytes': downloadBytes,
    'previewImage': previewImage?.toJson(),
  });
}

AssetRef? _optAsset(JsonReader r, String key) {
  final o = r.optObject(key);
  return o == null ? null : AssetRef.fromJson(o);
}

void _unique(JsonReader r, String key, Iterable<String> ids) {
  final seen = <String>{};
  for (final id in ids) {
    if (!seen.add(id)) r.fail(key, 'duplicate ID "$id"');
  }
}
