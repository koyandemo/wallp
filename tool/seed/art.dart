/// Art for the mock catalog's downloadable files, shared by
/// render_art_test.dart (draws the PNGs) and generate.dart (hashes them).
///
/// Pack looks come from the "wallp Store Flow" design
/// canvas. In the real product, designers upload this art in the dashboard.
library;

/// How a pack's tile picture is drawn.
enum PackLook {
  /// Comic book: a solid tile with a web across it in the ring colour.
  comic,

  /// A dark tile with a soft glow in the ring colour and a glowing
  /// perspective grid in the glyph colour along the bottom.
  neon,
}

/// How a downloadable icon pack's tile is drawn. Colours are `0xRRGGBB`;
/// [glyph] is for the symbols of sample apps in the store's previews.
class PackArt {
  const PackArt({
    required this.id,
    required this.look,
    required this.shape,
    required this.tile,
    required this.glyph,
    required this.ring,
  });

  final String id;
  final PackLook look;

  /// squircle, circle, square or leaf (see IconShape in the models).
  final String shape;
  final int tile;
  final int glyph;
  final int ring;
}

/// Spider Night's Web Slinger pack (spider_night.dart).
const webSlinger = PackArt(
  id: 'web-slinger',
  look: PackLook.comic,
  shape: 'squircle',
  tile: 0xD3202A,
  glyph: 0xFFFFFF,
  ring: 0x0A0A12,
);

/// Neon Night's Neon Glow pack (neon_night.dart).
const neonGlow = PackArt(
  id: 'neon-glow',
  look: PackLook.neon,
  shape: 'circle',
  tile: 0x14062B,
  glyph: 0x22E4FF,
  ring: 0xFF3EA5,
);

/// Every pack whose tile render_art_test.dart draws.
const packArt = [webSlinger, neonGlow];

/// Icon tile pictures are square, this many pixels.
const iconPixels = 256;

/// Scene layer images (transparent PNG, drawn along the bottom of a scene).
enum LayerArt {
  /// Night city skyline with lit windows, for Spider Night.
  spiderSkyline('spider-skyline', 1080, 1240),

  /// A spider web across the top-left corner, for Spider Night.
  spiderWeb('spider-web', 1080, 1080);

  const LayerArt(this.file, this.width, this.height);

  final String file;
  final int width;
  final int height;
}

/// Where the rendered files go, relative to the project root.
const sourceDir = 'tool/seed/source';

/// Pictures imported from an outside image generator
/// (import_spider_art_test.dart), one path per line. render_art_test.dart
/// doesn't draw over them.
const externalArtList = '$sourceDir/external-art.txt';

/// A pack's tile picture.
String backgroundPath(String packId) =>
    '$sourceDir/icons/$packId/background.png';

String layerPath(LayerArt art) => '$sourceDir/images/${art.file}.png';
