/// The mock catalog's content, taken from the "wallp Store Flow" design.
///
/// Built from the app's own models so it can't drift from the format.
/// generate.dart turns it into JSON files under assets/mock/.
library;

import 'dart:math' as math;

import 'package:wallp/catalog/catalog.dart';

import 'art.dart';

/// Every "published" date is relative to this, the date the design shows.
final seedDate = DateTime.utc(2026, 10, 15, 14);

DateTime daysAgo(int days) => seedDate.subtract(Duration(days: days));

const catalogVersion = '2026-10-15.1';

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

/// WCAG relative luminance.
double _lum(HexColor c) {
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

bool _isLight(HexColor c) => _lum(c) > 0.35;

HexColor _mix(HexColor a, HexColor b, double t) {
  int part(int shift) {
    final x = (a.argb >> shift) & 255, y = (b.argb >> shift) & 255;
    return (x + (y - x) * t).round();
  }

  final rgb = (part(16) << 16) | (part(8) << 8) | part(0);
  return _hex('#${rgb.toRadixString(16).padLeft(6, '0')}');
}

final _white = _hex('#FFFFFF');
final _black = _hex('#000000');
final _lightText = _hex('#F5F1EA');
final _darkText = _hex('#1A1720');

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

/// The plain wallp look, for undated collections and coming-soon tabs.
final _baseLook = _look(
  '#0E0C12',
  '#1A1720',
  '#26222E',
  '#332E3D',
  '#15121B',
  '#A39DAE',
  '#FFB547',
  'bebas-neue',
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
  // Thingyan and Thadingyut follow the Myanmar calendar: the dashboard team
  // must check these dates each year. The listed dates are placeholders.
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
  Festival(
    id: 'thadingyut',
    name: _t('Thadingyut', 'သီတင်းကျွတ်'),
    kind: FestivalKind.festival,
    tags: const ['myanmar'],
    sort: 40,
    occurrences: [DateTime(2027, 10, 11), DateTime(2028, 9, 29)],
    fallbackDate: const MonthDay(10, 10),
    durationDays: 3,
    look: _look(
      '#130C2A',
      '#1E153D',
      '#2A1F52',
      '#3B2E6B',
      '#181033',
      '#C1B8DC',
      '#FFD27A',
      'caveat',
    ),
    coverThemeId: 'festival-of-lights',
  ),
  Festival(
    id: 'minimal',
    name: _t('Minimal'),
    kind: FestivalKind.collection,
    sort: 90,
    look: _baseLook,
    coverThemeId: 'quiet-ink',
  ),
  Festival(
    id: 'kpop',
    name: _t('Kpop'),
    kind: FestivalKind.festival,
    comingSoon: true,
    sort: 100,
    look: _baseLook,
  ),
  Festival(
    id: 'mid-autumn',
    name: _t('Mid-Autumn'),
    kind: FestivalKind.festival,
    comingSoon: true,
    sort: 110,
    look: _baseLook,
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
  });

  final String id;
  final String family;
  final FontCategory category;

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
    id: 'mountains-of-christmas',
    family: 'Mountains of Christmas',
    category: FontCategory.handwritten,
    repoDir: 'apache/mountainsofchristmas',
    files: [
      ('MountainsofChristmas-Regular.ttf', 400, null),
      ('MountainsofChristmas-Bold.ttf', 700, null),
    ],
    tags: ['christmas', 'handwritten'],
  ),
  const FontSource(
    id: 'caveat',
    family: 'Caveat',
    category: FontCategory.handwritten,
    repoDir: 'ofl/caveat',
    files: [('Caveat[wght].ttf', 400, 700)],
    tags: ['handwritten', 'casual'],
  ),
  const FontSource(
    id: 'pacifico',
    family: 'Pacifico',
    category: FontCategory.handwritten,
    repoDir: 'ofl/pacifico',
    files: [('Pacifico-Regular.ttf', 400, null)],
    tags: ['handwritten', 'script'],
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
    sampleText: _t('သင်္ကြန် ၁၉:၄၇'),
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

List<IconPack> buildIconPacks(AssetFor asset) {
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

  IconPack images(
    String id,
    String festivalId,
    String name,
    String style,
    int added,
    int pop,
  ) {
    final art = packArt.firstWhere((a) => a.id == id);
    HexColor rgb(int v) => _hex('#${v.toRadixString(16).padLeft(6, '0')}');
    return IconPack(
      id: id,
      festivalId: festivalId,
      name: _t(name),
      style: _t(style),
      kind: IconPackKind.images,
      shape: IconShape.values.byName(art.shape),
      tile: art.tile == null ? null : rgb(art.tile!),
      glyph: rgb(art.glyph),
      ring: rgb(art.ring),
      glyphs: {
        for (final key in GlyphKeys.all)
          key: asset(iconPath(id, key), AssetFormat.png),
      },
      publishedAt: daysAgo(added),
      popularity: pop,
    );
  }

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
    images('moonlit', 'halloween', 'Moonlit', 'Filled', 6, 4),
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
    images('candy-cane', 'christmas', 'Candy Cane', 'Filled', 4, 5),
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
    images('padauk-flower', 'thingyan', 'Padauk', 'Outline', 60, 7),
    images('lantern-light', 'thadingyut', 'Lantern Light', 'Glow rim', 3, 6),
    images('quiet-line', 'minimal', 'Quiet Line', 'Line', 150, 8),
    images('mono-ember', 'minimal', 'Mono Ember', 'Filled', 100, 9),
  ];
}

// ---------------------------------------------------------------------------
// Scenes for the `layers` engine

enum Motif { moon, tree, ornament, cabin, drop, lantern, pumpkin, pagoda }

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

List<Layer> _motifLayers(Motif motif, Paint c, bool live) {
  final move = live ? ShapeMotion.sway : ShapeMotion.none;
  final pulse = live ? ShapeMotion.pulse : ShapeMotion.none;
  return switch (motif) {
    Motif.moon => [
      _shape(
        ShapeKind.circle,
        0.7,
        0.28,
        0.5,
        c('@motif'),
        glow: true,
        motion: pulse,
      ),
      _shape(ShapeKind.circle, 0.78, 0.25, 0.08, c('@deep'), opacity: 0.25),
    ],
    Motif.tree => [
      _shape(ShapeKind.rect, 0.5, 0.8, 0.07, c('@deep'), aspect: 0.7),
      _shape(
        ShapeKind.polygon,
        0.5,
        0.6,
        0.62,
        c('@motif'),
        aspect: 1.15,
        points: const [(x: 0.5, y: 0), (x: 1, y: 1), (x: 0, y: 1)],
      ),
      _shape(
        ShapeKind.circle,
        0.5,
        0.42,
        0.06,
        c('@accent'),
        glow: true,
        motion: pulse,
      ),
    ],
    Motif.ornament => [
      _shape(ShapeKind.rect, 0.5, 0.3, 0.012, c('@text'), aspect: 5),
      _shape(ShapeKind.rect, 0.5, 0.345, 0.1, c('@accent'), aspect: 0.5),
      _shape(
        ShapeKind.circle,
        0.5,
        0.46,
        0.46,
        c('@motif'),
        glow: true,
        motion: move,
      ),
    ],
    Motif.cabin => [
      _shape(
        ShapeKind.polygon,
        0.5,
        0.66,
        0.56,
        c('@motif'),
        aspect: 0.85,
        points: const [
          (x: 0.5, y: 0),
          (x: 1, y: 0.42),
          (x: 1, y: 1),
          (x: 0, y: 1),
          (x: 0, y: 0.42),
        ],
      ),
      _shape(
        ShapeKind.rect,
        0.42,
        0.7,
        0.1,
        c('@accent'),
        glow: true,
        motion: pulse,
      ),
      _shape(ShapeKind.rect, 0.6, 0.73, 0.09, c('@deep'), aspect: 1.5),
    ],
    Motif.drop => [
      _shape(
        ShapeKind.circle,
        0.3,
        0.38,
        0.3,
        c('@motif'),
        glow: true,
        motion: pulse,
      ),
      _shape(ShapeKind.circle, 0.72, 0.26, 0.14, c('@accent'), opacity: 0.8),
    ],
    Motif.lantern => [
      _shape(ShapeKind.rect, 0.5, 0.335, 0.14, c('@accent'), aspect: 0.25),
      _shape(
        ShapeKind.ellipse,
        0.5,
        0.44,
        0.34,
        c('@motif'),
        aspect: 1.3,
        glow: true,
        motion: move,
      ),
      _shape(
        ShapeKind.ellipse,
        0.5,
        0.44,
        0.16,
        c('@text'),
        aspect: 1.5,
        opacity: 0.3,
      ),
    ],
    Motif.pumpkin => [
      _shape(
        ShapeKind.rect,
        0.5,
        0.6,
        0.05,
        SceneColor('#3A5A2A'),
        aspect: 1.2,
      ),
      _shape(
        ShapeKind.ellipse,
        0.38,
        0.7,
        0.26,
        c('@motif'),
        aspect: 1.4,
        opacity: 0.9,
      ),
      _shape(
        ShapeKind.ellipse,
        0.62,
        0.7,
        0.26,
        c('@motif'),
        aspect: 1.4,
        opacity: 0.9,
      ),
      _shape(
        ShapeKind.ellipse,
        0.5,
        0.7,
        0.5,
        c('@motif'),
        aspect: 0.78,
        motion: pulse,
      ),
    ],
    // The pagoda itself is an image layer; this is the sun behind it.
    Motif.pagoda => [
      _shape(
        ShapeKind.circle,
        0.72,
        0.24,
        0.24,
        c('@motif'),
        glow: true,
        motion: pulse,
      ),
    ],
  };
}

/// Falling things per festival, only on live themes.
ParticlesLayer? _particles(String festivalId, Paint c) => switch (festivalId) {
  'halloween' => ParticlesLayer(
    effect: ParticleEffect.bats,
    count: 14,
    speed: 0.35,
    size: 0.5,
    color: c('@deep'),
  ),
  'christmas' => ParticlesLayer(
    effect: ParticleEffect.snow,
    count: 70,
    speed: 0.3,
    size: 0.35,
    color: SceneColor('#FFFFFF'),
    opacity: 0.9,
  ),
  'thingyan' => ParticlesLayer(
    effect: ParticleEffect.drops,
    count: 45,
    speed: 0.7,
    size: 0.3,
    color: SceneColor('#FFFFFF'),
    opacity: 0.7,
  ),
  'thadingyut' => ParticlesLayer(
    effect: ParticleEffect.lanterns,
    count: 12,
    speed: 0.15,
    size: 0.6,
    color: c('@accent'),
  ),
  _ => ParticlesLayer(
    effect: ParticleEffect.sparkles,
    count: 40,
    speed: 0.1,
    size: 0.2,
    color: c('@text'),
    opacity: 0.6,
  ),
};

SceneSpec _scene({
  required Motif motif,
  required String festivalId,
  required bool live,
  required Paint c,
  ImageLayer? image,
}) => SceneSpec.layers([
  GradientLayer(colors: [c('@surface'), c('@background')]),
  ..._motifLayers(motif, c, live),
  _shape(ShapeKind.ellipse, 0.5, 1, 1.8, c('@deep'), aspect: 0.45),
  ?image,
  if (live) ?_particles(festivalId, c),
]);

ImageLayer _image(LayerArt art, AssetFor asset) => ImageLayer(
  image: asset(layerPath(art), AssetFormat.png),
  fit: ImageFit.width,
  anchor: art == LayerArt.lanternGarland ? ImageAnchor.top : ImageAnchor.bottom,
);

// ---------------------------------------------------------------------------
// Themes

/// One colour variant as the design lists it: sky, ground, motif, accent.
typedef V = (
  String name,
  String bg,
  String ground,
  String motif,
  String accent,
);

Palette _palette(V v) {
  final bg = _hex(v.$2);
  final text = _isLight(bg) ? _darkText : _lightText;
  return Palette(
    background: bg,
    deep: _hex(v.$3),
    surface: _isLight(bg) ? _mix(bg, _black, 0.06) : _mix(bg, _white, 0.08),
    text: text,
    textMuted: _mix(text, bg, 0.3),
    motif: _hex(v.$4),
  );
}

PaletteOverride _override(Palette base, Palette p) => PaletteOverride(
  background: p.background == base.background ? null : p.background,
  deep: p.deep == base.deep ? null : p.deep,
  surface: p.surface == base.surface ? null : p.surface,
  text: p.text == base.text ? null : p.text,
  textMuted: p.textMuted == base.textMuted ? null : p.textMuted,
  motif: p.motif == base.motif ? null : p.motif,
);

/// Names for accent colours that appear in the design.
const _accentNames = {
  '#FF7A1A': 'Pumpkin',
  '#F3E6C4': 'Moon cream',
  '#A970FF': 'Witch purple',
  '#7BD44A': 'Slime',
  '#E8E4F0': 'Ghost white',
  '#F5F1EA': 'Snow',
  '#FFB547': 'Amber',
  '#F2B33D': 'Gold',
  '#CFE3F5': 'Ice',
  '#FFD27A': 'Lantern gold',
  '#FFE3EC': 'Pink icing',
  '#10223D': 'Navy',
  '#FFC21A': 'Sun',
  '#FFD54A': 'Padauk yellow',
  '#D7263D': 'Berry red',
  '#9FB3C6': 'Steel',
  '#7CC6FF': 'Sky',
  '#FF8FC0': 'Rose',
  '#D9D2C0': 'Bone',
  '#FFE08A': 'Candle',
};

/// Extra accents every theme in a festival offers, after its own.
final _festivalAccents = <String, List<Accent>>{
  'halloween': [
    _solid('Pumpkin', '#FF7A1A'),
    _solid('Witch purple', '#A970FF'),
    _solid('Slime', '#7BD44A'),
    _solid('Moon cream', '#F3E6C4'),
    _gradient('Pumpkin glow', ['#FFB547', '#FF4D2E'], 135),
  ],
  'christmas': [
    _solid('Gold', '#F2B33D'),
    _solid('Berry red', '#D7263D'),
    _solid('Snow', '#F5F1EA'),
    _solid('Pine', '#2C7A57'),
    _gradient('Frost', ['#F5F1EA', '#7CC6FF'], 180),
  ],
  'thingyan': [
    _solid('Sun', '#FFC21A'),
    _solid('Sky', '#7CC6FF'),
    _solid('Padauk yellow', '#FFD54A'),
    _solid('Lotus', '#FF8FA3'),
    _gradient('Splash', ['#FFC21A', '#7CC6FF'], 135),
  ],
  'thadingyut': [
    _solid('Lantern gold', '#FFD27A'),
    _solid('Amber', '#FFB547'),
    _solid('Rose', '#FF8FC0'),
    _solid('Snow', '#F5F1EA'),
    _gradient('Candle', ['#FFE08A', '#FF7A1A', '#D7263D'], 180),
  ],
  'minimal': [
    _solid('Snow', '#F5F1EA'),
    _solid('Amber', '#FFB547'),
    _solid('Steel', '#9FB3C6'),
    _solid('Rose', '#FF8FC0'),
    _gradient('Dusk', ['#FFB547', '#A970FF'], 135),
  ],
};

const _bodyFont = {
  'halloween': 'space-grotesk',
  'christmas': 'dm-sans',
  'thingyan': 'padauk',
  'thadingyut': 'padauk',
  'minimal': 'space-grotesk',
};

const _eventIcon = {
  'halloween': 'nightlight_round',
  'christmas': 'card_giftcard_rounded',
  'thingyan': 'water_drop_rounded',
  'thadingyut': 'light_mode_rounded',
  'minimal': 'event',
};

ThemeDetail _layersTheme(
  AssetFor asset, {
  required String id,
  required String festivalId,
  required String name,
  required ThemeStyle style,
  required Motif motif,
  required String font,
  required List<String> tags,
  required int added,
  required int popularity,
  required String iconPackId,
  required List<V> variants,
  bool live = false,
  LayerArt? image,
  List<String> wallpaperIds = const [],
  LocalizedText? subtitle,
}) {
  final base = _palette(variants.first);

  // One accent per distinct variant accent colour, then the festival's.
  final accents = <Accent>[];
  final variantAccent = <String, String>{};
  for (final v in variants) {
    final hex = _hex(v.$5).hex;
    final existing = accents.where((a) => a.primary.hex == hex).firstOrNull;
    final accent = existing ?? _solid(_accentNames[hex] ?? v.$1, hex);
    if (existing == null) accents.add(accent);
    variantAccent[_kebab(v.$1)] = accent.id;
  }
  for (final extra in _festivalAccents[festivalId]!) {
    final clash = accents.any(
      (a) =>
          a.id == extra.id ||
          (extra.type == AccentType.solid &&
              a.primary.hex == extra.primary.hex),
    );
    if (!clash) accents.add(extra);
  }

  return ThemeDetail(
    id: id,
    rev: 1,
    festivalId: festivalId,
    name: _t(name),
    subtitle: subtitle,
    style: style,
    tags: tags,
    publishedAt: daysAgo(added),
    popularity: popularity,
    scene: _scene(
      motif: motif,
      festivalId: festivalId,
      live: live,
      c: _token,
      image: image == null ? null : _image(image, asset),
    ),
    palette: base,
    accents: accents,
    variants: variants.length < 2
        ? const []
        : [
            for (final (i, v) in variants.indexed)
              Variant(
                id: _kebab(v.$1),
                name: _t(v.$1),
                palette: i == 0 ? null : _override(base, _palette(v)),
                accentId: variantAccent[_kebab(v.$1)],
              ),
          ],
    fonts: ThemeFonts(
      display: font,
      body: _bodyFont[festivalId]!,
      labels: _bodyFont[festivalId]!,
    ),
    accentClock: festivalId == 'halloween' || festivalId == 'thingyan',
    eventIcon: _eventIcon[festivalId]!,
    iconPackId: iconPackId,
    wallpaperIds: wallpaperIds,
    downloadBytes: 0,
  );
}

/// Today's three painted themes, with their existing colours and fonts.
List<ThemeDetail> _builtInThemes() {
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
      rev: 1,
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
        labels: 'space-grotesk',
      ),
      accentClock: true,
      eventIcon: 'nightlight_round',
      iconPackId: 'spooky-glow',
      wallpaperIds: const ['harvest-moon'],
      downloadBytes: 0,
    ),
    ThemeDetail(
      id: 'christmas-eve',
      rev: 1,
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
        labels: 'dm-sans',
      ),
      eventIcon: 'card_giftcard_rounded',
      iconPackId: 'gold-ornament',
      wallpaperIds: const ['silent-night'],
      downloadBytes: 0,
    ),
    ThemeDetail(
      id: 'thingyan-water',
      rev: 1,
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
        labels: 'padauk',
      ),
      accentClock: true,
      eventIcon: 'water_drop_rounded',
      iconPackId: 'water-splash',
      wallpaperIds: const ['water-splash'],
      downloadBytes: 0,
    ),
  ];
}

List<ThemeDetail> buildThemes(AssetFor asset) {
  ThemeDetail l({
    required String id,
    required String fest,
    required String name,
    required ThemeStyle style,
    required Motif motif,
    required String font,
    required String tags,
    required int added,
    required int pop,
    required String pack,
    required List<V> variants,
    bool live = false,
    LayerArt? image,
    List<String> walls = const [],
  }) => _layersTheme(
    asset,
    id: id,
    festivalId: fest,
    name: name,
    style: style,
    motif: motif,
    font: font,
    tags: tags.split(' '),
    added: added,
    popularity: pop,
    iconPackId: pack,
    variants: variants,
    live: live,
    image: image,
    wallpaperIds: walls,
  );

  const classic = ThemeStyle.classic,
      cozy = ThemeStyle.cozy,
      minimal = ThemeStyle.minimal,
      cute = ThemeStyle.cute;

  return [
    ..._builtInThemes(),

    // Halloween: 8 with Haunted Moon.
    l(
      id: 'pumpkin-patch',
      fest: 'halloween',
      name: 'Pumpkin Patch',
      style: cute,
      motif: Motif.pumpkin,
      font: 'creepster',
      tags: 'pumpkin orange',
      added: 5,
      pop: 2,
      pack: 'moonlit',
      walls: ['pumpkin-patch'],
      variants: [('Patch', '#2A1033', '#140A1C', '#FF7A1A', '#F3E6C4')],
    ),
    l(
      id: 'witch-hour',
      fest: 'halloween',
      name: 'Witch Hour',
      style: classic,
      motif: Motif.moon,
      font: 'creepster',
      tags: 'witch purple',
      added: 40,
      pop: 3,
      pack: 'moonlit',
      variants: [
        ('Violet', '#1E1440', '#120B2A', '#A970FF', '#A970FF'),
        ('Slime', '#0F2A1A', '#081A10', '#7BD44A', '#7BD44A'),
      ],
    ),
    l(
      id: 'ghost-town',
      fest: 'halloween',
      name: 'Ghost Town',
      style: minimal,
      motif: Motif.lantern,
      font: 'caveat',
      tags: 'ghost fog',
      added: 60,
      pop: 4,
      pack: 'moonlit',
      live: true,
      variants: [('Fog', '#1A1720', '#0E0C12', '#E8E4F0', '#E8E4F0')],
    ),
    l(
      id: 'bat-swarm',
      fest: 'halloween',
      name: 'Bat Swarm',
      style: classic,
      motif: Motif.moon,
      font: 'creepster',
      tags: 'bats moon night',
      added: 30,
      pop: 5,
      pack: 'moonlit',
      live: true,
      walls: ['bat-swarm'],
      variants: [('Dusk', '#14101E', '#08060C', '#D9D2C0', '#FF7A1A')],
    ),
    l(
      id: 'candy-corn',
      fest: 'halloween',
      name: 'Candy Corn',
      style: cute,
      motif: Motif.pumpkin,
      font: 'caveat',
      tags: 'candy sweet orange',
      added: 9,
      pop: 6,
      pack: 'moonlit',
      variants: [('Toffee', '#3A1A0A', '#1E0D05', '#FFB547', '#FFE08A')],
    ),
    l(
      id: 'raven-night',
      fest: 'halloween',
      name: 'Raven Night',
      style: minimal,
      motif: Motif.moon,
      font: 'bebas-neue',
      tags: 'raven dark red',
      added: 90,
      pop: 7,
      pack: 'moonlit',
      variants: [('Raven', '#101014', '#060608', '#C9C4D6', '#D7263D')],
    ),
    l(
      id: 'cobweb',
      fest: 'halloween',
      name: 'Cobweb',
      style: minimal,
      motif: Motif.moon,
      font: 'space-grotesk',
      tags: 'spider web grey',
      added: 200,
      pop: 8,
      pack: 'moonlit',
      variants: [('Dust', '#1C1A22', '#0E0D12', '#8A8496', '#F5F1EA')],
    ),

    // Christmas: 10 with Snowy Pines.
    l(
      id: 'cozy-cabin',
      fest: 'christmas',
      name: 'Cozy Cabin',
      style: cozy,
      motif: Motif.cabin,
      font: 'caveat',
      tags: 'cabin warm snow',
      added: 5,
      pop: 2,
      pack: 'candy-cane',
      image: LayerArt.snowHills,
      walls: ['snowy-cabin'],
      variants: [
        ('Warm', '#3A2318', '#F1E9DE', '#7A4A2E', '#FFB547'),
        ('Snowed in', '#2A3440', '#E9EFEC', '#5A6B7E', '#F5F1EA'),
      ],
    ),
    l(
      id: 'gold-ornaments',
      fest: 'christmas',
      name: 'Gold Ornaments',
      style: classic,
      motif: Motif.ornament,
      font: 'playfair-display',
      tags: 'gold red ornament',
      added: 60,
      pop: 3,
      pack: 'candy-cane',
      live: true,
      walls: ['ornaments'],
      variants: [
        ('Ruby', '#5A1420', '#2A0E15', '#F2B33D', '#F2B33D'),
        ('Emerald', '#0F3D2E', '#082418', '#F2B33D', '#F2B33D'),
        ('Navy', '#10223D', '#081226', '#F2B33D', '#F2B33D'),
      ],
    ),
    l(
      id: 'cocoa-night',
      fest: 'christmas',
      name: 'Cocoa Night',
      style: cozy,
      motif: Motif.cabin,
      font: 'pacifico',
      tags: 'cocoa warm night',
      added: 3,
      pop: 4,
      pack: 'candy-cane',
      live: true,
      image: LayerArt.snowHills,
      variants: [('Cocoa', '#2B1A12', '#1C120C', '#5C3A26', '#F3E6C4')],
    ),
    l(
      id: 'midnight-snow',
      fest: 'christmas',
      name: 'Midnight Snow',
      style: minimal,
      motif: Motif.tree,
      font: 'space-grotesk',
      tags: 'snow night minimal',
      added: 40,
      pop: 5,
      pack: 'candy-cane',
      variants: [
        ('Ink', '#0E1320', '#1D2533', '#1D2533', '#F5F1EA'),
        ('Frost', '#DCE6EE', '#B7C7D6', '#B7C7D6', '#10223D'),
      ],
    ),
    l(
      id: 'candy-cane',
      fest: 'christmas',
      name: 'Candy Cane',
      style: cute,
      motif: Motif.ornament,
      font: 'mountains-of-christmas',
      tags: 'candy red pink',
      added: 8,
      pop: 6,
      pack: 'candy-cane',
      variants: [
        ('Peppermint', '#B0182F', '#FFE3EC', '#F5F1EA', '#F5F1EA'),
        ('Plum', '#4A1A3A', '#FFE3EC', '#FF8FC0', '#FFE3EC'),
      ],
    ),
    l(
      id: 'little-reindeer',
      fest: 'christmas',
      name: 'Little Reindeer',
      style: cute,
      motif: Motif.tree,
      font: 'pacifico',
      tags: 'reindeer cute tree',
      added: 90,
      pop: 7,
      pack: 'candy-cane',
      live: true,
      variants: [
        ('Cocoa', '#6B3E26', '#F5E6D3', '#A8744F', '#F5F1EA'),
        ('Pine', '#1F4D3A', '#F5E6D3', '#2C7A57', '#FFD27A'),
      ],
    ),
    l(
      id: 'bare-branch',
      fest: 'christmas',
      name: 'Bare Branch',
      style: minimal,
      motif: Motif.tree,
      font: 'bebas-neue',
      tags: 'minimal dark winter',
      added: 200,
      pop: 8,
      pack: 'candy-cane',
      variants: [
        ('Graphite', '#1A1720', '#26222E', '#332E3D', '#F5F1EA'),
        ('Frost', '#DCE6EE', '#B7C7D6', '#9FB3C6', '#10223D'),
      ],
    ),
    l(
      id: 'silent-night',
      fest: 'christmas',
      name: 'Silent Night',
      style: classic,
      motif: Motif.tree,
      font: 'playfair-display',
      tags: 'night star tree',
      added: 300,
      pop: 9,
      pack: 'candy-cane',
      live: true,
      variants: [
        ('Night', '#0B1A2E', '#E9EFEC', '#173A5C', '#F2B33D'),
        ('Forest', '#0F3D2E', '#E9EFEC', '#1F6B4A', '#F2B33D'),
      ],
    ),
    l(
      id: 'gingerbread',
      fest: 'christmas',
      name: 'Gingerbread',
      style: cute,
      motif: Motif.cabin,
      font: 'mountains-of-christmas',
      tags: 'gingerbread cookie sweet',
      added: 2,
      pop: 10,
      pack: 'candy-cane',
      variants: [
        ('Ginger', '#8A4B22', '#F5E6D3', '#B5713A', '#F5F1EA'),
        ('Icing', '#F5E6D3', '#E8D2B8', '#D9A066', '#8A4B22'),
      ],
    ),

    // Thingyan: 6 with Water Splash.
    l(
      id: 'padauk-bloom',
      fest: 'thingyan',
      name: 'Padauk Bloom',
      style: cute,
      motif: Motif.drop,
      font: 'baloo-2',
      tags: 'padauk flowers yellow',
      added: 50,
      pop: 2,
      pack: 'padauk-flower',
      walls: ['padauk-bloom'],
      variants: [
        ('Bloom', '#0B4B80', '#5BB2EC', '#FFD54A', '#FFD54A'),
        ('Dusk', '#2A1A50', '#4A3A8A', '#FFD54A', '#FFD54A'),
      ],
    ),
    l(
      id: 'golden-pagoda',
      fest: 'thingyan',
      name: 'Golden Pagoda',
      style: classic,
      motif: Motif.pagoda,
      font: 'padauk',
      tags: 'pagoda gold myanmar',
      added: 6,
      pop: 3,
      pack: 'padauk-flower',
      image: LayerArt.pagoda,
      walls: ['golden-pagoda'],
      variants: [('Gold', '#1E3A5F', '#0F2238', '#F2B33D', '#F2B33D')],
    ),
    l(
      id: 'silver-bowl',
      fest: 'thingyan',
      name: 'Silver Bowl',
      style: cozy,
      motif: Motif.drop,
      font: 'baloo-2',
      tags: 'water bowl silver',
      added: 80,
      pop: 4,
      pack: 'padauk-flower',
      live: true,
      variants: [('Silver', '#0E5A7A', '#08364A', '#DDE6EA', '#FFC21A')],
    ),
    l(
      id: 'new-year-morning',
      fest: 'thingyan',
      name: 'New Year Morning',
      style: minimal,
      motif: Motif.drop,
      font: 'space-grotesk',
      tags: 'morning new year calm',
      added: 120,
      pop: 5,
      pack: 'padauk-flower',
      variants: [('Morning', '#123B5C', '#0A2238', '#FFE08A', '#FFE08A')],
    ),
    l(
      id: 'water-fight',
      fest: 'thingyan',
      name: 'Water Fight',
      style: cute,
      motif: Motif.drop,
      font: 'baloo-2',
      tags: 'water splash fun',
      added: 4,
      pop: 6,
      pack: 'padauk-flower',
      live: true,
      variants: [('Splash', '#0A6BA8', '#0A3D6B', '#7CC6FF', '#FFC21A')],
    ),

    // Thadingyut: 3.
    l(
      id: 'festival-of-lights',
      fest: 'thadingyut',
      name: 'Festival of Lights',
      style: classic,
      motif: Motif.lantern,
      font: 'caveat',
      tags: 'lights lantern myanmar',
      added: 30,
      pop: 1,
      pack: 'lantern-light',
      live: true,
      image: LayerArt.lanternGarland,
      walls: ['lanterns'],
      variants: [('Lantern', '#1E1440', '#120B2A', '#FFD27A', '#FFD27A')],
    ),
    l(
      id: 'candle-glow',
      fest: 'thadingyut',
      name: 'Candle Glow',
      style: cozy,
      motif: Motif.lantern,
      font: 'playfair-display',
      tags: 'candle warm',
      added: 4,
      pop: 2,
      pack: 'lantern-light',
      variants: [('Glow', '#2A1A10', '#140C06', '#FFB547', '#FFB547')],
    ),
    l(
      id: 'paper-lanterns',
      fest: 'thadingyut',
      name: 'Paper Lanterns',
      style: cute,
      motif: Motif.lantern,
      font: 'caveat',
      tags: 'paper lantern pink',
      added: 70,
      pop: 3,
      pack: 'lantern-light',
      live: true,
      image: LayerArt.lanternGarland,
      variants: [('Paper', '#2A1F52', '#181033', '#FF8FC0', '#FFD27A')],
    ),

    // Minimal: 3.
    l(
      id: 'quiet-ink',
      fest: 'minimal',
      name: 'Quiet Ink',
      style: minimal,
      motif: Motif.moon,
      font: 'bebas-neue',
      tags: 'minimal dark simple',
      added: 150,
      pop: 1,
      pack: 'quiet-line',
      walls: ['quiet-ink'],
      variants: [('Ink', '#1A1720', '#26222E', '#332E3D', '#F5F1EA')],
    ),
    l(
      id: 'ember',
      fest: 'minimal',
      name: 'Ember',
      style: minimal,
      motif: Motif.moon,
      font: 'space-grotesk',
      tags: 'minimal warm orange',
      added: 100,
      pop: 2,
      pack: 'mono-ember',
      live: true,
      walls: ['ember'],
      variants: [('Ember', '#241A12', '#140F0A', '#FFB547', '#FFB547')],
    ),
    l(
      id: 'slate',
      fest: 'minimal',
      name: 'Slate',
      style: minimal,
      motif: Motif.moon,
      font: 'dm-sans',
      tags: 'minimal grey cool',
      added: 11,
      pop: 3,
      pack: 'quiet-line',
      variants: [('Slate', '#22272E', '#15191E', '#4A5361', '#9FB3C6')],
    ),
  ];
}

// ---------------------------------------------------------------------------
// Wallpapers

List<Wallpaper> buildWallpapers(AssetFor asset) {
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

  Wallpaper layers(
    String id,
    String fest,
    String name,
    Motif motif,
    V colours,
    String tags,
    int added,
    int pop, {
    bool live = false,
    LayerArt? image,
  }) {
    final palette = _palette(colours);
    final accent = _solid('Accent', colours.$5);
    return Wallpaper(
      id: id,
      festivalId: fest,
      name: _t(name),
      publishedAt: daysAgo(added),
      scene: _scene(
        motif: motif,
        festivalId: fest,
        live: live,
        c: _literal(palette, accent),
        image: image == null ? null : _image(image, asset),
      ),
      tags: tags.split(' '),
      popularity: pop,
    );
  }

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
    layers(
      'bat-swarm',
      'halloween',
      'Bat Swarm',
      Motif.moon,
      ('', '#14101E', '#08060C', '#D9D2C0', '#FF7A1A'),
      'bats moon',
      30,
      2,
      live: true,
    ),
    layers(
      'pumpkin-patch',
      'halloween',
      'Pumpkin Patch',
      Motif.pumpkin,
      ('', '#2A1033', '#140A1C', '#FF7A1A', '#F3E6C4'),
      'pumpkin orange',
      5,
      3,
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
    layers(
      'ornaments',
      'christmas',
      'Ornaments',
      Motif.ornament,
      ('', '#5A1420', '#3A0D15', '#F2B33D', '#F2B33D'),
      'gold red',
      60,
      2,
    ),
    layers(
      'snowy-cabin',
      'christmas',
      'Snowy Cabin',
      Motif.cabin,
      ('', '#3A2318', '#F1E9DE', '#7A4A2E', '#FFB547'),
      'cabin snow warm',
      5,
      3,
      live: true,
      image: LayerArt.snowHills,
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
    layers(
      'padauk-bloom',
      'thingyan',
      'Padauk Bloom',
      Motif.drop,
      ('', '#0B4B80', '#5BB2EC', '#FFD54A', '#FFD54A'),
      'padauk flowers',
      50,
      2,
    ),
    layers(
      'golden-pagoda',
      'thingyan',
      'Golden Pagoda',
      Motif.pagoda,
      ('', '#1E3A5F', '#0F2238', '#F2B33D', '#F2B33D'),
      'pagoda gold',
      6,
      3,
      image: LayerArt.pagoda,
    ),
    layers(
      'lanterns',
      'thadingyut',
      'Lanterns',
      Motif.lantern,
      ('', '#1E1440', '#120B2A', '#FFD27A', '#FFD27A'),
      'lights lantern',
      30,
      1,
      live: true,
      image: LayerArt.lanternGarland,
    ),
    layers(
      'ember',
      'minimal',
      'Ember',
      Motif.moon,
      ('', '#241A12', '#140F0A', '#FFB547', '#FFB547'),
      'minimal warm',
      100,
      1,
      live: true,
    ),
    layers(
      'quiet-ink',
      'minimal',
      'Quiet Ink',
      Motif.moon,
      ('', '#1A1720', '#26222E', '#332E3D', '#F5F1EA'),
      'minimal dark',
      150,
      2,
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
  // Scheduled ahead: hidden until its window opens.
  Banner(
    id: 'thadingyut-2027',
    tag: _t('THEME'),
    title: _t('Festival of Lights'),
    subtitle: _t('Lanterns and candle glow for Thadingyut.'),
    cta: _t('Explore'),
    action: const BannerAction(
      type: BannerActionType.festival,
      id: 'thadingyut',
    ),
    look: BannerLook(
      background: _hex('#1E1440'),
      accent: _hex('#FFD27A'),
      titleColor: _hex('#FFD27A'),
      font: 'caveat',
      artThemeId: 'festival-of-lights',
    ),
    startsAt: DateTime.utc(2027, 9, 15),
    endsAt: DateTime.utc(2027, 10, 15),
    sort: 50,
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
  'moon',
  'snow',
  'Thingyan',
  'handwritten',
  'minimal',
  'live',
];

const engines = Engines([
  EngineInfo(id: EngineIds.halloween, sinceApp: '1.0.0'),
  EngineInfo(id: EngineIds.christmas, sinceApp: '1.0.0'),
  EngineInfo(id: EngineIds.thingyan, sinceApp: '1.0.0'),
  EngineInfo(id: EngineIds.layers, sinceApp: '1.0.0', params: ['layers']),
]);
