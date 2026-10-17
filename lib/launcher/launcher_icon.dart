import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../catalog/catalog.dart';

import '../icons/themed_icon_painter.dart';
import '../models/phone_theme.dart';
import '../render/icon_shape.dart';
import '../render/image_icons.dart';
import '../render/scene_assets.dart';
import '../services/icon_pack_service.dart';

/// An app's icon in the current theme's style (Halloween, Christmas or
/// Thingyan icons), or the app's own icon for themes without an icon pack.
class LauncherIcon extends StatelessWidget {
  const LauncherIcon({
    super.key,
    required this.app,
    required this.theme,
    required this.accent,
    this.size = 56,
  });

  final InstalledApp app;
  final PhoneTheme theme;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final own = _OwnIcon(app: app, size: size);
    // A downloaded pack: its picture for this app, else the app's own icon
    // framed in the pack's tile.
    if (theme.imageIcons case final pack?) {
      final framed = PackFallbackIcon(pack: pack, app: app, size: size);
      final picture = pack.pictureFor(app.glyphKey);
      if (picture == null) return framed;
      return PackPictureIcon(
        picture: picture,
        shape: pack.shape,
        size: size,
        placeholder: framed,
      );
    }
    final style = theme.iconStyle;
    if (theme.hasIconPack && style != null) {
      return ThemedIcon(
        style: style,
        accent: accent,
        glyph: app.glyph,
        appIcon: app.icon,
        size: size,
        shape: theme.iconShape,
      );
    }
    return own;
  }
}

class _OwnIcon extends StatelessWidget {
  const _OwnIcon({required this.app, required this.size});

  final InstalledApp app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = app.icon;
    return SizedBox.square(
      dimension: size,
      child: icon == null
          ? Icon(Icons.apps_rounded, size: size * 0.7, color: Colors.white)
          : RawImage(image: icon, filterQuality: FilterQuality.medium),
    );
  }
}

/// An app a downloaded pack has no picture for: its own icon on the pack's
/// background picture, or, without one (or until it loads), on the pack's
/// tile colour ringed in its ring colour. Clipped to the user's tile shape.
class PackFallbackIcon extends StatefulWidget {
  const PackFallbackIcon({
    super.key,
    required this.pack,
    required this.app,
    required this.size,
  });

  final ImageIconPack pack;
  final InstalledApp app;
  final double size;

  @override
  State<PackFallbackIcon> createState() => _PackFallbackIconState();
}

class _PackFallbackIconState extends State<PackFallbackIcon> {
  ui.Image? _background;
  AssetRef? _loading;

  void _load() {
    final wanted = widget.pack.background;
    if (_loading == wanted) return;
    _loading = wanted;
    _background = null;
    if (wanted == null) return;
    SceneAssets.of(context).image(wanted).then((img) {
      if (mounted && _loading == wanted) setState(() => _background = img);
    });
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final pack = widget.pack;
    final size = widget.size;
    final background = _background;
    final icon = widget.app.icon;
    final tile = IconShapeClip(
      shape: pack.shape,
      size: size,
      child: icon == null && background == null
          ? Icon(Icons.apps_rounded, size: size * 0.55, color: Colors.white)
          : CustomPaint(
              size: Size.square(size),
              painter: PackFallbackPainter(
                pack: pack,
                appIcon: icon,
                background: background,
                // The size of the pack's own glyphs, so its art shows around.
                iconScale: background == null ? 0.6 : 0.5,
              ),
            ),
    );
    // The background picture has its own rim.
    if (background != null) {
      return SizedBox.square(dimension: size, child: tile);
    }
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: iconShapeRadius(pack.shape, size),
          border: Border.all(color: pack.ring, width: size * 0.035),
        ),
        child: tile,
      ),
    );
  }
}

/// A downloaded icon-pack picture, clipped to the user's tile shape. Shows
/// [placeholder] until the picture loads, or if it can't.
class PackPictureIcon extends StatefulWidget {
  const PackPictureIcon({
    super.key,
    required this.picture,
    required this.shape,
    required this.size,
    required this.placeholder,
  });

  final AssetRef picture;
  final IconShape shape;
  final double size;
  final Widget placeholder;

  @override
  State<PackPictureIcon> createState() => _PackPictureIconState();
}

class _PackPictureIconState extends State<PackPictureIcon> {
  ui.Image? _image;
  AssetRef? _loading;

  void _load() {
    if (_loading == widget.picture) return;
    _loading = widget.picture;
    _image = null;
    final wanted = widget.picture;
    SceneAssets.of(context).image(wanted).then((img) {
      if (mounted && _loading == wanted) setState(() => _image = img);
    });
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final image = _image;
    if (image == null) return widget.placeholder;
    final s = widget.size;
    final picture = SizedBox.square(
      dimension: s,
      child: RawImage(image: image, filterQuality: FilterQuality.medium),
    );
    return IconShapeClip(shape: widget.shape, size: s, child: picture);
  }
}

class LauncherAppTile extends StatelessWidget {
  const LauncherAppTile({
    super.key,
    required this.app,
    required this.theme,
    required this.accent,
    required this.onTap,
    required this.onLongPress,
    this.showLabel = true,
    this.iconSize = 56,
  });

  final InstalledApp app;
  final PhoneTheme theme;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool showLabel;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: app.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        onLongPress: onLongPress,
        radius: iconSize * 0.7,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LauncherIcon(
              app: app,
              theme: theme,
              accent: accent,
              size: iconSize,
            ),
            if (showLabel) ...[
              const SizedBox(height: 6),
              Text(
                app.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.appNameStyle(const TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
