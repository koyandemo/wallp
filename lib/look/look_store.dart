import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog/catalog.dart';
import '../data/catalog/built_in_catalog.dart';
import 'applied_look.dart';

/// Saves the applied look where all three engines can read it: the theme
/// store, wallp Home and the live wallpaper.
///
/// Uses [SharedPreferencesAsync] (no in-memory cache) because the engines
/// run separately and must see each other's writes at once.
class LookStore {
  LookStore({SharedPreferencesAsync? prefs, BuiltInCatalog? builtIn})
    : _prefs = prefs ?? SharedPreferencesAsync(),
      _builtIn = builtIn ?? BuiltInCatalog();

  final SharedPreferencesAsync _prefs;
  final BuiltInCatalog _builtIn;

  static const lookKey = 'applied_look';
  static const pendingKey = 'pending_look';

  // Before Phase 3 the app saved only a theme ID and an accent colour.
  static const legacyThemeKey = 'applied_theme_id';
  static const legacyAccentKey = 'applied_accent';
  static const legacyPendingKey = 'pending_apply';

  /// A pending apply older than this is stale (the user never finished
  /// switching the home app to wallp) and is dropped.
  static const pendingMaxAge = Duration(minutes: 10);

  /// What the user applied, or null if nothing yet.
  ///
  /// Moves an old (theme ID + accent) save over to a look the first time.
  /// A damaged save is deleted and treated as nothing applied.
  Future<AppliedLook?> saved() async {
    final raw = await _prefs.getString(lookKey);
    if (raw != null) {
      final look = _decode(raw, 'applied look');
      if (look != null) return look;
      await _prefs.remove(lookKey);
    }
    return _migrateLegacy();
  }

  /// The applied look, or, before anything was applied, the built-in
  /// theme of the soonest festival (not saved, so it moves on by itself).
  Future<AppliedLook> load({DateTime? now}) async =>
      await saved() ?? await defaultLook(now ?? DateTime.now());

  Future<void> save(AppliedLook look) =>
      _prefs.setString(lookKey, jsonEncode(look.toJson()));

  Future<AppliedLook> defaultLook(DateTime now) async {
    final catalog = await _builtIn.catalog();
    final soonest = catalog.themes.reduce((a, b) {
      int key(ThemeSummary t) =>
          catalog.festival(t.festivalId)?.countdown(now).sortKey ?? 1 << 31;
      return key(b) < key(a) ? b : a;
    });
    return AppliedLook.wholeTheme(
      catalog,
      (await _builtIn.theme(soonest.id))!,
      at: now,
    );
  }

  /// Remembers a look being applied while Android switches the home app to
  /// wallp. Switching jumps straight to the new home screen, so the store
  /// may never finish the apply; wallp Home finishes it with [takePending].
  Future<void> savePending(AppliedLook look, {DateTime? at}) =>
      _prefs.setString(
        pendingKey,
        jsonEncode({
          'look': look.toJson(),
          'at': (at ?? DateTime.now()).toUtc().toIso8601String(),
        }),
      );

  /// The pending look if it's recent, and clears it either way.
  Future<AppliedLook?> takePending({DateTime? now}) async {
    final raw = await _prefs.getString(pendingKey);
    await clearPending();
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.parse(json['at'] as String);
      final age = (now ?? DateTime.now()).difference(at);
      if (age.isNegative || age > pendingMaxAge) return null;
      return AppliedLook.fromJson(JsonReader.of(json['look'], 'pending'));
    } on Object catch (e) {
      debugPrint('Dropping a damaged pending apply: $e');
      return null;
    }
  }

  Future<void> clearPending() async {
    await _prefs.remove(pendingKey);
    await _prefs.remove(legacyPendingKey);
  }

  AppliedLook? _decode(String raw, String what) {
    try {
      return AppliedLook.fromJson(JsonReader.of(jsonDecode(raw), what));
    } on Object catch (e) {
      debugPrint('Ignoring a damaged $what: $e');
      return null;
    }
  }

  /// Turns an old save into a look: the same built-in theme, and the
  /// theme's accent of the same colour (or that colour as a custom accent).
  Future<AppliedLook?> _migrateLegacy() async {
    final id = await _prefs.getString(legacyThemeKey);
    if (id == null) return null;
    final argb = await _prefs.getInt(legacyAccentKey);
    final theme = await _builtIn.theme(id);
    AppliedLook? look;
    if (theme != null) {
      look = AppliedLook.wholeTheme(
        await _builtIn.catalog(),
        theme,
        at: DateTime.now(),
        accent: argb == null ? null : accentForArgb(theme, argb),
      );
      await save(look);
    }
    await _prefs.remove(legacyThemeKey);
    await _prefs.remove(legacyAccentKey);
    return look;
  }

  /// [theme]'s accent drawn in [argb], or a custom solid accent of it.
  static Accent accentForArgb(ThemeDetail theme, int argb) {
    final rgb = argb & 0xFFFFFF;
    for (final a in theme.accents) {
      if (a.type == AccentType.solid && (a.primary.argb & 0xFFFFFF) == rgb) {
        return a;
      }
    }
    final hex = '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
    return Accent(
      id: 'custom',
      name: LocalizedText.en('Custom'),
      colors: [HexColor(hex)],
    );
  }
}
