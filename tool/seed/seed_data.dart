/// The mock catalog's content, taken from the "wallp Store Flow" design.
///
/// Built from the app's own models so it can't drift from the format.
/// generate.dart turns it into JSON files under assets/mock/.
library;

import 'dart:math' as math;

import 'package:wallp/catalog/catalog.dart';

import 'art.dart';

part 'neon_night.dart';
part 'spider_night.dart';

/// Every "published" date is relative to this, the date the design shows.
final seedDate = DateTime.utc(2026, 10, 15, 14);

DateTime daysAgo(int days) => seedDate.subtract(Duration(days: days));

const catalogVersion = '2026-10-15.1';

/// The demo catalog's own publish number. Bump it whenever the demo data
/// changes: installed apps only fetch a catalog whose version is new.
/// 2: Halloween label colour, Creepster unlisted. 3: label fonts.
/// 4: Creepster listed again. 5: Padauk's preview says welcome.
/// 6: the Spider Night kit. 7: Web Slinger's background tile.
/// 8: pack pictures edge to edge, the app draws the shape's rim.
/// 9: a readable brand red for the Heroes store look.
/// 10: icon packs are only a tile; the 20 per-app pictures are gone.
/// 11: the Neon Night kit and the Orbitron font.
const demoRevision = 11;

/// Turns a source file under tool/seed/source/ into a hashed asset.
typedef AssetFor = AssetRef Function(String sourcePath, AssetFormat format);

LocalizedText _t(String en, [String? my]) =>
    LocalizedText({'en': en, 'my': ?my});

HexColor _hex(String hex) {
  if (!HexColor.isValid(hex)) throw ArgumentError.value(hex, 'hex');
  return HexColor(hex.toUpperCase());
}

String _kebab(String name) => name
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

Accent _solid(String name, String hex) =>
    Accent(id: _kebab(name), name: _t(name), colors: [_hex(hex)]);

Accent _gradient(String name, List<String> hexes, int angle) => Accent(
  id: _kebab(name),
  name: _t(name),
  colors: [for (final h in hexes) _hex(h)],
  angle: angle,
);

// ---------------------------------------------------------------------------
// Colour helpers

HexColor _mix(HexColor a, HexColor b, double t) {
  int part(int shift) {
    final x = (a.argb >> shift) & 255, y = (b.argb >> shift) & 255;
    return (x + (y - x) * t).round();
  }

  final rgb = (part(16) << 16) | (part(8) << 8) | part(0);
  return _hex('#${rgb.toRadixString(16).padLeft(6, '0')}');
}

final _lightText = _hex('#F5F1EA');

// ---------------------------------------------------------------------------
// Festivals

FestivalLook _look(
  String bg,
  String surface,
  String surface2,
  String outline,
  String nav,
  String muted,
  String brand,
  String font,
) => FestivalLook(
  background: _hex(bg),
  surface: _hex(surface),
  surface2: _hex(surface2),
  outline: _hex(outline),
  nav: _hex(nav),
  muted: _hex(muted),
  brand: _hex(brand),
  displayFont: font,
);

final festivals = <Festival>[
  Festival(
    id: 'halloween',
    name: _t('Halloween', 'ဟယ်လိုဝင်း'),
    kind: FestivalKind.festival,
    sort: 10,
    fallbackDate: const MonthDay(10, 31),
    unit: CountdownUnit.night,
    look: _look(
      '#120A1C',
      '#1E1430',
      '#2A1D40',
      '#3D2C57',
      '#170E24',
      '#B9AECB',
      '#FF7A1A',
      'creepster',
    ),
    coverThemeId: 'halloween-night',
  ),
  Festival(
    id: 'christmas',
    name: _t('Christmas', 'ခရစ္စမတ်'),
    kind: FestivalKind.festival,
    sort: 20,
    fallbackDate: const MonthDay(12, 25),
    look: _look(
      '#0A2A1F',
      '#11392B',
      '#184735',
      '#255A44',
      '#0D3225',
      '#B4CEC1',
      '#F2B33D',
      'playfair-display',
    ),
    coverThemeId: 'christmas-eve',
  ),
  // Thingyan follows the Myanmar calendar: the dashboard team must check
  // these dates each year. The listed dates are placeholders.
  Festival(
    id: 'thingyan',
    name: _t('Thingyan', 'သင်္ကြန်'),
    kind: FestivalKind.festival,
    tags: const ['myanmar'],
    sort: 30,
    occurrences: [
      DateTime(2027, 4, 13),
      DateTime(2028, 4, 13),
      DateTime(2029, 4, 13),
    ],
    fallbackDate: const MonthDay(4, 13),
    durationDays: 4,
    look: _look(
      '#062848',
      '#0C375F',
      '#124570',
      '#1E5A8C',
      '#083054',
      '#B6D0E8',
      '#FFC21A',
      'baloo-2',
    ),
    coverThemeId: 'thingyan-water',
  ),
];

// ---------------------------------------------------------------------------
// Fonts (downloaded from github.com/google/fonts by generate.dart)

class FontSource {
  const FontSource({
    required this.id,
    required this.family,
    required this.category,
    required this.repoDir,
    required this.files,
    this.scripts = const ['latin'],
    this.tags = const [],
    this.sampleText,
    this.listed = true,
  });

  final String id;
  final String family;
  final FontCategory category;
  final bool listed;

  /// Folder in the google/fonts repo, e.g. `ofl/creepster`.
  final String repoDir;

  /// (file name, weight, max weight for variable fonts)
  final List<(String, int, int?)> files;
  final List<String> scripts;
  final List<String> tags;
  final LocalizedText? sampleText;

  bool get isApache => repoDir.startsWith('apache/');
  String get license => isApache ? 'Apache-2.0' : 'OFL-1.1';
  String get licenseFile => isApache ? 'LICENSE.txt' : 'OFL.txt';
}

final fontSources = <FontSource>[
  const FontSource(
    id: 'creepster',
    family: 'Creepster',
    category: FontCategory.display,
    repoDir: 'ofl/creepster',
    files: [('Creepster-Regular.ttf', 400, null)],
    tags: ['halloween', 'spooky'],
  ),
  const FontSource(
    id: 'playfair-display',
    family: 'Playfair Display',
    category: FontCategory.display,
    repoDir: 'ofl/playfairdisplay',
    files: [('PlayfairDisplay[wght].ttf', 400, 900)],
    tags: ['christmas', 'serif', 'elegant'],
  ),
  const FontSource(
    id: 'baloo-2',
    family: 'Baloo 2',
    category: FontCategory.display,
    repoDir: 'ofl/baloo2',
    files: [('Baloo2[wght].ttf', 400, 800)],
    scripts: ['latin', 'devanagari'],
    tags: ['thingyan', 'rounded'],
  ),
  const FontSource(
    id: 'bebas-neue',
    family: 'Bebas Neue',
    category: FontCategory.display,
    repoDir: 'ofl/bebasneue',
    files: [('BebasNeue-Regular.ttf', 400, null)],
    tags: ['bold', 'tall'],
  ),
  const FontSource(
    id: 'orbitron',
    family: 'Orbitron',
    category: FontCategory.display,
    repoDir: 'ofl/orbitron',
    files: [('Orbitron[wght].ttf', 400, 900)],
    tags: ['neon', 'futuristic', 'wide'],
  ),
  const FontSource(
    id: 'space-grotesk',
    family: 'Space Grotesk',
    category: FontCategory.clean,
    repoDir: 'ofl/spacegrotesk',
    files: [('SpaceGrotesk[wght].ttf', 300, 700)],
    tags: ['clean', 'modern'],
  ),
  const FontSource(
    id: 'dm-sans',
    family: 'DM Sans',
    category: FontCategory.clean,
    repoDir: 'ofl/dmsans',
    files: [('DMSans[opsz,wght].ttf', 100, 1000)],
    tags: ['clean', 'friendly'],
  ),
  FontSource(
    id: 'padauk',
    family: 'Padauk',
    category: FontCategory.myanmar,
    repoDir: 'ofl/padauk',
    files: const [
      ('Padauk-Regular.ttf', 400, null),
      ('Padauk-Bold.ttf', 700, null),
    ],
    scripts: const ['myanmar', 'latin'],
    tags: const ['myanmar', 'burmese'],
    // Welcome, like the other fonts' default preview.
    sampleText: _t('ကြိုဆိုပါတယ်'),
  ),
];

String fontSourcePath(String fileName) => '$sourceDir/fonts/$fileName';

List<CatalogFont> buildFonts(AssetFor asset) => [
  for (final f in fontSources)
    CatalogFont(
      id: f.id,
      family: f.family,
      category: f.category,
      license: f.license,
      scripts: f.scripts,
      tags: f.tags,
      sampleText: f.sampleText,
      listed: f.listed,
      // Latin-only fonts can't draw Burmese app names.
      fallbackFor: f.scripts.contains('myanmar')
          ? const {}
          : const {'my': 'padauk'},
      files: [
        for (final (name, weight, maxWeight) in f.files)
          FontFile(
            asset: asset(fontSourcePath(name), AssetFormat.ttf),
            weight: weight,
            maxWeight: maxWeight,
          ),
      ],
    ),
];

// ---------------------------------------------------------------------------
// Icon packs

/// The three painted packs. Spider Night's downloaded pack is in its kit.
List<IconPack> buildIconPacks() {
  IconPack painted(
    String id,
    String festivalId,
    String name,
    String style,
    String painter,
    IconShape shape,
    String tile,
    String glyph,
    String ring,
    int added,
    int pop,
  ) => IconPack(
    id: id,
    festivalId: festivalId,
    name: _t(name),
    style: _t(style),
    kind: IconPackKind.painted,
    painter: painter,
    shape: shape,
    tile: _hex(tile),
    glyph: _hex(glyph),
    ring: _hex(ring),
    publishedAt: daysAgo(added),
    popularity: pop,
  );

  return [
    painted(
      'spooky-glow',
      'halloween',
      'Spooky Glow',
      'Neon outline',
      EngineIds.halloween,
      IconShape.squircle,
      '#1E1430',
      '#FF7A1A',
      '#FF7A1A',
      120,
      1,
    ),
    painted(
      'gold-ornament',
      'christmas',
      'Gold Ornament',
      'Gold rim',
      EngineIds.christmas,
      IconShape.circle,
      '#5A1420',
      '#F2B33D',
      '#F2B33D',
      120,
      2,
    ),
    painted(
      'water-splash',
      'thingyan',
      'Water Splash',
      'Filled',
      EngineIds.thingyan,
      IconShape.leaf,
      '#FFC21A',
      '#0A3D6B',
      '#FFC21A',
      150,
      3,
    ),
  ];
}

// ---------------------------------------------------------------------------
// Scenes for the `layers` engine (Spider Night)

/// Picks a layer colour. Themes pass palette tokens through; wallpapers
/// (which have no palette) resolve them to literal colours.
typedef Paint = SceneColor Function(String tokenOrHex);

SceneColor _token(String v) => SceneColor(v);

Paint _literal(Palette p, Accent accent) =>
    (v) => SceneColor(switch (v) {
      '@background' => p.background.hex,
      '@deep' => p.deep.hex,
      '@surface' => p.surface.hex,
      '@text' => p.text.hex,
      '@motif' => (p.motif ?? p.text).hex,
      '@accent' => accent.primary.hex,
      _ => v,
    });

ShapeLayer _shape(
  ShapeKind kind,
  double x,
  double y,
  double width,
  SceneColor color, {
  double aspect = 1,
  List<({double x, double y})> points = const [],
  bool glow = false,
  ShapeMotion motion = ShapeMotion.none,
  double opacity = 1,
}) => ShapeLayer(
  shape: kind,
  x: x,
  y: y,
  width: width,
  aspect: aspect,
  color: color,
  points: points,
  glow: glow,
  motion: motion,
  opacity: opacity,
);

// ---------------------------------------------------------------------------
// Themes

/// Today's three painted themes, with their existing colours and fonts.
List<ThemeDetail> buildThemes() {
  Palette p(
    String bg,
    String deep,
    String surface,
    String text,
    String muted,
  ) => Palette(
    background: _hex(bg),
    deep: _hex(deep),
    surface: _hex(surface),
    text: _hex(text),
    textMuted: _hex(muted),
  );

  return [
    ThemeDetail(
      id: 'halloween-night',
      // 2: labels.color. 3: labels font = the theme's font.
      rev: 3,
      festivalId: 'halloween',
      name: _t('Haunted Moon'),
      style: ThemeStyle.classic,
      tags: const ['spooky', 'moon', 'bats'],
      publishedAt: daysAgo(120),
      popularity: 1,
      scene: const SceneSpec(engine: EngineIds.halloween),
      palette: p('#160C24', '#0D0717', '#2A1840', '#F4E9C9', '#CDBFA0'),
      accents: [
        _solid('Pumpkin', '#FF8A2A'),
        _solid('Slime', '#9BE15D'),
        _solid('Witch', '#B57BFF'),
        _gradient('Pumpkin glow', ['#FFB547', '#FF4D2E'], 135),
      ],
      variants: [
        Variant(id: 'night', name: _t('Night')),
        Variant(
          id: 'blood-moon',
          name: _t('Blood moon'),
          palette: PaletteOverride(
            background: _hex('#1A0A10'),
            deep: _hex('#0D0508'),
            surface: _hex('#3A1420'),
          ),
        ),
      ],
      fonts: const ThemeFonts(
        display: 'creepster',
        body: 'space-grotesk',
        // App names in the theme's own font ("Theme font" on the icon
        // pack page); the phone's font is the "System font" choice.
        labels: 'creepster',
      ),
      accentClock: true,
      // Warm candle-light names; the Christmas and Thingyan themes keep the
      // default white, so both paths can be tried.
      labelColor: _hex('#FFD9A8'),
      eventIcon: 'nightlight_round',
      iconPackId: 'spooky-glow',
      wallpaperIds: const ['harvest-moon'],
      downloadBytes: 0,
    ),
    ThemeDetail(
      id: 'christmas-eve',
      // 2: labels font = the theme's font.
      rev: 2,
      festivalId: 'christmas',
      name: _t('Snowy Pines'),
      style: ThemeStyle.classic,
      tags: const ['snow', 'tree', 'winter'],
      publishedAt: daysAgo(120),
      popularity: 1,
      scene: const SceneSpec(engine: EngineIds.christmas),
      palette: p('#0F3D2E', '#0A2A20', '#1A5C41', '#FFF6E5', '#CFE0D7'),
      accents: [
        _solid('Berry red', '#C8102E'),
        _solid('Gold', '#B8862E'),
        _solid('Pine', '#1F6B4C'),
      ],
      variants: [
        Variant(id: 'forest', name: _t('Forest')),
        Variant(
          id: 'midnight',
          name: _t('Midnight'),
          palette: PaletteOverride(
            background: _hex('#10223D'),
            deep: _hex('#0A1628'),
            surface: _hex('#1B3557'),
          ),
        ),
        Variant(
          id: 'berry',
          name: _t('Berry'),
          palette: PaletteOverride(
            background: _hex('#4A1020'),
            deep: _hex('#2A0812'),
            surface: _hex('#6A1A30'),
          ),
          accentId: 'gold',
        ),
      ],
      fonts: const ThemeFonts(
        display: 'playfair-display',
        body: 'dm-sans',
        labels: 'playfair-display',
      ),
      eventIcon: 'card_giftcard_rounded',
      iconPackId: 'gold-ornament',
      wallpaperIds: const ['silent-night'],
      downloadBytes: 0,
    ),
    ThemeDetail(
      id: 'thingyan-water',
      // 2: labels font = the theme's font.
      rev: 2,
      festivalId: 'thingyan',
      name: _t('Water Splash'),
      subtitle: _t('သင်္ကြန်'),
      style: ThemeStyle.classic,
      tags: const ['water', 'myanmar', 'new year'],
      publishedAt: daysAgo(150),
      popularity: 1,
      scene: const SceneSpec(engine: EngineIds.thingyan),
      palette: p('#0A3D6B', '#1477C2', '#0F4F86', '#FFF8E7', '#CFE6F7'),
      accents: [
        _solid('Sun', '#FFC20E'),
        _solid('Sky', '#7CC6F0'),
        _solid('Lotus', '#FF8FA3'),
      ],
      fonts: const ThemeFonts(
        display: 'baloo-2',
        body: 'padauk',
        // Burmese app names fall back to Padauk.
        labels: 'baloo-2',
      ),
      accentClock: true,
      eventIcon: 'water_drop_rounded',
      iconPackId: 'water-splash',
      wallpaperIds: const ['water-splash'],
      downloadBytes: 0,
    ),
  ];
}

// ---------------------------------------------------------------------------
// Wallpapers

List<Wallpaper> buildWallpapers() {
  Wallpaper painted(
    String id,
    String fest,
    String name,
    String engine,
    String tags,
    int added,
    int pop,
  ) => Wallpaper(
    id: id,
    festivalId: fest,
    name: _t(name),
    publishedAt: daysAgo(added),
    scene: SceneSpec(engine: engine),
    tags: tags.split(' '),
    popularity: pop,
  );

  return [
    painted(
      'harvest-moon',
      'halloween',
      'Harvest Moon',
      EngineIds.halloween,
      'moon bats',
      120,
      1,
    ),
    painted(
      'silent-night',
      'christmas',
      'Silent Night',
      EngineIds.christmas,
      'snow star tree',
      300,
      1,
    ),
    painted(
      'water-splash',
      'thingyan',
      'Water Splash',
      EngineIds.thingyan,
      'water myanmar',
      150,
      1,
    ),
  ];
}

// ---------------------------------------------------------------------------
// Banners, accent presets, search

final banners = <Banner>[
  Banner(
    id: 'halloween-2026',
    tag: _t('THEME'),
    title: _t('Halloween Night'),
    subtitle: _t('Wallpaper, icons and a spooky clock font.'),
    cta: _t('Get theme'),
    action: const BannerAction(
      type: BannerActionType.theme,
      id: 'halloween-night',
    ),
    look: BannerLook(
      background: _hex('#160C24'),
      accent: _hex('#FF7A1A'),
      titleColor: _hex('#FF7A1A'),
      font: 'creepster',
      artThemeId: 'halloween-night',
    ),
    startsAt: DateTime.utc(2026, 10, 1),
    endsAt: DateTime.utc(2026, 11, 1),
    sort: 10,
  ),
  Banner(
    id: 'christmas-2026',
    tag: _t('WALLPAPERS'),
    title: _t('Snowy Christmas'),
    subtitle: _t('Snowy pines, gold ornaments and cozy cabins.'),
    cta: _t('Browse'),
    action: const BannerAction(
      type: BannerActionType.wallpapers,
      id: 'christmas',
    ),
    look: BannerLook(
      background: _hex('#0F3D2E'),
      accent: _hex('#F2B33D'),
      titleColor: _hex('#F5F1EA'),
      font: 'playfair-display',
      artThemeId: 'christmas-eve',
    ),
    startsAt: DateTime.utc(2026, 10, 10),
    endsAt: DateTime.utc(2026, 12, 27),
    sort: 20,
  ),
  Banner(
    id: 'clock-fonts',
    tag: _t('NEW · FONTS'),
    title: _t('Clock fonts'),
    subtitle: _t('Pick a font for the wallp Home and lock screen clock.'),
    cta: _t('Try fonts'),
    action: const BannerAction(type: BannerActionType.fonts),
    look: BannerLook(
      background: _hex('#26222E'),
      accent: _hex('#FFB547'),
      titleColor: _hex('#F5F1EA'),
      font: 'space-grotesk',
    ),
    sort: 30,
  ),
  Banner(
    id: 'thingyan-2027',
    tag: _t('THEME'),
    title: _t('Thingyan', 'သင်္ကြန်'),
    subtitle: _t('Water festival themes with Padauk flowers.'),
    cta: _t('Explore'),
    action: const BannerAction(type: BannerActionType.festival, id: 'thingyan'),
    look: BannerLook(
      background: _hex('#0A3D6B'),
      accent: _hex('#FFC21A'),
      titleColor: _hex('#FFC21A'),
      font: 'baloo-2',
      artThemeId: 'thingyan-water',
    ),
    sort: 40,
  ),
];

final accentPresets = AccentPresets(
  solids: [
    _solid('Pumpkin', '#FF7A1A'),
    _solid('Ember', '#FF4D2E'),
    _solid('Candy', '#FF5FA2'),
    _solid('Witch purple', '#A970FF'),
    _solid('Ghost blue', '#7CC6FF'),
    _solid('Slime', '#7BD44A'),
    _solid('Moon cream', '#F3E6C4'),
    _solid('Gold', '#F2B33D'),
    _solid('Bone', '#F5F1EA'),
    _solid('Blood', '#D7263D'),
  ],
  gradients: [
    _gradient('Pumpkin glow', ['#FFB547', '#FF4D2E'], 135),
    _gradient('Witching hour', ['#A970FF', '#FF5FA2'], 135),
    _gradient('Moonrise', ['#F3E6C4', '#FF7A1A'], 180),
    _gradient('Potion', ['#7BD44A', '#2EC4B6'], 90),
    _gradient('Frost', ['#F5F1EA', '#7CC6FF'], 180),
    _gradient('Candle', ['#FFE08A', '#FF7A1A', '#D7263D'], 180),
  ],
);

const searchSuggestions = [
  'Halloween',
  'Christmas',
  'Thingyan',
  'moon',
  'snow',
  'spider',
  'neon',
  'live',
];

const engines = Engines([
  EngineInfo(id: EngineIds.halloween, sinceApp: '1.0.0'),
  EngineInfo(id: EngineIds.christmas, sinceApp: '1.0.0'),
  EngineInfo(id: EngineIds.thingyan, sinceApp: '1.0.0'),
  EngineInfo(id: EngineIds.layers, sinceApp: '1.0.0', params: ['layers']),
]);
