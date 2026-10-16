import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../catalog/catalog.dart';

import '../icons/themed_icon_painter.dart';
import '../models/phone_theme.dart';
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
    // A downloaded pack: its picture for this app, else the app's own icon.
    if (theme.imageIcons case final pack?) {
      final picture = pack.pictureFor(app.glyphKey);
      if (picture == null) return own;
      return PackPictureIcon(
        picture: picture,
        shape: pack.shape,
        size: size,
        placeholder: own,
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
    return switch (widget.shape) {
      IconShape.circle => ClipOval(child: picture),
      IconShape.square => ClipRRect(
        borderRadius: BorderRadius.circular(s * 0.12),
        child: picture,
      ),
      IconShape.squircle => ClipRRect(
        borderRadius: BorderRadius.circular(s * 0.3),
        child: picture,
      ),
      IconShape.leaf => ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(s * 0.5),
          topRight: Radius.circular(s * 0.5),
          bottomRight: Radius.circular(s * 0.5),
          bottomLeft: Radius.circular(s * 0.12),
        ),
        child: picture,
      ),
    };
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

  static const _labelShadow = [
    Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
  ];

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
                style: theme.bodyStyle(
                  const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    shadows: _labelShadow,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
