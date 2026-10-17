// The Neon Night kit: one complete theme made only from script, to try every
// part of the system the other themes don't:
//
// * A live wallpaper on the `layers` engine, drawn only from shapes and
//   particles (no pictures): a synthwave sun over a glowing perspective
//   grid, stars and sparkles.
// * Two colour variants (Midnight, Sunset) and a gradient accent, which the
//   grid lines are painted in.
// * Its own downloaded font (Orbitron) for the clock and app names.
// * The Neon Glow icon pack: a dark neon tile, circle by default.
// * The same scene as a still wallpaper, and a store banner.
//
// The tile comes from render_art_test.dart; run tool/seed/spider_night.sh
// (it builds every kit) to rebuild everything.
part of 'seed_data.dart';

const neonThemeId = 'neon-night';
const neonWallpaperIds = {'neon-horizon'};

final _neonPalette = Palette(
  background: _hex('#120326'),
  deep: _hex('#07010F'),
  surface: _hex('#3A0B5C'),
  text: _hex('#F8F0FF'),
  textMuted: _mix(_hex('#F8F0FF'), _hex('#120326'), 0.3),
  motif: _hex('#FF3EA5'),
);

final _neonAccents = [
  _solid('Neon cyan', '#22E4FF'),
  _solid('Hot pink', '#FF3EA5'),
  _solid('Laser lime', '#B6FF3B'),
  _gradient('Synthwave', ['#FF3EA5', '#22E4FF'], 90),
];

/// The sun: a circle sitting on the horizon. Its stripes are cut across the
/// lower half in the sky colour, each exactly as wide as the sun there.
const _sunX = 0.5, _sunY = 0.47, _sunWidth = 0.62;
const _horizon = 0.62;

/// (y, height in px) of each stripe; the design canvas is 390 × 844.
const _sunStripes = [(0.52, 4.0), (0.55, 6.0), (0.578, 8.0), (0.602, 9.0)];

List<Layer> _sunStripeLayers(Paint c) {
  const w = 390.0, h = 844.0;
  const r = _sunWidth * w / 2;
  return [
    for (final (y, px) in _sunStripes)
      () {
        final d = (y - _sunY) * h;
        final chord = 2 * math.sqrt(r * r - d * d);
        return _shape(
          ShapeKind.rect,
          _sunX,
          y,
          chord / w,
          c('@surface'),
          aspect: px / chord,
        );
      }(),
  ];
}

/// The ground's grid: lines across, getting further apart towards the
/// viewer, and lines from the vanishing point on the horizon.
List<Layer> _neonGrid(Paint c) {
  // The ground box: from the horizon to the bottom edge, 3 screens wide so
  // the outer lines can fan out past the sides.
  const groundY = (_horizon + 1) / 2;
  const boxWidth = 3.0;
  const boxAspect = (1 - _horizon) * 844 / (boxWidth * 390);
  return [
    for (final y in [0.635, 0.655, 0.685, 0.725, 0.78, 0.855, 0.95])
      _shape(
        ShapeKind.rect,
        0.5,
        y,
        1.3,
        c('@accent'),
        aspect: 2 / (1.3 * 390),
        opacity: 0.55,
      ),
    for (var k = -10; k <= 10; k++)
      _shape(
        ShapeKind.polygon,
        0.5,
        groundY,
        boxWidth,
        c('@accent'),
        aspect: boxAspect,
        opacity: 0.45,
        points: [
          (x: 0.5 + k * 0.004 - 0.0004, y: 0.0),
          (x: 0.5 + k * 0.004 + 0.0004, y: 0.0),
          (x: 0.5 + k * 0.045 + 0.0012, y: 1.0),
          (x: 0.5 + k * 0.045 - 0.0012, y: 1.0),
        ],
      ),
  ];
}

/// The scene, back to front. Themes pass palette tokens, wallpapers literal
/// colours (see [Paint]).
SceneSpec _neonScene(Paint c, {required bool live}) => SceneSpec.layers([
  // The lower half is one flat colour, so the sun's stripes match it.
  GradientLayer(colors: [c('@background'), c('@surface'), c('@surface')]),
  if (live)
    ParticlesLayer(
      effect: ParticleEffect.stars,
      count: 50,
      speed: 0.06,
      size: 0.2,
      color: c('@text'),
      opacity: 0.6,
    ),
  _shape(
    ShapeKind.circle,
    _sunX,
    _sunY,
    _sunWidth,
    c('@motif'),
    glow: true,
    motion: live ? ShapeMotion.pulse : ShapeMotion.none,
  ),
  ..._sunStripeLayers(c),
  // The ground, from the horizon down.
  _shape(
    ShapeKind.rect,
    0.5,
    (_horizon + 1) / 2,
    1.3,
    c('@deep'),
    aspect: (1 - _horizon) * 844 / (1.3 * 390),
  ),
  ..._neonGrid(c),
  // The glowing horizon line.
  _shape(
    ShapeKind.rect,
    0.5,
    _horizon,
    1.3,
    c('@accent'),
    aspect: 3 / (1.3 * 390),
    glow: true,
    opacity: 0.9,
  ),
  if (live)
    ParticlesLayer(
      effect: ParticleEffect.sparkles,
      count: 24,
      speed: 0.3,
      size: 0.3,
      color: c('@accent'),
      opacity: 0.7,
    ),
]);

SeedKit buildNeonNight(AssetFor asset) {
  final literal = _literal(_neonPalette, _neonAccents.first);
  HexColor rgb(int v) => _hex('#${v.toRadixString(16).padLeft(6, '0')}');
  return SeedKit(
    festival: Festival(
      id: 'neon',
      name: _t('Neon'),
      kind: FestivalKind.collection,
      sort: 85,
      look: _look(
        '#120326',
        '#1E0838',
        '#2A0F4A',
        '#3D1A63',
        '#170530',
        '#B9A6D6',
        '#22E4FF',
        'orbitron',
      ),
      coverThemeId: neonThemeId,
    ),
    theme: ThemeDetail(
      id: neonThemeId,
      rev: 1,
      festivalId: 'neon',
      name: _t('Neon Night'),
      subtitle: _t('A synthwave sun on a glowing grid'),
      style: ThemeStyle.minimal,
      tags: const ['neon', 'synthwave', 'retro', 'grid', 'night'],
      publishedAt: daysAgo(1),
      popularity: 0,
      scene: _neonScene(_token, live: true),
      palette: _neonPalette,
      accents: _neonAccents,
      variants: [
        Variant(id: 'midnight', name: _t('Midnight')),
        Variant(
          id: 'sunset',
          name: _t('Sunset'),
          palette: PaletteOverride(
            background: _hex('#2A0A2E'),
            surface: _hex('#6B1747'),
            motif: _hex('#FF8A3D'),
          ),
          accentId: 'hot-pink',
        ),
      ],
      fonts: const ThemeFonts(
        display: 'orbitron',
        body: 'space-grotesk',
        labels: 'orbitron',
      ),
      accentClock: true,
      labelColor: _hex('#F8F0FF'),
      eventIcon: 'music_note_rounded',
      iconPackId: neonGlow.id,
      wallpaperIds: neonWallpaperIds.toList(),
      downloadBytes: 0,
    ),
    wallpapers: [
      Wallpaper(
        id: 'neon-horizon',
        festivalId: 'neon',
        name: _t('Neon Horizon'),
        publishedAt: daysAgo(1),
        scene: _neonScene(literal, live: false),
        tags: const ['neon', 'grid', 'still'],
        popularity: 1,
      ),
    ],
    iconPack: IconPack(
      id: neonGlow.id,
      festivalId: 'neon',
      name: _t('Neon Glow'),
      style: _t('Glow'),
      kind: IconPackKind.images,
      shape: IconShape.values.byName(neonGlow.shape),
      tile: rgb(neonGlow.tile),
      glyph: rgb(neonGlow.glyph),
      ring: rgb(neonGlow.ring),
      background: asset(backgroundPath(neonGlow.id), AssetFormat.png),
      publishedAt: daysAgo(1),
      popularity: 0,
    ),
    banner: Banner(
      id: 'neon-night',
      tag: _t('NEW · THEME'),
      title: _t('Neon Night'),
      subtitle: _t('A synthwave sun, neon icons and a glowing clock.'),
      cta: _t('Get theme'),
      action: const BannerAction(type: BannerActionType.theme, id: neonThemeId),
      look: BannerLook(
        background: _hex('#120326'),
        accent: _hex('#22E4FF'),
        titleColor: _hex('#F8F0FF'),
        font: 'orbitron',
        artThemeId: neonThemeId,
      ),
      sort: 6,
    ),
  );
}
