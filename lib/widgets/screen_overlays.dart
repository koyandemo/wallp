import 'package:flutter/material.dart';

import '../core/date_format.dart';
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
  });

  final PhoneTheme theme;
  final Color accent;
  final DateTime now;

  /// Distance from the top to the date line. The live wallpaper moves it
  /// down, below the phone's own lock screen clock.
  final double top;

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    final use24h = MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false;
    final eventDate = theme.event.nextDate(now);

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
              Text(
                DateFormatX.clock(now, use24h: use24h),
                style: theme.displayStyle(
                  TextStyle(
                    fontSize: 108,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                    color: theme.accentClock ? accent : p.text,
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          top: top + 192,
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
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    theme.eventIcon,
                    color: _onAccent(theme, accent),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        theme.event.countdownLabel(now),
                        style: theme.bodyStyle(
                          TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: p.text,
                          ),
                        ),
                      ),
                      Text(
                        'until ${theme.event.name} · '
                        '${DateFormatX.shortDate(eventDate)}',
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
      ],
    );
  }
}

/// Countdown widget, app grid and dock, like the design's home screen.
class HomeScreenOverlay extends StatelessWidget {
  const HomeScreenOverlay({
    super.key,
    required this.theme,
    required this.accent,
    required this.now,
  });

  final PhoneTheme theme;
  final Color accent;
  final DateTime now;

  static const _apps = <(String, IconData)>[
    ('Photos', Icons.photo_outlined),
    ('Music', Icons.music_note_outlined),
    ('Maps', Icons.map_outlined),
    ('Weather', Icons.cloud_outlined),
    ('Clock', Icons.schedule_outlined),
    ('Mail', Icons.mail_outline_rounded),
    ('Calendar', Icons.calendar_today_outlined),
    ('Settings', Icons.tune_rounded),
  ];

  static const _dock = <IconData>[
    Icons.phone_outlined,
    Icons.chat_bubble_outline_rounded,
    Icons.public_rounded,
    Icons.camera_alt_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    final eventDate = theme.event.nextDate(now);

    Widget appRow(Iterable<(String, IconData)> apps) => Row(
      children: [
        for (final (name, icon) in apps)
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Icon(icon, color: accent, size: 28),
                ),
                const SizedBox(height: 7),
                Text(
                  name,
                  style: theme.bodyStyle(
                    TextStyle(fontSize: 12, color: p.text),
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
          padding: const EdgeInsets.fromLTRB(24, 64, 24, 0),
          child: Column(
            children: [
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
                      child: Text(
                        theme.name,
                        style: theme.displayStyle(
                          TextStyle(fontSize: 46, height: 1, color: accent),
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
                                theme.event.countdownValue(now),
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
                                'until ${DateFormatX.longDate(eventDate)}',
                                style: theme.bodyStyle(
                                  TextStyle(fontSize: 14, color: p.textMuted),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(theme.eventIcon, color: accent, size: 48),
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
                for (final icon in _dock)
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      icon,
                      color: _onAccent(theme, accent),
                      size: 28,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "LIVE WALLPAPER" title over the animated scene, like the design's live board.
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
