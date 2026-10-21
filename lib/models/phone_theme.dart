import 'package:flutter/material.dart';

import '../catalog/catalog.dart' show IconShape;
import '../render/font_registry.dart';
import '../render/image_icons.dart';
import '../render/layered_scene.dart';

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
    this._iconStyle,
    this.layered,
    this.imageIcons,
    this.iconShape = IconShape.squircle,
    this.labelColor = Colors.white,
    this.systemLabels = false,
    this.labelFont,
  });

  final String id;
  final String categoryId;
  final String name;

  /// Optional second title line, e.g. the Burmese name for Thingyan.
  final String? subtitle;

  /// The painter for this theme's wallpaper; null draws a placeholder
  /// (catalog themes on the `layers` engine, until it exists: Phase 6).
  final SceneKind? scene;
  final ThemePalette palette;

  /// Google Fonts family names.
  final String displayFont;
  final String bodyFont;

  /// What the countdown counts to; null for undated collections (Minimal).
  final ThemeEvent? event;

  /// Icon in the lock screen's countdown card.
  final IconData eventIcon;

  /// Lock-screen clock drawn in the accent color instead of the text color.
  final bool accentClock;

  /// Has themed app icons (home screen + icon shortcuts), drawn by
  /// ThemedIconPainter in the [iconStyle] style.
  final bool hasIconPack;

  final SceneKind? _iconStyle;

  /// The ThemedIconPainter style: the applied icon pack's, else the
  /// scene's.
  SceneKind? get iconStyle => _iconStyle ?? scene;

  /// A dashboard-made scene for the `layers` engine; drawn instead of the
  /// placeholder when [scene] is null.
  final LayeredScene? layered;

  /// A downloaded icon pack; drawn instead of [iconStyle] icons.
  final ImageIconPack? imageIcons;

  /// The tile shape for painted icons (downloaded packs carry their own).
  final IconShape iconShape;

  /// App names under icons on wallp Home.
  final Color labelColor;

  /// App names in the phone's own font instead of [bodyFont].
  final bool systemLabels;

  /// Google Fonts family for app names; null = [bodyFont].
  final String? labelFont;

  /// For app names anywhere on wallp Home: in [labelColor] with
  /// [labelShadows], in the label font. [style] sets size and weight.
  TextStyle appNameStyle([TextStyle? style]) => labelStyle(
    (style ?? const TextStyle()).copyWith(
      color: labelColor,
      shadows: labelShadows,
    ),
  );

  /// For app names under icons.
  TextStyle labelStyle(TextStyle style) => systemLabels
      ? style
      : FontRegistry.shared.style(labelFont ?? bodyFont, style);

  /// Behind [labelColor] so names read on any wallpaper: dark behind light
  /// names, light behind dark ones.
  List<Shadow> get labelShadows => [
    Shadow(
      color: labelColor.computeLuminance() > 0.4
          ? const Color(0xCC000000)
          : const Color(0x99FFFFFF),
      blurRadius: 6,
      offset: const Offset(0, 1),
    ),
  ];

  /// In the downloaded font if this engine loaded it, else the system font.
  TextStyle displayStyle([TextStyle? style]) =>
      FontRegistry.shared.style(displayFont, style);

  TextStyle bodyStyle([TextStyle? style]) =>
      FontRegistry.shared.style(bodyFont, style);

  PhoneTheme copyWith({
    String? displayFont,
    String? bodyFont,
    bool? accentClock,
    bool? hasIconPack,
    SceneKind? iconStyle,
    ImageIconPack? imageIcons,
    IconShape? iconShape,
    Color? labelColor,
    bool? systemLabels,
    String? labelFont,
  }) => PhoneTheme(
    id: id,
    categoryId: categoryId,
    name: name,
    subtitle: subtitle,
    scene: scene,
    palette: palette,
    displayFont: displayFont ?? this.displayFont,
    bodyFont: bodyFont ?? this.bodyFont,
    event: event,
    eventIcon: eventIcon,
    accentClock: accentClock ?? this.accentClock,
    hasIconPack: hasIconPack ?? this.hasIconPack,
    iconStyle: iconStyle ?? _iconStyle,
    layered: layered,
    imageIcons: imageIcons ?? this.imageIcons,
    iconShape: iconShape ?? this.iconShape,
    labelColor: labelColor ?? this.labelColor,
    systemLabels: systemLabels ?? this.systemLabels,
    labelFont: labelFont ?? this.labelFont,
  );
}
