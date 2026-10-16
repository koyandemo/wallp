import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Which painted scene draws this theme's wallpapers (built in Step 4).
enum SceneKind { halloween, christmas, thingyan }

/// Colors shared by a theme's lock, home and live screens.
class ThemePalette {
  const ThemePalette({
    required this.background,
    required this.deep,
    required this.surface,
    required this.text,
    required this.textMuted,
    required this.accentOptions,
  });

  /// Main sky / backdrop color.
  final Color background;

  /// Darkest shade, used for silhouettes and the foreground ground.
  final Color deep;

  /// Card and icon-tile fill.
  final Color surface;

  final Color text;
  final Color textMuted;

  /// First entry is the default accent; the rest are user-selectable.
  final List<Color> accentOptions;

  Color get accent => accentOptions.first;
}

/// A yearly date the theme counts down to (e.g. 31 October).
class ThemeEvent {
  const ThemeEvent({
    required this.name,
    required this.month,
    required this.day,
    this.unit = 'day',
  });

  final String name;
  final int month;
  final int day;

  /// Countdown word: "day", or "night" for Halloween.
  final String unit;

  /// "17 nights left", "1 day left", or "Happy Halloween!" on the day.
  String countdownLabel(DateTime now) {
    final days = daysUntil(now);
    if (days == 0) return 'Happy $name!';
    return '${countdownValue(now)} left';
  }

  /// "17 nights", "1 day", or "Today" on the day.
  String countdownValue(DateTime now) {
    final days = daysUntil(now);
    if (days == 0) return 'Today';
    return '$days ${days == 1 ? unit : '${unit}s'}';
  }

  /// Next occurrence on or after [now]'s date.
  DateTime nextDate(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final thisYear = DateTime(now.year, month, day);
    return thisYear.isBefore(today)
        ? DateTime(now.year + 1, month, day)
        : thisYear;
  }

  /// Whole days from [now]'s date to the event; 0 on the day itself.
  int daysUntil(DateTime now) {
    final today = DateTime.utc(now.year, now.month, now.day);
    final next = nextDate(now);
    return DateTime.utc(
      next.year,
      next.month,
      next.day,
    ).difference(today).inDays;
  }
}

class PhoneTheme {
  const PhoneTheme({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.scene,
    required this.palette,
    required this.displayFont,
    required this.bodyFont,
    required this.event,
    this.eventIcon = Icons.event,
    this.accentClock = false,
    this.hasIconPack = false,
    this.subtitle,
  });

  final String id;
  final String categoryId;
  final String name;

  /// Optional second title line, e.g. the Burmese name for Thingyan.
  final String? subtitle;

  final SceneKind scene;
  final ThemePalette palette;

  /// Google Fonts family names.
  final String displayFont;
  final String bodyFont;

  final ThemeEvent event;

  /// Icon in the lock screen's countdown card.
  final IconData eventIcon;

  /// Lock-screen clock drawn in the accent color instead of the text color.
  final bool accentClock;

  /// Has themed app icons (home screen + icon shortcuts), drawn by
  /// ThemedIconPainter in this theme's [scene] style.
  final bool hasIconPack;

  TextStyle displayStyle([TextStyle? style]) =>
      GoogleFonts.getFont(displayFont, textStyle: style);

  TextStyle bodyStyle([TextStyle? style]) =>
      GoogleFonts.getFont(bodyFont, textStyle: style);
}
