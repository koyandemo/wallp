import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/theme_catalog.dart';
import '../models/phone_theme.dart';
import 'theme_prefs.dart';

/// One apply, for the "Recently applied" list.
class AppliedEntry {
  const AppliedEntry({
    required this.theme,
    required this.accent,
    required this.appliedAt,
  });

  final PhoneTheme theme;
  final Color accent;
  final DateTime appliedAt;

  Map<String, Object> toJson() => {
    'theme': theme.id,
    'accent': accent.toARGB32(),
    'at': appliedAt.millisecondsSinceEpoch,
  };

  /// Null if the theme no longer exists in the catalog.
  static AppliedEntry? fromJson(Map<String, dynamic> json) {
    final theme = ThemeCatalog.byId(json['theme'] as String);
    if (theme == null) return null;
    return AppliedEntry(
      theme: theme,
      accent: Color(json['accent'] as int),
      appliedAt: DateTime.fromMillisecondsSinceEpoch(json['at'] as int),
    );
  }
}

/// The user's favourites, apply history and last-picked accent per theme.
/// Shared app-wide with provider; every change is saved on the phone.
class MyThemes extends ChangeNotifier {
  MyThemes({SharedPreferencesAsync? prefs, ThemePrefs? themePrefs})
    : _prefs = prefs ?? SharedPreferencesAsync(),
      _themePrefs = themePrefs ?? ThemePrefs(prefs: prefs);

  final SharedPreferencesAsync _prefs;
  final ThemePrefs _themePrefs;

  static const historyLimit = 10;
  static const _favoritesKey = 'my_favorites';
  static const _historyKey = 'my_history';
  static const _accentsKey = 'my_accents';

  final _favorites = <String>{};
  final _history = <AppliedEntry>[];
  final _accents = <String, Color>{};

  /// Favourites in catalog order.
  List<PhoneTheme> get favorites =>
      ThemeCatalog.themes.where((t) => _favorites.contains(t.id)).toList();

  /// Newest first; one entry per theme.
  List<AppliedEntry> get history => List.unmodifiable(_history);

  /// The theme applied last, or null if nothing was applied yet.
  AppliedEntry? get current => _history.firstOrNull;

  bool isFavorite(PhoneTheme theme) => _favorites.contains(theme.id);

  /// The accent the user picked last for [theme], else its default.
  Color accentFor(PhoneTheme theme) =>
      _accents[theme.id] ?? theme.palette.accent;

  Future<void> load() async {
    final favorites = await _prefs.getStringList(_favoritesKey) ?? const [];
    final history = <AppliedEntry>[];
    final accents = <String, Color>{};
    try {
      final rawHistory = await _prefs.getString(_historyKey);
      if (rawHistory != null) {
        for (final item in jsonDecode(rawHistory) as List) {
          final entry = AppliedEntry.fromJson(item as Map<String, dynamic>);
          if (entry != null) history.add(entry);
        }
      }
      final rawAccents = await _prefs.getString(_accentsKey);
      if (rawAccents != null) {
        (jsonDecode(rawAccents) as Map<String, dynamic>).forEach(
          (id, argb) => accents[id] = Color(argb as int),
        );
      }
    } on FormatException {
      // Corrupt data: start fresh rather than crash.
    }
    _favorites
      ..clear()
      ..addAll(favorites.where((id) => ThemeCatalog.byId(id) != null));
    _history
      ..clear()
      ..addAll(history);
    _accents
      ..clear()
      ..addAll(accents);
    notifyListeners();
  }

  Future<void> toggleFavorite(PhoneTheme theme) async {
    if (!_favorites.remove(theme.id)) _favorites.add(theme.id);
    notifyListeners();
    await _prefs.setStringList(_favoritesKey, _favorites.toList());
  }

  Future<void> rememberAccent(PhoneTheme theme, Color accent) async {
    _accents[theme.id] = accent;
    notifyListeners();
    await _saveAccents();
  }

  /// See [ThemePrefs.savePending].
  Future<void> savePending(PhoneTheme theme, Color accent) =>
      _themePrefs.savePending(theme, accent);

  Future<void> clearPending() => _themePrefs.clearPending();

  /// Finishes an apply that was cut short by switching the home app to
  /// wallp. Returns the theme it applied, or null if there was none.
  Future<PhoneTheme?> applyPending({DateTime? now}) async {
    final pending = await _themePrefs.takePending(now: now);
    if (pending == null) return null;
    await load();
    await recordApplied(pending.theme, pending.accent);
    return pending.theme;
  }

  /// Records an apply: history, accent, and the theme the home screen uses.
  Future<void> recordApplied(
    PhoneTheme theme,
    Color accent, {
    DateTime? at,
  }) async {
    _history
      ..removeWhere((e) => e.theme.id == theme.id)
      ..insert(
        0,
        AppliedEntry(
          theme: theme,
          accent: accent,
          appliedAt: at ?? DateTime.now(),
        ),
      );
    if (_history.length > historyLimit) {
      _history.removeRange(historyLimit, _history.length);
    }
    _accents[theme.id] = accent;
    notifyListeners();
    await _prefs.setString(
      _historyKey,
      jsonEncode([for (final e in _history) e.toJson()]),
    );
    await _saveAccents();
    // wallp Home (a separate engine) reads this.
    await _themePrefs.save(theme, accent);
  }

  Future<void> _saveAccents() => _prefs.setString(
    _accentsKey,
    jsonEncode({
      for (final MapEntry(:key, :value) in _accents.entries)
        key: value.toARGB32(),
    }),
  );
}
