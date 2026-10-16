import 'package:flutter/material.dart';

import '../icons/themed_icon_painter.dart';
import '../models/phone_theme.dart';
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
    if (theme.hasIconPack) {
      return ThemedIcon(
        style: theme.scene,
        accent: accent,
        glyph: app.glyph,
        appIcon: app.icon,
        size: size,
      );
    }
    final icon = app.icon;
    return SizedBox.square(
      dimension: size,
      child: icon == null
          ? Icon(Icons.apps_rounded, size: size * 0.7, color: Colors.white)
          : RawImage(image: icon, filterQuality: FilterQuality.medium),
    );
  }
}

/// Icon with its label underneath, for the home grid and the app drawer.
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
