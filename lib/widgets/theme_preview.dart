import 'package:flutter/material.dart';

import '../models/phone_theme.dart';
import '../scenes/scene_painter.dart';
import '../scenes/scene_view.dart';
import 'screen_overlays.dart';

export '../scenes/scene_painter.dart' show kSceneSize;

/// Which phone screen a preview shows.
enum PhoneScreen {
  lock('Lock'),
  home('Home'),
  live('Live');

  const PhoneScreen(this.label);

  final String label;
}

/// A theme's [screen], drawn at [kSceneSize] and scaled to fit its box.
class ThemePreview extends StatelessWidget {
  const ThemePreview({
    super.key,
    required this.theme,
    required this.now,
    this.screen = PhoneScreen.lock,
    this.animate = false,
    this.accent,
    this.accentGradient,
    this.clockColor,
    this.clockScale = 1,
    this.clockGradient,
  });

  final PhoneTheme theme;
  final DateTime now;
  final PhoneScreen screen;
  final bool animate;

  /// Overrides the theme's default accent.
  final Color? accent;

  /// The accent as a gradient (a gradient accent); null for a solid one.
  final Gradient? accentGradient;

  /// The lock clock exactly as the user set it (colour, size, gradient);
  /// without [clockColor], the theme's default.
  final Color? clockColor;
  final double clockScale;
  final Gradient? clockGradient;

  @override
  Widget build(BuildContext context) {
    final accent = this.accent ?? theme.palette.accent;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox.fromSize(
        size: kSceneSize,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SceneView(theme: theme, animate: animate, accent: accent),
            switch (screen) {
              PhoneScreen.lock => LockScreenOverlay(
                theme: theme,
                accent: accent,
                now: now,
                clockColor: clockColor,
                clockScale: clockScale,
                clockGradient: clockColor != null
                    ? clockGradient
                    : theme.accentClock
                    ? accentGradient
                    : null,
                accentGradient: accentGradient,
                showShortcuts: true,
              ),
              PhoneScreen.home => HomeScreenOverlay(
                theme: theme,
                accent: accent,
                now: now,
                accentGradient: accentGradient,
                clockColor: clockColor,
                clockScale: clockScale,
                clockGradient: clockGradient,
              ),
              PhoneScreen.live => Stack(
                children: [LiveWallpaperOverlay(theme: theme, accent: accent)],
              ),
            },
          ],
        ),
      ),
    );
  }
}
