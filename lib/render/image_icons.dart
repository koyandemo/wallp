import '../catalog/catalog.dart';

/// A downloaded icon pack as wallp Home draws it: one picture per glyph
/// key, clipped to the tile shape the user picked.
class ImageIconPack {
  const ImageIconPack({required this.glyphs, required this.shape});

  final Map<String, AssetRef> glyphs;
  final IconShape shape;

  /// The picture for [glyphKey], or null to keep the app's own icon.
  AssetRef? pictureFor(String? glyphKey) =>
      glyphKey == null ? null : glyphs[glyphKey];
}
