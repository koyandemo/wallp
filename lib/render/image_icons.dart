import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../catalog/catalog.dart';

/// A downloaded icon pack as wallp Home draws it: one picture per glyph
/// key, clipped to the tile shape the user picked.
class ImageIconPack {
  const ImageIconPack({
    required this.glyphs,
    required this.shape,
    required this.ring,
    this.tile,
  });

  final Map<String, AssetRef> glyphs;
  final IconShape shape;

  /// The pack's tile and ring colours, for apps it has no picture for.
  /// Null [tile] = no tile (line icons straight on the wallpaper).
  final Color? tile;
  final Color ring;

  /// The picture for [glyphKey], or null to frame the app's own icon.
  AssetRef? pictureFor(String? glyphKey) =>
      glyphKey == null ? null : glyphs[glyphKey];
}

/// An app the pack has no picture for: its own icon on the pack's tile, so
/// every app on wallp Home still looks part of the theme.
///
/// Fills the whole canvas; callers clip it to the tile shape (or let the
/// launcher mask it, for a pinned shortcut).
class PackFallbackPainter extends CustomPainter {
  const PackFallbackPainter({
    required this.pack,
    required this.appIcon,
    this.iconScale = 0.6,
  });

  final ImageIconPack pack;
  final ui.Image? appIcon;

  /// The app icon's width as a share of the tile.
  final double iconScale;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    if (pack.tile case final tile?) {
      // Lighter in the middle, like the pack's pictures.
      canvas.drawRect(
        full,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Color.lerp(tile, const Color(0xFFFFFFFF), 0.12)!,
              Color.lerp(tile, const Color(0xFF000000), 0.35)!,
            ],
            radius: 0.75,
          ).createShader(full),
      );
    }
    final icon = appIcon;
    if (icon == null) return;
    final side = size.shortestSide * iconScale;
    final dst = Rect.fromCenter(center: full.center, width: side, height: side);
    // A soft shadow lifts the app's icon off the tile.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        dst.shift(Offset(0, side * 0.04)),
        Radius.circular(side * 0.22),
      ),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, side * 0.06),
    );
    canvas.drawImageRect(
      icon,
      Offset.zero & Size(icon.width.toDouble(), icon.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(PackFallbackPainter old) =>
      old.pack != pack || old.appIcon != appIcon || old.iconScale != iconScale;
}
