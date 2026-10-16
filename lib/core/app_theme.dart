import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../render/font_registry.dart';
import 'store_palette.dart';

class AppTheme {
  AppTheme._();

  /// The store's theme in [palette]'s colours (the plain wallp look, or a
  /// festival's: "Match app to my theme").
  static ThemeData dark([StorePalette palette = StorePalette.base]) {
    final p = palette;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: p.brand,
          brightness: Brightness.dark,
        ).copyWith(
          primary: p.brand,
          onPrimary: p.onBrand,
          surface: p.surface,
          onSurface: p.text,
          outline: p.outline,
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
    );

    // google_fonts 9 returns material_ui's TextTheme, so apply the family
    // to Flutter's own TextTheme instead of using soraTextTheme().
    final text = base.textTheme
        .apply(
          fontFamily: GoogleFonts.sora().fontFamily,
          bodyColor: p.text,
          displayColor: p.text,
        )
        .copyWith(
          headlineLarge: GoogleFonts.sora(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            height: 1.15,
            color: p.text,
          ),
          titleMedium: GoogleFonts.sora(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: p.text,
          ),
          bodyMedium: GoogleFonts.sora(fontSize: 14, color: p.muted),
          labelSmall: GoogleFonts.sora(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
            color: p.muted,
          ),
        );

    return base.copyWith(
      extensions: [p],
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: p.text,
        // Page titles in the festival's display font.
        titleTextStyle: p.displayFamily == null
            ? null
            : FontRegistry.shared.style(
                p.displayFamily!,
                TextStyle(fontSize: 24, color: p.text),
              ),
      ),
      // Off switches stay visible: an outlined track and a muted thumb.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.onBrand : p.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.brand : p.surface2,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.brand : p.muted,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.nav,
        indicatorColor: p.brand.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? p.brand : p.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => GoogleFonts.sora(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected) ? p.text : p.muted,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.surface2,
        contentTextStyle: GoogleFonts.sora(fontSize: 14, color: p.text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
