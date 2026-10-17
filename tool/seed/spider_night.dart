// The Spider Night kit: one complete theme made only from script.
//
// * A live wallpaper on the `layers` engine: a pulsing red moon, a spider
//   swinging on its thread, city rain and stars, over a picture skyline.
// * The same scene as stand-alone wallpapers, one live and one still.
// * The Web Slinger icon pack: a comic-style tile for every app's logo.
//
// Pictures come from render_art_test.dart; run tool/seed/spider_night.sh to
// rebuild and preview everything.
//
// The art is an original spider-and-city look, not Marvel's Spider-Man:
// shipping the real character, logo or name needs a licence.
part of 'seed_data.dart';

/// Everything one kit adds to a catalog.
class SeedKit {
  const SeedKit({
    required this.festival,
    required this.theme,
    required this.wallpapers,
    required this.iconPack,
    required this.banner,
  });

  final Festival festival;
  final ThemeDetail theme;
  final List<Wallpaper> wallpapers;
  final IconPack iconPack;
  final Banner banner;
}

const spiderThemeId = 'spider-night';
const spiderWallpaperIds = {'red-moon-swing', 'web-corner'};

final _spiderPalette = Palette(
  background: _hex('#0B1026'),
  deep: _hex('#05070F'),
  surface: _hex('#1A2350'),
  text: _lightText,
  textMuted: _mix(_lightText, _hex('#0B1026'), 0.3),
  motif: _hex('#E23636'),
);

final _spiderAccents = [
  _solid('Spider red', '#E23636'),
  _solid('Suit blue', '#2B5BD7'),
  _solid('Web white', '#F5F1EA'),
  _gradient('Multiverse', ['#FF3B5C', '#7B5BFF'], 135),
];

/// The spider hanging on its thread. Every part shares one tall box, so with
/// `sway` they all swing together from the box's top, like a pendulum.
/// Box: [_spiderWidth] of the screen width wide, [_spiderAspect] times as tall.
const _spiderWidth = 0.2;
const _spiderAspect = 4.0;

/// Points in box units (x 0–1, y 0–[_spiderAspect]) to the 0–1 corners the
/// format wants.
List<({double x, double y})> _boxPoints(List<(double, double)> pts) => [
  for (final (x, y) in pts) (x: x, y: y / _spiderAspect),
];

List<(double, double)> _oval(double cx, double cy, double rx, double ry) => [
  for (var i = 0; i < 18; i++)
    (
      cx + rx * math.cos(i * 2 * math.pi / 18),
      cy + ry * math.sin(i * 2 * math.pi / 18),
    ),
];

/// A thick polyline as one closed polygon: down one side, back the other.
List<(double, double)> _strip(List<(double, double)> line, double thick) {
  final left = <(double, double)>[], right = <(double, double)>[];
  for (var i = 0; i < line.length; i++) {
    final (ax, ay) = line[i == 0 ? 0 : i - 1];
    final (bx, by) = line[i == line.length - 1 ? i : i + 1];
    final dx = bx - ax, dy = by - ay;
    final len = math.sqrt(dx * dx + dy * dy);
    final nx = -dy / len * thick / 2, ny = dx / len * thick / 2;
    final (x, y) = line[i];
    left.add((x + nx, y + ny));
    right.add((x - nx, y - ny));
  }
  return [...left, ...right.reversed];
}

List<Layer> _spider(Paint c, bool live, double x, double y) {
  const a = _spiderAspect;
  // Hangs head down: the thread holds the abdomen, the head is lowest.
  final parts = <List<(double, double)>>[
    _strip([(0.5, 0), (0.5, a - 0.5)], 0.014),
    _oval(0.5, a - 0.42, 0.13, 0.17),
    _oval(0.5, a - 0.17, 0.085, 0.09),
  ];
  // Four legs a side: start at the head, bend at the knee, end at the foot.
  const legs = [
    ((0.54, a - 0.12), (0.78, a - 0.24), (0.86, a - 0.02)),
    ((0.56, a - 0.15), (0.86, a - 0.32), (0.97, a - 0.16)),
    ((0.56, a - 0.19), (0.86, a - 0.48), (0.98, a - 0.38)),
    ((0.54, a - 0.22), (0.76, a - 0.58), (0.84, a - 0.74)),
  ];
  for (final (start, knee, foot) in legs) {
    for (final side in [1.0, -1.0]) {
      (double, double) m((double, double) p) =>
          (0.5 + (p.$1 - 0.5) * side, p.$2);
      parts.add(_strip([m(start), m(knee), m(foot)], 0.035));
    }
  }
  return [
    for (final part in parts)
      _shape(
        ShapeKind.polygon,
        x,
        y,
        _spiderWidth,
        c('@deep'),
        aspect: _spiderAspect,
        points: _boxPoints(part),
        motion: live ? ShapeMotion.sway : ShapeMotion.none,
      ),
  ];
}

/// The scene, back to front. Themes pass palette tokens, wallpapers literal
/// colours (see [Paint]).
SceneSpec _spiderScene(AssetFor asset, Paint c, {required bool live}) {
  // The box's top sits just above the screen, so the thread comes from
  // off-screen and the spider hangs in front of the moon.
  const spiderTop = -0.012;
  final spiderY = spiderTop + _spiderWidth * _spiderAspect * 390 / 844 / 2;
  return SceneSpec.layers([
    GradientLayer(colors: [c('@background'), c('@surface'), c('#3A1030')]),
    if (live)
      ParticlesLayer(
        effect: ParticleEffect.stars,
        count: 40,
        speed: 0.08,
        size: 0.25,
        color: c('@text'),
        opacity: 0.7,
      ),
    _shape(
      ShapeKind.circle,
      0.68,
      0.26,
      0.56,
      c('@motif'),
      glow: true,
      motion: live ? ShapeMotion.pulse : ShapeMotion.none,
      opacity: 0.92,
    ),
    _shape(ShapeKind.circle, 0.6, 0.22, 0.16, c('#FF8A7A'), opacity: 0.25),
    _shape(ShapeKind.circle, 0.78, 0.32, 0.1, c('#FF8A7A'), opacity: 0.2),
    ImageLayer(
      image: asset(layerPath(LayerArt.spiderWeb), AssetFormat.png),
      anchor: ImageAnchor.top,
      opacity: 0.55,
    ),
    ..._spider(c, live, 0.64, spiderY),
    ImageLayer(
      image: asset(layerPath(LayerArt.spiderSkyline), AssetFormat.png),
    ),
    if (live)
      ParticlesLayer(
        effect: ParticleEffect.rain,
        count: 50,
        speed: 0.55,
        size: 0.25,
        color: c('#9FB3C6'),
        opacity: 0.35,
      ),
  ]);
}

SeedKit buildSpiderNight(AssetFor asset) {
  final literal = _literal(_spiderPalette, _spiderAccents.first);
  return SeedKit(
    festival: Festival(
      id: 'heroes',
      name: _t('Heroes'),
      kind: FestivalKind.collection,
      sort: 80,
      look: _look(
        '#0B1026',
        '#151B36',
        '#1F2747',
        '#2C3660',
        '#0E1330',
        '#A9B3CF',
        // A deeper red than the theme's accent, so light button labels on
        // it stay readable (4.5:1).
        '#CB3131',
        'bebas-neue',
      ),
      coverThemeId: spiderThemeId,
    ),
    theme: ThemeDetail(
      id: spiderThemeId,
      // 2: the icon pack's background tile (downloadBytes).
      // 3: edge-to-edge icon pictures (downloadBytes).
      // 4: the icon pack is only its tile (downloadBytes).
      rev: 4,
      festivalId: 'heroes',
      name: _t('Spider Night'),
      subtitle: _t('A red moon, city rain and a spider on a swing'),
      style: ThemeStyle.classic,
      tags: const ['spider', 'hero', 'city', 'red', 'web'],
      publishedAt: daysAgo(1),
      popularity: 0,
      scene: _spiderScene(asset, _token, live: true),
      palette: _spiderPalette,
      accents: _spiderAccents,
      fonts: const ThemeFonts(
        display: 'bebas-neue',
        body: 'space-grotesk',
        labels: 'bebas-neue',
      ),
      accentClock: true,
      labelColor: _lightText,
      eventIcon: 'star_rounded',
      iconPackId: 'web-slinger',
      wallpaperIds: spiderWallpaperIds.toList(),
      downloadBytes: 0,
    ),
    wallpapers: [
      Wallpaper(
        id: 'red-moon-swing',
        festivalId: 'heroes',
        name: _t('Red Moon Swing'),
        publishedAt: daysAgo(1),
        scene: _spiderScene(asset, literal, live: true),
        tags: const ['spider', 'city', 'rain'],
        popularity: 1,
      ),
      Wallpaper(
        id: 'web-corner',
        festivalId: 'heroes',
        name: _t('Web Corner'),
        publishedAt: daysAgo(1),
        scene: _spiderScene(asset, literal, live: false),
        tags: const ['spider', 'web', 'still'],
        popularity: 2,
      ),
    ],
    iconPack: () {
      const art = webSlinger;
      HexColor rgb(int v) => _hex('#${v.toRadixString(16).padLeft(6, '0')}');
      return IconPack(
        id: art.id,
        festivalId: 'heroes',
        name: _t('Web Slinger'),
        style: _t('Comic'),
        kind: IconPackKind.images,
        shape: IconShape.values.byName(art.shape),
        tile: rgb(art.tile),
        glyph: rgb(art.glyph),
        ring: rgb(art.ring),
        background: asset(backgroundPath(art.id), AssetFormat.png),
        publishedAt: daysAgo(1),
        popularity: 0,
      );
    }(),
    banner: Banner(
      id: 'spider-night',
      tag: _t('NEW · THEME'),
      title: _t('Spider Night'),
      subtitle: _t('Live wallpaper, comic icons and a bold clock.'),
      cta: _t('Get theme'),
      action: const BannerAction(
        type: BannerActionType.theme,
        id: spiderThemeId,
      ),
      look: BannerLook(
        background: _hex('#0B1026'),
        accent: _hex('#E23636'),
        titleColor: _hex('#F5F1EA'),
        font: 'bebas-neue',
        artThemeId: spiderThemeId,
      ),
      sort: 5,
    ),
  );
}
