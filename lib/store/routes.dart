import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../catalog/catalog.dart';
import '../data/catalog/catalog_repository.dart';
import '../look/applied_look.dart';
import 'screens/accent_picker_screen.dart';
import 'screens/festival_screen.dart';
import 'screens/font_detail_screen.dart';
import 'screens/icon_pack_screens.dart';
import 'screens/search_screen.dart';
import 'screens/theme_detail_screen.dart';
import 'screens/wallpaper_detail_screen.dart';
import 'widgets/store_look_scope.dart';

/// Opening the store's pages, from anywhere.
abstract final class StoreRoutes {
  /// Each page wears [festivalId]'s colours ("Match app to my theme"),
  /// or the applied theme's when null.
  static Future<T?> _push<T>(
    BuildContext context,
    Widget page, {
    String? festivalId,
  }) => Navigator.of(context).push<T>(
    MaterialPageRoute(
      builder: (_) => StoreLookScope(festivalId: festivalId, child: page),
    ),
  );

  static Catalog _catalog(BuildContext context) =>
      context.read<CatalogRepository>().catalog;

  static Future<void> theme(BuildContext context, String id) => _push(
    context,
    ThemeDetailScreen(themeId: id),
    festivalId: _catalog(context).theme(id)?.festivalId,
  );

  static Future<void> festival(BuildContext context, String id) =>
      _push(context, FestivalScreen(festivalId: id), festivalId: id);

  static Future<void> wallpaper(BuildContext context, String id) => _push(
    context,
    WallpaperDetailScreen(wallpaperId: id),
    festivalId: _catalog(context).wallpaper(id)?.festivalId,
  );

  /// [previewOn]: the look to preview the font on, if not the user's own.
  static Future<void> font(
    BuildContext context,
    String id, {
    AppliedLook? previewOn,
  }) => _push(
    context,
    FontDetailScreen(fontId: id, previewOn: previewOn),
    festivalId: previewOn?.festival.id,
  );

  static Future<void> iconPacks(BuildContext context, {String? filter}) =>
      _push(context, IconPacksScreen(initialFilter: filter));

  static Future<void> iconPack(BuildContext context, String id) => _push(
    context,
    IconPackDetailScreen(packId: id),
    festivalId: _catalog(context).iconPack(id)?.festivalId,
  );

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
    festivalId: theme.festivalId,
  );
}
