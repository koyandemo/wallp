/// Art for the mock catalog's downloadable files, shared by
/// render_art_test.dart (draws the PNGs) and generate.dart (hashes them).
///
/// Glyph paths and icon pack looks come from the "wallp Store Flow" design
/// canvas. In the real product, designers upload this art in the dashboard.
library;

/// One stroke path per glyph key, in a 24 × 24 box (SVG path syntax).
const glyphPaths = <String, String>{
  'phone': 'M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a1 1 0 0 1-1 1A16 16 0 0 1 4 5a1 1 0 0 1 1-1z',
  'messages': 'M4 5h16v11H9l-5 4z M8 10h8 M8 13h5',
  'camera':
      'M3 8h4l2-3h6l2 3h4v11H3z M12 10a3.5 3.5 0 1 0 0 7a3.5 3.5 0 1 0 0-7z',
  'maps': 'M12 21s-7-6-7-11a7 7 0 0 1 14 0c0 5-7 11-7 11z M12 7.5a2.5 2.5 0 1 0 0 5a2.5 2.5 0 1 0 0-5z',
  'music': 'M9 18V5l11-2v13 M6 15a3 3 0 1 0 0 6a3 3 0 1 0 0-6z M17 13a3 3 0 1 0 0 6a3 3 0 1 0 0-6z',
  'mail': 'M3 6h18v12H3z M3 6l9 7 9-7',
  'photos': 'M3 4h18v16H3z M21 15l-5-5L5 20 M8.5 7a1.5 1.5 0 1 0 0 3a1.5 1.5 0 1 0 0-3z',
  'clock': 'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z M12 7v5l3 2',
  'calendar': 'M4 5h16v15H4z M4 10h16 M8 3v4 M16 3v4',
  'settings': 'M12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6z M12 2v3 M12 19v3 M2 12h3 M19 12h3 M4.9 4.9L7 7 M17 17l2.1 2.1 M4.9 19.1L7 17 M17 7l2.1-2.1',
  'browser': 'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z M3 12h18 M12 3c3.5 3.5 3.5 14.5 0 18 M12 3c-3.5 3.5-3.5 14.5 0 18',
  'weather': 'M7 18h10a4 4 0 0 0 0-8a6 6 0 0 0-11.5 1.5A3.3 3.3 0 0 0 7 18z',
  'notes': 'M6 3h12v18H6z M9 8h6 M9 12h6 M9 16h4',
  'calculator': 'M5 3h14v18H5z M8 6h8v4H8z M8 14h.01 M12 14h.01 M16 14h.01 M8 18h.01 M12 18h.01 M16 18h.01',
  'wallet': 'M3 7h17v12H3z M3 7l13-3v3 M16 13h.01',
  'store': 'M5 8h14l-1 12H6z M9 8a3 3 0 0 1 6 0',
  'video': 'M3 6h13v12H3z M16 10l5-3v10l-5-3',
  'contacts':
      'M12 4a4 4 0 1 0 0 8a4 4 0 1 0 0-8z M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6',
  'files': 'M3 6h6l2 2h10v11H3z',
  'health': 'M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z M8 11h2l1-2 2 4 1-2h2',
};

enum PackLook {
  /// Solid tile, dark glyph.
  filled,

  /// Dark tile, coloured ring and glyph.
  outline,

  /// Like outline, with a soft glow around the ring.
  glow,

  /// No tile: the glyph alone, straight on the wallpaper.
  line,

  /// Comic book: solid tile with a web drawn across it in the ring colour,
  /// and the glyph inked with a ring-coloured outline.
  comic,
}

/// How a downloadable icon pack is drawn. Colours are `0xRRGGBB`.
class PackArt {
  const PackArt({
    required this.id,
    required this.look,
    required this.shape,
    required this.glyph,
    required this.ring,
    this.tile,
    this.background = false,
  });

  final String id;
  final PackLook look;

  /// squircle, circle, square or leaf (see IconShape in the models).
  final String shape;
  final int? tile;
  final int glyph;
  final int ring;

  /// Also draw an empty tile ([backgroundPath]) for apps the pack has no
  /// picture for.
  final bool background;
}

const packArt = <PackArt>[
  PackArt(
    id: 'moonlit',
    look: PackLook.filled,
    shape: 'circle',
    tile: 0xF3E6C4,
    glyph: 0x160C24,
    ring: 0xF3E6C4,
  ),
  PackArt(
    id: 'candy-cane',
    look: PackLook.filled,
    shape: 'squircle',
    tile: 0xF5F1EA,
    glyph: 0xB0182F,
    ring: 0xB0182F,
  ),
  PackArt(
    id: 'padauk-flower',
    look: PackLook.outline,
    shape: 'squircle',
    tile: 0x0B4B80,
    glyph: 0xFFD54A,
    ring: 0xFFD54A,
  ),
  PackArt(
    id: 'lantern-light',
    look: PackLook.glow,
    shape: 'circle',
    tile: 0x2A1F52,
    glyph: 0xFFD27A,
    ring: 0xFFD27A,
  ),
  PackArt(
    id: 'quiet-line',
    look: PackLook.line,
    shape: 'square',
    glyph: 0xF5F1EA,
    ring: 0xF5F1EA,
  ),
  PackArt(
    id: 'mono-ember',
    look: PackLook.filled,
    shape: 'squircle',
    tile: 0xFFB547,
    glyph: 0x241A12,
    ring: 0xFFB547,
  ),
  // Spider Night kit (spider_night.dart).
  PackArt(
    id: 'web-slinger',
    look: PackLook.comic,
    shape: 'squircle',
    tile: 0xD3202A,
    glyph: 0xFFFFFF,
    ring: 0x0A0A12,
    background: true,
  ),
];

/// Icon images are square, this many pixels.
const iconPixels = 256;

/// Scene layer images (transparent PNG, drawn along the bottom of a scene).
enum LayerArt {
  /// Rolling snowy hills, for the cabin themes.
  snowHills('snow-hills', 1080, 640),

  /// A gold pagoda silhouette on a low hill, for Golden Pagoda.
  pagoda('pagoda', 1080, 900),

  /// A string of paper lanterns across the top, for Thadingyut.
  lanternGarland('lantern-garland', 1080, 520, top: true),

  /// Night city skyline with lit windows, for Spider Night.
  spiderSkyline('spider-skyline', 1080, 1240),

  /// A spider web across the top-left corner, for Spider Night.
  spiderWeb('spider-web', 1080, 1080, top: true);

  const LayerArt(this.file, this.width, this.height, {this.top = false});

  final String file;
  final int width;
  final int height;

  /// Drawn along the top of the scene instead of the bottom.
  final bool top;
}

/// Where the rendered files go, relative to the project root.
const sourceDir = 'tool/seed/source';

/// Pictures imported from an outside image generator
/// (import_spider_art_test.dart), one path per line. render_art_test.dart
/// doesn't draw over them.
const externalArtList = '$sourceDir/external-art.txt';

String iconPath(String packId, String glyph) =>
    '$sourceDir/icons/$packId/$glyph.png';

/// A pack's empty tile: its pictures without a glyph.
String backgroundPath(String packId) =>
    '$sourceDir/icons/$packId/background.png';

String layerPath(LayerArt art) => '$sourceDir/images/${art.file}.png';
