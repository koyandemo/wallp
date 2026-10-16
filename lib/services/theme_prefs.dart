import 'dart:convert';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/theme_catalog.dart';
import '../models/phone_theme.dart';

/// The theme (and accent) the user last applied.
class AppliedTheme {
  const AppliedTheme({required this.theme, required this.accent});

  final PhoneTheme theme;
  final Color accent;
}

/// Remembers the applied theme so the home screen can follow it.
///
/// Uses [SharedPreferencesAsync] (no in-memory cache) because the theme
/// store and the home screen run as separate Flutter engines and must see
/// each other's writes.
class ThemePrefs {
  ThemePrefs({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static const _themeKey = 'applied_theme_id';
  static const _accentKey = 'applied_accent';
  static const _lockClockKey = 'lock_clock';
  static const _pendingKey = 'pending_apply';

  /// A pending apply older than this is stale (the user never finished
  /// switching the home app) and is dropped.
  static const pendingMaxAge = Duration(minutes: 10);

  /// The applied theme, or the next festival's theme if none was applied.
  Future<AppliedTheme> load({DateTime? now}) async {
    final id = await _prefs.getString(_themeKey);
    final theme =
        (id == null ? null : ThemeCatalog.byId(id)) ??
        ThemeCatalog.nextUp(now ?? DateTime.now());
    final argb = await _prefs.getInt(_accentKey);
    final accent = argb == null ? theme.palette.accent : Color(argb);
    return AppliedTheme(theme: theme, accent: accent);
  }

  /// Whether the live wallpaper draws the themed clock on the lock screen.
  Future<bool> loadLockClock() async =>
      await _prefs.getBool(_lockClockKey) ?? true;

  Future<void> saveLockClock(bool on) => _prefs.setBool(_lockClockKey, on);

  /// Remembers a theme the user is applying while Android switches the home
  /// app to wallp. Switching jumps straight to the new home screen, so the
  /// theme store may never get to finish the apply; wallp Home finishes it
  /// with [takePending].
  Future<void> savePending(PhoneTheme theme, Color accent, {DateTime? at}) =>
      _prefs.setString(
        _pendingKey,
        jsonEncode({
          'theme': theme.id,
          'accent': accent.toARGB32(),
          'at': (at ?? DateTime.now()).millisecondsSinceEpoch,
        }),
      );

  /// The pending apply if it's recent, and clears it either way.
  Future<AppliedTheme?> takePending({DateTime? now}) async {
    final raw = await _prefs.getString(_pendingKey);
    if (raw == null) return null;
    await clearPending();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final theme = ThemeCatalog.byId(json['theme'] as String);
      final at = DateTime.fromMillisecondsSinceEpoch(json['at'] as int);
      final age = (now ?? DateTime.now()).difference(at);
      if (theme == null || age.isNegative || age > pendingMaxAge) return null;
      return AppliedTheme(theme: theme, accent: Color(json['accent'] as int));
    } on Object {
      // Corrupt entry: nothing to apply.
      return null;
    }
  }

  Future<void> clearPending() => _prefs.remove(_pendingKey);

  Future<void> save(PhoneTheme theme, Color accent) async {
    await _prefs.setString(_themeKey, theme.id);
    await _prefs.setInt(_accentKey, accent.toARGB32());
  }
}
