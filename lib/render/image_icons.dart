import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../catalog/catalog.dart';

/// A downloaded icon pack as wallp Home draws it: every app's own logo on
/// the pack's background tile, clipped to the tile shape the user picked.
class ImageIconPack {
  const ImageIconPack({
    required this.shape,
    required this.ring,
    required this.glyph,
    this.tile,
    this.background,
  });

  /// [pack] in the user's [shape].
  factory ImageIconPack.of(IconPack pack, IconShape shape) => ImageIconPack(
    shape: shape,
    ring: Color(pack.ring.argb),
    glyph: Color(pack.glyph.argb),
    tile: pack.tile == null ? null : Color(pack.tile!.argb),
    background: pack.background,
  );

  final IconShape shape;

  /// The pack's tile picture, drawn under every app. Null, or until it
  /// loads: a plain [tile] instead.
  final AssetRef? background;

  /// The pack's colours. Null [tile] = no tile.
  final Color? tile;
  final Color ring;

  /// For the symbols of sample apps in previews, which have no logo.
  final Color glyph;
}

/// An app under a downloaded pack: its own logo on the pack's tile, so
/// every app on wallp Home looks part of the theme while staying
/// recognisable.
///
/// Fills the whole canvas; callers clip it to the tile shape (or let the
/// launcher mask it, for a pinned shortcut).
class PackTilePainter extends CustomPainter {
  const PackTilePainter({
    required this.pack,
    required this.appIcon,
    this.logo,
    this.symbol,
    this.background,
    this.iconScale = 0.6,
  });

  final ImageIconPack pack;
  final ui.Image? appIcon;

  /// Drawn when there's no [logo] or [appIcon]: a sample app in a preview.
  final IconData? symbol;

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
    if (icon == null) {
      if (symbol case final symbol?) _paintSymbol(canvas, symbol, full, side);
      return;
    }
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

  void _paintSymbol(Canvas canvas, IconData symbol, Rect full, double side) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(symbol.codePoint),
        style: TextStyle(
          fontFamily: symbol.fontFamily,
          package: symbol.fontPackage,
          fontSize: side,
          color: pack.glyph,
          shadows: const [Shadow(color: Color(0x66000000), blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      full.center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
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
  bool shouldRepaint(PackTilePainter old) =>
      old.pack != pack ||
      old.appIcon != appIcon ||
      old.logo != logo ||
      old.symbol != symbol ||
      old.background != background ||
      old.iconScale != iconScale;
}
