import 'package:flutter/material.dart';

import '../catalog/catalog.dart';
import 'app_colors.dart';

/// The store's own colours: the plain wallp look, or a festival's
/// ("Match app to my theme"). Read with `context.palette`.
@immutable
class StorePalette extends ThemeExtension<StorePalette> {
  const StorePalette({
    required this.background,
    required this.surface,
    required this.surface2,
    required this.outline,
    required this.nav,
    required this.text,
    required this.muted,
    required this.brand,
    this.displayFamily,
  });

  /// The plain wallp look.
  static const base = StorePalette(
    background: AppColors.background,
    surface: AppColors.surface,
    surface2: AppColors.surfaceHigh,
    outline: AppColors.outline,
    nav: Color(0xFF15121B),
    text: AppColors.textPrimary,
    muted: AppColors.textSecondary,
    brand: AppColors.brand,
  );

  /// A festival's look; text stays the light ink every look is designed
  /// around. [catalog] turns the look's font ID into a family name.
  factory StorePalette.of(FestivalLook look, Catalog catalog) => StorePalette(
    background: Color(look.background.argb),
    surface: Color(look.surface.argb),
    surface2: Color(look.surface2.argb),
    outline: Color(look.outline.argb),
    nav: Color(look.nav.argb),
    text: AppColors.textPrimary,
    muted: Color(look.muted.argb),
    brand: Color(look.brand.argb),
    displayFamily: catalog.font(look.displayFont)?.family,
  );

  final Color background;

  /// Cards and sheets.
  final Color surface;

  /// Raised things on a surface: the download card, swatches' rings.
  final Color surface2;
  final Color outline;

  /// The tab bar.
  final Color nav;
  final Color text;

  /// Secondary text: at least 4.5:1 on [background].
  final Color muted;

  /// Buttons, links, the selected tab, APPLIED badges.
  final Color brand;

  /// Big headings in the festival's font; null = the app font.
  final String? displayFamily;

  /// Text on [brand]: dark on light brands, light on dark ones.
  Color get onBrand =>
      ThemeData.estimateBrightnessForColor(brand) == Brightness.light
      ? background
      : text;

  @override
  StorePalette copyWith({Color? background, Color? brand}) => StorePalette(
    background: background ?? this.background,
    surface: surface,
    surface2: surface2,
    outline: outline,
    nav: nav,
    text: text,
    muted: muted,
    brand: brand ?? this.brand,
    displayFamily: displayFamily,
  );

  /// Smooth change of colours when moving between festivals.
  @override
  StorePalette lerp(StorePalette? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return StorePalette(
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surface2: c(surface2, other.surface2),
      outline: c(outline, other.outline),
      nav: c(nav, other.nav),
      text: c(text, other.text),
      muted: c(muted, other.muted),
      brand: c(brand, other.brand),
      displayFamily: t < 0.5 ? displayFamily : other.displayFamily,
    );
  }
}

extension StorePaletteOf on BuildContext {
  /// The colours for this part of the store.
  StorePalette get palette =>
      Theme.of(this).extension<StorePalette>() ?? StorePalette.base;
}
