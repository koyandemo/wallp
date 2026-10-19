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

  /// Which way to draw the icon, first that works (docs/app-client.md
  /// §2): the pack's picture for this app; the pack tile with the app's
  /// logo; the painted style; the app's own icon. A picture that hasn't
  /// downloaded, or won't load, shows the next way instead.
  @override
  Widget build(BuildContext context) {
    final fallback = _packStyle();
    if (theme.appPictures case final pictures?) {
      if (pictures[app.packageName] case final picture?) {
        return PackAppIcon(
          picture: picture,
          ring: pictures.ring,
          shape: theme.iconShape,
          size: size,
          fallback: fallback,
        );
      }
    }
    return fallback;
  }

  Widget _packStyle() {
    final own = _OwnIcon(app: app, size: size);
    // A downloaded pack: every app keeps its own logo, on the pack's tile.
    if (theme.imageIcons case final pack?) {
      return PackTileIcon(pack: pack, app: app, size: size);
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

/// An app the pack has its own picture for: the picture clipped to the
/// user's tile shape, ringed in the pack's ring colour. Shows [fallback]
/// until the picture loads, and for good if it can't.
class PackAppIcon extends StatefulWidget {
  const PackAppIcon({
    super.key,
    required this.picture,
    required this.ring,
    required this.shape,
    required this.size,
    required this.fallback,
  });

  final AssetRef picture;
  final Color ring;
  final IconShape shape;
  final double size;
  final Widget fallback;

  @override
  State<PackAppIcon> createState() => _PackAppIconState();
}

class _PackAppIconState extends State<PackAppIcon> {
  ui.Image? _image;
  AssetRef? _loading;
  bool _inFlight = false;

  /// Like [PackTileIcon]: looks again on every rebuild until the picture is
  /// there, so it shows up once it has downloaded.
  void _load() {
    final wanted = widget.picture;
    if (_loading != wanted) {
      _loading = wanted;
      _image = null;
    }
    if (_image != null || _inFlight) return;
    _inFlight = true;
    SceneAssets.of(context).image(wanted).then((img) {
      _inFlight = false;
      if (mounted && _loading == wanted && img != null) {
        setState(() => _image = img);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final image = _image;
    if (image == null) return widget.fallback;
    return IconShapeTile(
      shape: widget.shape,
      size: widget.size,
      ring: widget.ring,
      child: RawImage(
        image: image,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// An app under a downloaded pack: its own logo (a sample app in a preview:
/// its symbol) on the pack's background picture, or, until that loads, on
/// the pack's tile colour. Clipped to the user's tile shape and ringed in
/// the pack's ring colour.
class PackTileIcon extends StatefulWidget {
  const PackTileIcon({
    super.key,
    required this.pack,
    required this.app,
    required this.size,
  });

  final ImageIconPack pack;
  final InstalledApp app;
  final double size;

  @override
  State<PackTileIcon> createState() => _PackTileIconState();
}

class _PackTileIconState extends State<PackTileIcon> {
  ui.Image? _background;
  AssetRef? _loading;
  bool _inFlight = false;

  /// Reads the tile picture from the phone. Until it's there, every rebuild
  /// looks again, so a preview picks it up once it has downloaded.
  void _load() {
    final wanted = widget.pack.background;
    if (_loading != wanted) {
      _loading = wanted;
      _background = null;
    }
    if (wanted == null || _background != null || _inFlight) return;
    _inFlight = true;
    SceneAssets.of(context).image(wanted).then((img) {
      _inFlight = false;
      if (mounted && _loading == wanted && img != null) {
        setState(() => _background = img);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final pack = widget.pack;
    final size = widget.size;
    final background = _background;
    final app = widget.app;
    return IconShapeTile(
      shape: pack.shape,
      size: size,
      ring: pack.tile == null ? null : pack.ring,
      child: CustomPaint(
        size: Size.square(size),
        painter: PackTilePainter(
          pack: pack,
          appIcon: app.icon,
          logo: app.logo,
          symbol: app.glyph ?? Icons.apps_rounded,
          background: background,
          // Half the tile, so the pack's art shows around the logo.
          iconScale: background == null ? 0.6 : 0.5,
        ),
      ),
    );
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
