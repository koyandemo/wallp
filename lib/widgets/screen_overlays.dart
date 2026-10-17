import 'package:flutter/material.dart';

import '../core/date_format.dart';
import '../launcher/launcher_icon.dart';
import '../look/accent_paint.dart';
import '../services/icon_pack_service.dart';
import '../models/phone_theme.dart';

/// Icon color that reads on top of [accent]: dark on light accents
/// (orange, yellow), light on dark ones (Christmas red), as in the design.
Color _onAccent(PhoneTheme theme, Color accent) =>
    ThemeData.estimateBrightnessForColor(accent) == Brightness.light
    ? theme.palette.background
    : theme.palette.text;

/// Date, big clock and countdown card, laid out like the design's lock screen.
class LockScreenOverlay extends StatelessWidget {
  const LockScreenOverlay({
    super.key,
    required this.theme,
    required this.accent,
    required this.now,
    this.top = 76,
    this.clockColor,
    this.clockScale = 1,
    this.clockGradient,
    this.accentGradient,
    this.onAccent,
    this.showShortcuts = false,
  });

  final PhoneTheme theme;
  final Color accent;
  final DateTime now;

  /// The applied clock style's colour; null = accent or text, by theme.
  final Color? clockColor;

  /// The applied clock style's size (1 = the design's medium).
  final double clockScale;

  /// Paints the clock when it's drawn in a gradient accent.
  final Gradient? clockGradient;

  /// Fills the countdown badge when the accent is a gradient.
  final Gradient? accentGradient;

  /// The badge icon's colour; null works it out from [accent].
  final Color? onAccent;

  /// Draws the flashlight and camera shortcuts a phone's lock screen has.
  /// Previews only: on the phone, the system draws its own.
  final bool showShortcuts;

  /// Distance from the top to the date line. The live wallpaper moves it
  /// down, below the phone's own lock screen clock.
  final double top;

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    final use24h = MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false;
    final event = theme.event;

    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: top,
          child: Column(
            children: [
              Text(
                DateFormatX.longDate(now),
                style: theme.bodyStyle(
                  TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: p.text,
                  ),
                ),
              ),
              GradientText(
                gradient: clockGradient,
                child: Text(
                  DateFormatX.clock(now, use24h: use24h),
                  style: theme.displayStyle(
                    TextStyle(
                      fontSize: 108 * clockScale,
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                      color:
                          clockColor ?? (theme.accentClock ? accent : p.text),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Undated collections (Minimal) have no countdown card.
        if (event != null)
          Positioned(
            left: 24,
            right: 24,
            top: top + 192 + 108 * (clockScale - 1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: p.background.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: p.text.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accentGradient == null ? accent : null,
                      gradient: accentGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      theme.eventIcon,
                      color: onAccent ?? _onAccent(theme, accent),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.countdownLabel(now),
                          style: theme.bodyStyle(
                            TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                              color: p.text,
                            ),
                          ),
                        ),
                        Text(
                          'until ${event.name} · '
                          '${DateFormatX.shortDate(event.nextDate(now))}',
                          style: theme.bodyStyle(
                            TextStyle(fontSize: 14, color: p.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (showShortcuts)
          Positioned(
            left: 36,
            right: 36,
            bottom: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final icon in const [
                  Icons.flashlight_on_rounded,
                  Icons.photo_camera_rounded,
                ])
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: p.background.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                      border: Border.all(color: p.text.withValues(alpha: 0.18)),
                    ),
                    child: GradientText(
                      gradient: accentGradient,
                      child: Icon(icon, size: 28, color: accent),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Countdown widget, app grid and dock, like the design's home screen. The
/// apps are drawn the way wallp Home draws them: the theme's own icons.
class HomeScreenOverlay extends StatelessWidget {
  const HomeScreenOverlay({
    super.key,
    required this.theme,
    required this.accent,
    required this.now,
    this.accentGradient,
    this.clockColor,
    this.clockScale = 1,
    this.clockGradient,
  });

  final PhoneTheme theme;
  final Color accent;
  final DateTime now;

  /// Paints the theme name and countdown icon when the accent is a gradient.
  final Gradient? accentGradient;

  /// The wallp Home clock above the widget, as the user set it; without
  /// [clockColor], the theme's default.
  final Color? clockColor;
  final double clockScale;
  final Gradient? clockGradient;

  static const _apps = [
    InstalledApp(
      packageName: 'com.google.android.apps.photos',
      label: 'Photos',
    ),
    InstalledApp(packageName: 'com.spotify.music', label: 'Music'),
    InstalledApp(packageName: 'com.google.android.apps.maps', label: 'Maps'),
    InstalledApp(packageName: 'com.android.weather', label: 'Weather'),
    InstalledApp(packageName: 'com.google.android.deskclock', label: 'Clock'),
    InstalledApp(packageName: 'com.android.email', label: 'Mail'),
    InstalledApp(packageName: 'com.google.android.calendar', label: 'Calendar'),
    InstalledApp(packageName: 'com.android.settings', label: 'Settings'),
  ];

  static const _dock = [
    InstalledApp(packageName: 'com.google.android.dialer', label: 'Phone'),
    InstalledApp(
      packageName: 'com.google.android.apps.messaging',
      label: 'Messages',
    ),
    InstalledApp(packageName: 'com.android.chrome', label: 'Chrome'),
    InstalledApp(packageName: 'com.android.camera', label: 'Camera'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    final event = theme.event;

    Widget appRow(Iterable<InstalledApp> apps) => Row(
      children: [
        for (final app in apps)
          Expanded(
            child: Column(
              children: [
                LauncherIcon(app: app, theme: theme, accent: accent, size: 62),
                const SizedBox(height: 7),
                Text(
                  app.label,
                  style: theme.labelStyle(
                    TextStyle(
                      fontSize: 12,
                      color: theme.labelColor,
                      shadows: theme.labelShadows,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
          child: Column(
            children: [
              GradientText(
                gradient: clockColor != null
                    ? clockGradient
                    : theme.accentClock
                    ? accentGradient
                    : null,
                child: Text(
                  DateFormatX.clock(
                    now,
                    use24h:
                        MediaQuery.maybeAlwaysUse24HourFormatOf(context) ??
                        false,
                  ),
                  style: theme.displayStyle(
                    TextStyle(
                      fontSize: 64 * clockScale,
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                      color:
                          clockColor ??
                          (theme.accentClock ? accent : Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 168,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: p.background.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: p.text.withValues(alpha: 0.18)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: GradientText(
                        gradient: accentGradient,
                        child: Text(
                          theme.name,
                          style: theme.displayStyle(
                            TextStyle(fontSize: 46, height: 1, color: accent),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                event?.countdownValue(now) ?? 'Any time',
                                style: theme.bodyStyle(
                                  TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w700,
                                    color: p.text,
                                  ),
                                ),
                              ),
                              Text(
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                event == null
                                    ? 'Fits every season'
                                    : 'until ${DateFormatX.longDate(event.nextDate(now))}',
                                style: theme.bodyStyle(
                                  TextStyle(fontSize: 14, color: p.textMuted),
                                ),
                              ),
                            ],
                          ),
                        ),
                        GradientText(
                          gradient: accentGradient,
                          child: Icon(theme.eventIcon, color: accent, size: 48),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              appRow(_apps.take(4)),
              const SizedBox(height: 22),
              appRow(_apps.skip(4)),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 22,
          height: 90,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: p.surface.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: p.text.withValues(alpha: 0.14)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final app in _dock)
                  LauncherIcon(
                    app: app,
                    theme: theme,
                    accent: accent,
                    size: 62,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class LiveWallpaperOverlay extends StatelessWidget {
  const LiveWallpaperOverlay({
    super.key,
    required this.theme,
    required this.accent,
  });

  final PhoneTheme theme;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    return Positioned(
      left: 0,
      right: 0,
      top: 112,
      child: Column(
        children: [
          Text(
            'LIVE WALLPAPER',
            style: theme.bodyStyle(
              TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.3,
                color: p.textMuted,
              ),
            ),
          ),
          Text(
            theme.name,
            textAlign: TextAlign.center,
            style: theme.displayStyle(
              TextStyle(
                fontSize: 46,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: accent,
              ),
            ),
          ),
          if (theme.subtitle != null)
            Text(
              theme.subtitle!,
              style: theme.bodyStyle(
                TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: p.text,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
