import 'package:flutter/material.dart';

import '../models/phone_theme.dart';
import '../models/theme_category.dart';

/// Every category and theme the app ships with.
/// Colors and fonts come from the "Seasonal Phone Themes" design canvas.
class ThemeCatalog {
  ThemeCatalog._();

  static const categories = <ThemeCategory>[
    ThemeCategory(id: 'halloween', name: 'Halloween'),
    ThemeCategory(id: 'christmas', name: 'Christmas'),
    ThemeCategory(id: 'thingyan', name: 'Thingyan'),
    ThemeCategory(id: 'kpop', name: 'Kpop', comingSoon: true),
    ThemeCategory(id: 'mid-autumn', name: 'Mid-Autumn', comingSoon: true),
  ];

  static const themes = <PhoneTheme>[
    PhoneTheme(
      id: 'halloween-night',
      categoryId: 'halloween',
      name: 'Halloween',
      scene: SceneKind.halloween,
      palette: ThemePalette(
        background: Color(0xFF160C24),
        deep: Color(0xFF0D0717),
        surface: Color(0xFF2A1840),
        text: Color(0xFFF4E9C9),
        textMuted: Color(0xFFCDBFA0),
        accentOptions: [
          Color(0xFFFF8A2A),
          Color(0xFF9BE15D),
          Color(0xFFB57BFF),
        ],
      ),
      displayFont: 'Creepster',
      bodyFont: 'Space Grotesk',
      event: ThemeEvent(name: 'Halloween', month: 10, day: 31, unit: 'night'),
      eventIcon: Icons.nightlight_round,
      accentClock: true,
      hasIconPack: true,
    ),
    PhoneTheme(
      id: 'christmas-eve',
      categoryId: 'christmas',
      name: 'Christmas',
      scene: SceneKind.christmas,
      palette: ThemePalette(
        background: Color(0xFF0F3D2E),
        deep: Color(0xFF0A2A20),
        surface: Color(0xFF1A5C41),
        text: Color(0xFFFFF6E5),
        textMuted: Color(0xFFCFE0D7),
        accentOptions: [
          Color(0xFFC8102E),
          Color(0xFFB8862E),
          Color(0xFF1F6B4C),
        ],
      ),
      displayFont: 'Playfair Display',
      bodyFont: 'DM Sans',
      event: ThemeEvent(name: 'Christmas', month: 12, day: 25),
      eventIcon: Icons.card_giftcard_rounded,
      hasIconPack: true,
    ),
    PhoneTheme(
      id: 'thingyan-water',
      categoryId: 'thingyan',
      name: 'Water Festival',
      subtitle: 'သင်္ကြန်',
      scene: SceneKind.thingyan,
      palette: ThemePalette(
        background: Color(0xFF0A3D6B),
        deep: Color(0xFF1477C2),
        surface: Color(0xFF0F4F86),
        text: Color(0xFFFFF8E7),
        textMuted: Color(0xFFCFE6F7),
        accentOptions: [
          Color(0xFFFFC20E),
          Color(0xFF7CC6F0),
          Color(0xFFFF8FA3),
        ],
      ),
      displayFont: 'Baloo 2',
      bodyFont: 'Padauk',
      event: ThemeEvent(name: 'Thingyan', month: 4, day: 13),
      eventIcon: Icons.water_drop_rounded,
      accentClock: true,
      hasIconPack: true,
    ),
  ];

  static List<PhoneTheme> themesIn(String categoryId) =>
      themes.where((t) => t.categoryId == categoryId).toList();

  /// The theme whose festival comes soonest after [now].
  static PhoneTheme nextUp(DateTime now) => themes.reduce(
    (a, b) => b.event.daysUntil(now) < a.event.daysUntil(now) ? b : a,
  );

  static PhoneTheme? byId(String id) {
    for (final t in themes) {
      if (t.id == id) return t;
    }
    return null;
  }
}
