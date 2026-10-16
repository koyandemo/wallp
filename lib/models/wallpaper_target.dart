import 'package:flutter/material.dart';

/// Where to apply a wallpaper.
enum WallpaperTarget {
  home('Home screen', Icons.home_rounded),
  lock('Lock screen', Icons.lock_rounded),
  both('Home & lock screens', Icons.smartphone_rounded),

  /// Android only: the animated scene via wallp's live wallpaper service.
  live('Live wallpaper (animated)', Icons.animation_rounded);

  const WallpaperTarget(this.label, this.icon);

  final String label;
  final IconData icon;
}
