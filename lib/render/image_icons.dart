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
    this.background,
  });

  final Map<String, AssetRef> glyphs;
  final IconShape shape;

  /// The pack's empty tile picture, drawn under apps it has no picture for.
  /// Null = they get a plain [tile] instead.
  final AssetRef? background;

  /// The pack's tile and ring colours, for apps it has no picture for.
  /// Null [tile] = no tile (line icons straight on the wallpaper).
  final Color? tile;
  final Color ring;

  /// The picture for [glyphKey]: previews only, whose sample apps have no
  /// icon. Real apps keep their own logo, on the pack's tile.
  AssetRef? pictureFor(String? glyphKey) =>
      glyphKey == null ? null : glyphs[glyphKey];
}

/// An app under a downloaded pack: its own logo on the pack's tile, so
/// every app on wallp Home looks part of the theme while staying
/// recognisable.
///
/// Fills the whole canvas; callers clip it to the tile shape (or let the
/// launcher mask it, for a pinned shortcut).
class PackFallbackPainter extends CustomPainter {
  const PackFallbackPainter({
    required this.pack,
    required this.appIcon,
    this.logo,
    this.background,
    this.iconScale = 0.6,
  });

  final ImageIconPack pack;
  final ui.Image? appIcon;

  /// [InstalledApp.logo]: drawn instead of [appIcon] when there is one, so
  /// the app's own background makes way for the pack's.
  final ui.Image? logo;

  /// The pack's loaded [ImageIconPack.background], drawn edge to edge like
  /// its pictures. Null = a gradient of the pack's tile colour.
  final ui.Image? background;

  /// The app icon's width as a share of the tile. A [logo] layer is drawn
  /// twice as wide, since adaptive icons keep their logo in its middle half.
  final double iconScale;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    if (background case final bg?) {
      canvas.drawImageRect(
        bg,
        Offset.zero & Size(bg.width.toDouble(), bg.height.toDouble()),
        full,
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else if (pack.tile case final tile?) {
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
    final side = size.shortestSide * iconScale;
    if (logo case final logo?) {
      _paintLogo(
        canvas,
        logo,
        Rect.fromCenter(center: full.center, width: side * 2, height: side * 2),
      );
      return;
    }
    final icon = appIcon;
    if (icon == null) return;
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

  /// [logo] over a soft shadow in its own shape.
  void _paintLogo(Canvas canvas, ui.Image logo, Rect dst) {
    final src =
        Offset.zero & Size(logo.width.toDouble(), logo.height.toDouble());
    final blur = dst.width * 0.02;
    canvas
      ..drawImageRect(
        logo,
        src,
        dst.shift(Offset(0, dst.width * 0.015)),
        Paint()
          ..colorFilter = const ColorFilter.mode(
            Color(0x66000000),
            BlendMode.srcIn,
          )
          ..imageFilter = ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      )
      ..drawImageRect(
        logo,
        src,
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      );
  }

  @override
  bool shouldRepaint(PackFallbackPainter old) =>
      old.pack != pack ||
      old.appIcon != appIcon ||
      old.logo != logo ||
      old.background != background ||
      old.iconScale != iconScale;
}
