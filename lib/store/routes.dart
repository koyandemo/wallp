import 'package:flutter/material.dart';

import '../catalog/catalog.dart';
import 'screens/accent_picker_screen.dart';
import 'screens/festival_screen.dart';
import 'screens/font_detail_screen.dart';
import 'screens/icon_pack_screens.dart';
import 'screens/search_screen.dart';
import 'screens/theme_detail_screen.dart';
import 'screens/wallpaper_detail_screen.dart';

/// Opening the store's pages, from anywhere.
abstract final class StoreRoutes {
  static Future<T?> _push<T>(BuildContext context, Widget page) =>
      Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

  static Future<void> theme(BuildContext context, String id) =>
      _push(context, ThemeDetailScreen(themeId: id));

  static Future<void> festival(BuildContext context, String id) =>
      _push(context, FestivalScreen(festivalId: id));

  static Future<void> wallpaper(BuildContext context, String id) =>
      _push(context, WallpaperDetailScreen(wallpaperId: id));

  static Future<void> font(BuildContext context, String id) =>
      _push(context, FontDetailScreen(fontId: id));

  static Future<void> iconPacks(BuildContext context, {String? filter}) =>
      _push(context, IconPacksScreen(initialFilter: filter));

  static Future<void> iconPack(BuildContext context, String id) =>
      _push(context, IconPackDetailScreen(packId: id));

  static Future<void> search(BuildContext context) =>
      _push(context, const SearchScreen());

  /// The accent picker for [theme]; returns the accent picked, or null.
  static Future<Accent?> accentPicker(
    BuildContext context,
    ThemeDetail theme, {
    String? variantId,
    Accent? current,
  }) => _push<Accent>(
    context,
    AccentPickerScreen(theme: theme, variantId: variantId, current: current),
  );
}
