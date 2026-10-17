/// What the phone looks like right now: the theme, and each part the user
/// can change on its own (wallpaper, clock font, icons, accent, variant).
///
/// Pure Dart. Every catalog object it uses is kept as a full snapshot, so
/// wallp Home and the live wallpaper (separate engines that may start with
/// no network, e.g. after a reboot) can draw it from saved data alone, and
/// a theme removed from the catalog keeps working on phones that applied it
/// (docs/theme-api.md §7.3).
library;

import '../catalog/catalog.dart';
import '../catalog/json.dart' show compact;

/// How a theme was applied from its detail page's Apply sheet.
enum ApplyOption {
  /// Wallpaper, icons, clock font and accent.
  wholeTheme,

  /// The theme's wallpaper; keep the icons and font.
  wallpaperOnly,

  /// The theme's display font as the clock font; keep everything else.
  clockFontOnly,
}

class AppliedLook {
  AppliedLook({
    required this.theme,
    required this.festival,
    required this.accent,
    required this.clock,
    required this.icons,
    required this.appliedAt,
    required Map<String, CatalogFont> fonts,
    this.variantId,
    this.wallpaper = WallpaperChoice.followTheme,
  }) : fonts = Map.unmodifiable(fonts) {
    // A look must carry every font it draws with.
    for (final id in {...theme.fonts.ids, clock.fontId, ...wallpaper.fontIds}) {
      if (!this.fonts.containsKey(id)) {
        throw ArgumentError('AppliedLook is missing font "$id"');
      }
    }
    if (variantId != null && !theme.variants.any((v) => v.id == variantId)) {
      throw ArgumentError('${theme.id} has no variant "$variantId"');
    }
  }

  /// Applying a whole theme: its wallpaper, icons, display font as the
  /// clock, and [accent] (the variant's, or the theme's first, if null).
  ///
  /// [catalog] supplies the festival, icon pack and fonts the theme names;
  /// throws [StateError] if any is missing.
  factory AppliedLook.wholeTheme(
    Catalog catalog,
    ThemeDetail theme, {
    required DateTime at,
    String? variantId,
    Accent? accent,
  }) {
    final festival =
        catalog.festival(theme.festivalId) ??
        (throw StateError('${theme.id}: no festival "${theme.festivalId}"'));
    return AppliedLook(
      theme: theme,
      festival: festival,
      variantId: variantId,
      accent: accent ?? defaultAccentFor(theme, variantId),
      clock: ClockStyle.forTheme(theme),
      icons: IconChoice(catalog.iconPackFor(theme)),
      fonts: _fontsOf(catalog, theme.fonts.ids),
      appliedAt: at,
    );
  }

  static Map<String, CatalogFont> _fontsOf(
    Catalog catalog,
    Iterable<String> ids,
  ) => {for (final id in ids) id: catalog.fontFor(id)};

  static Accent defaultAccentFor(ThemeDetail theme, String? variantId) {
    final variant = theme.variants.where((v) => v.id == variantId).firstOrNull;
    return (variant?.accentId == null
            ? null
            : theme.accentById(variant!.accentId!)) ??
        theme.defaultAccent;
  }

  factory AppliedLook.fromJson(JsonReader r) {
    final version = r.integer('v');
    if (version != schemaVersion) r.fail('v', 'unknown look version $version');
    final fontsJson = r.object('fonts');
    return AppliedLook(
      theme: ThemeDetail.fromJson(r.object('theme')),
      festival: Festival.fromJson(r.object('festival')),
      variantId: r.optId('variantId'),
      accent: Accent.fromJson(r.object('accent')),
      clock: ClockStyle.fromJson(r.object('clock')),
      icons: IconChoice.fromJson(r.object('icons')),
      wallpaper: WallpaperChoice.fromJson(r.optObject('wallpaper')),
      fonts: {
        for (final id in fontsJson.json.keys)
          id: CatalogFont.fromJson(fontsJson.object(id)),
      },
      appliedAt: r.time('appliedAt'),
    );
  }

  static const schemaVersion = 1;

  final ThemeDetail theme;

  /// The theme's festival, for its countdown.
  final Festival festival;
  final String? variantId;

  /// The user's pick: one of the theme's accents, a preset, or a custom one.
  final Accent accent;
  final ClockStyle clock;
  final IconChoice icons;
  final WallpaperChoice wallpaper;

  /// Every font this look draws with, by ID.
  final Map<String, CatalogFont> fonts;
  final DateTime appliedAt;

  /// The theme's colours with the variant's changes.
  Palette get palette => theme.paletteFor(variantId);

  CatalogFont get clockFont => fonts[clock.fontId]!;

  /// Every file this look needs on disk to draw (Phase 5 pins them):
  /// scene images, icon pictures and font files.
  Set<AssetRef> get assets => {
    ...theme.scene.assets,
    ...wallpaper.assets,
    ...icons.pack.assets,
    for (final f in fonts.values) ...f.files.map((f) => f.asset),
  };

  /// Applying [option] of [other] (a theme's detail page Apply sheet).
  AppliedLook apply(
    Catalog catalog,
    ThemeDetail other,
    ApplyOption option, {
    required DateTime at,
    String? variantId,
    Accent? accent,
  }) => switch (option) {
    ApplyOption.wholeTheme => AppliedLook.wholeTheme(
      catalog,
      other,
      at: at,
      variantId: variantId,
      accent: accent,
    ),
    ApplyOption.wallpaperOnly => withWallpaper(
      WallpaperChoice.ofTheme(
        other,
        variantId: variantId,
        accent: accent ?? defaultAccentFor(other, variantId),
      ),
      fonts: _fontsOf(catalog, other.fonts.ids),
      at: at,
    ),
    ApplyOption.clockFontOnly => withClockFont(
      catalog.fontFor(other.fonts.display),
      at: at,
    ),
  };

  /// A new wallpaper; theme, icons and font stay.
  AppliedLook withWallpaper(
    WallpaperChoice choice, {
    required DateTime at,
    Map<String, CatalogFont> fonts = const {},
  }) => _copy(wallpaper: choice, fonts: {...this.fonts, ...fonts}, at: at);

  /// A new clock font. Keeps the size, colour and places unless given.
  AppliedLook withClockFont(
    CatalogFont font, {
    required DateTime at,
    ClockSize? size,
    ClockColor? color,
    ClockPlaces? places,
  }) => _copy(
    clock: ClockStyle(
      fontId: font.id,
      size: size ?? clock.size,
      color: color ?? clock.color,
      places: places ?? clock.places,
    ),
    fonts: {...fonts, font.id: font},
    at: at,
  );

  /// A different icon pack; [shape] defaults to the pack's own. The label
  /// colour stays unless [labels] is given.
  AppliedLook withIconPack(
    IconPack pack, {
    required DateTime at,
    IconShape? shape,
    LabelColor? labels,
    LabelFont? labelFont,
  }) => _copy(
    icons: IconChoice(
      pack,
      shape: shape,
      labels: labels ?? icons.labels,
      labelFont: labelFont ?? icons.labelFont,
    ),
    at: at,
  );

  /// A new accent for the current theme (and its wallpaper, if it follows
  /// the theme).
  AppliedLook withAccent(Accent accent, {required DateTime at}) =>
      _copy(accent: accent, at: at);

  /// Another colour variant; the accent follows it unless [keepAccent].
  AppliedLook withVariant(
    String? variantId, {
    required DateTime at,
    bool keepAccent = false,
  }) => AppliedLook(
    theme: theme,
    festival: festival,
    variantId: variantId,
    accent: keepAccent ? accent : defaultAccentFor(theme, variantId),
    clock: clock,
    icons: icons,
    wallpaper: wallpaper,
    fonts: fonts,
    appliedAt: at,
  );

  AppliedLook _copy({
    required DateTime at,
    Accent? accent,
    ClockStyle? clock,
    IconChoice? icons,
    WallpaperChoice? wallpaper,
    Map<String, CatalogFont>? fonts,
  }) {
    final next = AppliedLook(
      theme: theme,
      festival: festival,
      variantId: variantId,
      accent: accent ?? this.accent,
      clock: clock ?? this.clock,
      icons: icons ?? this.icons,
      wallpaper: wallpaper ?? this.wallpaper,
      fonts: fonts ?? this.fonts,
      appliedAt: at,
    );
    return next._withoutUnusedFonts();
  }

  /// Drops fonts no part of the look uses any more, keeping saved data small.
  AppliedLook _withoutUnusedFonts() {
    final used = {...theme.fonts.ids, clock.fontId, ...wallpaper.fontIds};
    if (fonts.keys.every(used.contains)) return this;
    return AppliedLook(
      theme: theme,
      festival: festival,
      variantId: variantId,
      accent: accent,
      clock: clock,
      icons: icons,
      wallpaper: wallpaper,
      fonts: {
        for (final e in fonts.entries)
          if (used.contains(e.key)) e.key: e.value,
      },
      appliedAt: appliedAt,
    );
  }

  Map<String, Object?> toJson() => compact({
    'v': schemaVersion,
    'appliedAt': appliedAt.toUtc().toIso8601String(),
    'theme': theme.toJson(),
    'festival': festival.toJson(),
    'variantId': variantId,
    'accent': accent.toJson(),
    'clock': clock.toJson(),
    'icons': icons.toJson(),
    'wallpaper': wallpaper.toJson(),
    'fonts': {for (final e in fonts.entries) e.key: e.value.toJson()},
  });
}

enum ClockSize {
  small(0.75),
  medium(1),
  large(1.25);

  const ClockSize(this.scale);

  /// Multiplies the design's clock size (96 px at medium).
  final double scale;
}

/// The clock colour: the accent, the theme's text colour, or a fixed one.
class ClockColor {
  const ClockColor.accent() : hex = null, _text = false;
  const ClockColor.text() : hex = null, _text = true;
  const ClockColor.fixed(HexColor this.hex) : _text = false;

  factory ClockColor.fromJson(String value, String path) => switch (value) {
    'accent' => const ClockColor.accent(),
    'text' => const ClockColor.text(),
    _ when HexColor.isValid(value) => ClockColor.fixed(HexColor(value)),
    _ => throw CatalogFormatException(
      path,
      'expected accent, text or "#RRGGBB"',
    ),
  };

  final HexColor? hex;
  final bool _text;

  bool get isAccent => hex == null && !_text;
  bool get isText => _text;

  String toJson() => hex?.hex ?? (_text ? 'text' : 'accent');

  @override
  bool operator ==(Object other) =>
      other is ClockColor && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

/// Where the clock font is used (the Font detail page's switches).
class ClockPlaces {
  const ClockPlaces({
    this.lockScreen = true,
    this.homeClock = true,
    this.appLabels = false,
  }) : assert(lockScreen || homeClock || appLabels, 'at least one place');

  factory ClockPlaces.fromJson(JsonReader r) {
    final places = (
      lock: r.boolean('lockScreen'),
      home: r.boolean('homeClock'),
      labels: r.boolean('appLabels'),
    );
    if (!places.lock && !places.home && !places.labels) {
      r.fail('lockScreen', 'at least one place must be on');
    }
    return ClockPlaces(
      lockScreen: places.lock,
      homeClock: places.home,
      appLabels: places.labels,
    );
  }

  /// The lock screen clock drawn by the live wallpaper.
  final bool lockScreen;

  /// The clock above the icons on wallp Home.
  final bool homeClock;

  /// App names under icons on wallp Home.
  final bool appLabels;

  Map<String, Object?> toJson() => {
    'lockScreen': lockScreen,
    'homeClock': homeClock,
    'appLabels': appLabels,
  };

  @override
  bool operator ==(Object other) =>
      other is ClockPlaces &&
      other.lockScreen == lockScreen &&
      other.homeClock == homeClock &&
      other.appLabels == appLabels;

  @override
  int get hashCode => Object.hash(lockScreen, homeClock, appLabels);
}

class ClockStyle {
  const ClockStyle({
    required this.fontId,
    this.size = ClockSize.medium,
    this.color = const ClockColor.accent(),
    this.places = const ClockPlaces(),
  });

  /// A theme's own clock: its display font, in the accent if the theme
  /// says so, on the lock screen and wallp Home.
  factory ClockStyle.forTheme(ThemeDetail theme) => ClockStyle(
    fontId: theme.fonts.display,
    color: theme.accentClock
        ? const ClockColor.accent()
        : const ClockColor.text(),
  );

  factory ClockStyle.fromJson(JsonReader r) => ClockStyle(
    fontId: r.id('fontId'),
    size: r.enumValue('size', ClockSize.values),
    color: ClockColor.fromJson(r.string('color'), r.at('color')),
    places: ClockPlaces.fromJson(r.object('places')),
  );

  final String fontId;
  final ClockSize size;
  final ClockColor color;
  final ClockPlaces places;

  Map<String, Object?> toJson() => {
    'fontId': fontId,
    'size': size.name,
    'color': color.toJson(),
    'places': places.toJson(),
  };
}

/// The icon pack on wallp Home, the tile shape and the app name colour and
/// font the user picked.
class IconChoice {
  IconChoice(
    this.pack, {
    IconShape? shape,
    this.labels = const LabelColor.theme(),
    this.labelFont = LabelFont.theme,
  }) : shape = shape ?? pack.shape;

  factory IconChoice.fromJson(JsonReader r) => IconChoice(
    IconPack.fromJson(r.object('pack')),
    shape: r.enumValue('shape', IconShape.values),
    // Saved before label colours existed: the theme's.
    labels: switch (r.optString('labels')) {
      null => const LabelColor.theme(),
      final v => LabelColor.fromJson(v, r.at('labels')),
    },
    labelFont: r.has('labelFont')
        ? r.enumValue('labelFont', LabelFont.values)
        : LabelFont.theme,
  );

  final IconPack pack;
  final IconShape shape;
  final LabelColor labels;
  final LabelFont labelFont;

  Map<String, Object?> toJson() => {
    'pack': pack.toJson(),
    'shape': shape.name,
    'labels': labels.toJson(),
    'labelFont': labelFont.name,
  };
}

/// App names in the theme's label font, or the phone's own.
enum LabelFont { theme, system }

/// The colour of app names on wallp Home: the theme's (its `labels.color`,
/// else white), the accent, or one the user picked.
class LabelColor {
  const LabelColor.theme() : hex = null, _accent = false;
  const LabelColor.accent() : hex = null, _accent = true;
  const LabelColor.fixed(HexColor this.hex) : _accent = false;

  factory LabelColor.fromJson(String value, String path) => switch (value) {
    'theme' => const LabelColor.theme(),
    'accent' => const LabelColor.accent(),
    _ when HexColor.isValid(value) => LabelColor.fixed(HexColor(value)),
    _ => throw CatalogFormatException(
      path,
      'expected theme, accent or "#RRGGBB"',
    ),
  };

  final HexColor? hex;
  final bool _accent;

  bool get isTheme => hex == null && !_accent;
  bool get isAccent => _accent;

  String toJson() => hex?.hex ?? (_accent ? 'accent' : 'theme');

  @override
  bool operator ==(Object other) =>
      other is LabelColor && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

/// What's on the wallpaper: the current theme's scene (the usual case),
/// another theme's scene ("Wallpaper only"), or a stand-alone wallpaper.
class WallpaperChoice {
  const WallpaperChoice._()
    : theme = null,
      variantId = null,
      accent = null,
      wallpaper = null;

  /// The applied theme's own scene, following its variant and accent.
  static const followTheme = WallpaperChoice._();

  WallpaperChoice.ofTheme(
    ThemeDetail this.theme, {
    this.variantId,
    required Accent this.accent,
  }) : wallpaper = null;

  const WallpaperChoice.standalone(Wallpaper this.wallpaper)
    : theme = null,
      variantId = null,
      accent = null;

  factory WallpaperChoice.fromJson(JsonReader? r) {
    if (r == null) return followTheme;
    final wallpaper = r.optObject('wallpaper');
    if (wallpaper != null) {
      return WallpaperChoice.standalone(Wallpaper.fromJson(wallpaper));
    }
    return WallpaperChoice.ofTheme(
      ThemeDetail.fromJson(r.object('theme')),
      variantId: r.optId('variantId'),
      accent: Accent.fromJson(r.object('accent')),
    );
  }

  /// Another theme whose scene is the wallpaper.
  final ThemeDetail? theme;
  final String? variantId;
  final Accent? accent;
  final Wallpaper? wallpaper;

  bool get followsTheme => theme == null && wallpaper == null;

  /// The other theme's fonts, which its scene may use for text (Placeholder).
  Set<String> get fontIds => theme?.fonts.ids ?? const {};

  Iterable<AssetRef> get assets sync* {
    if (theme case final t?) yield* t.scene.assets;
    if (wallpaper?.scene case final s?) yield* s.assets;
    for (final size in wallpaper?.image?.sizes ?? const <ImageSize>[]) {
      yield size.asset;
    }
  }

  Map<String, Object?>? toJson() => followsTheme
      ? null
      : compact({
          'theme': theme?.toJson(),
          'variantId': variantId,
          'accent': accent?.toJson(),
          'wallpaper': wallpaper?.toJson(),
        });
}
