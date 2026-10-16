import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../catalog/catalog.dart';
import '../../core/app_theme.dart';
import '../../core/store_palette.dart';
import '../../data/catalog/catalog_repository.dart';
import '../../look/look_controller.dart';
import '../../render/font_registry.dart';
import '../state/user_store.dart';

/// "Match app to my theme": the store wears a festival's colours.
///
/// With [festivalId], this part of the store wears that festival's look (a
/// festival page, a theme of it). Without, the applied theme's festival.
/// With the setting off, or an undated collection, the plain wallp look.
class StoreLookScope extends StatelessWidget {
  const StoreLookScope({super.key, this.festivalId, required this.child});

  final String? festivalId;
  final Widget child;

  /// Built themes by festival ID: building one isn't free, and pages
  /// rebuild often.
  static final _themes = <String, ThemeData>{};
  static final _base = AppTheme.dark();

  /// Which festival's look applies here, or null for the plain one.
  static Festival? festivalFor(BuildContext context, String? festivalId) {
    if (!context.watch<UserStore>().setting(UserSetting.matchAppToTheme)) {
      return null;
    }
    final repo = context.watch<CatalogRepository>();
    if (festivalId != null) {
      return repo.isReady ? repo.catalog.festival(festivalId) : null;
    }
    final looks = context.watch<LookController>();
    // The default look (nothing applied) is a suggestion: keep the app plain.
    return looks.isApplied ? looks.look?.festival : null;
  }

  @override
  Widget build(BuildContext context) {
    final festival = festivalFor(context, festivalId);
    final repo = context.watch<CatalogRepository>();
    final ThemeData data;
    if (festival == null ||
        festival.kind == FestivalKind.collection ||
        !repo.isReady) {
      data = _base;
    } else {
      final palette = StorePalette.of(festival.look, repo.catalog);
      // Rebuilt once the display font is loaded, so titles switch to it.
      final fontReady =
          palette.displayFamily != null &&
          FontRegistry.shared.loadedFamily(palette.displayFamily!) != null;
      data = _themes.putIfAbsent(
        '${festival.id}:$fontReady',
        () => AppTheme.dark(palette),
      );
    }
    return AnimatedTheme(
      data: data,
      duration: const Duration(milliseconds: 300),
      child: child,
    );
  }
}
