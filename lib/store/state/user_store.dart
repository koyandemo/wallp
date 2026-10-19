import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../catalog/catalog.dart';
import '../logic/queries.dart';

/// One entry of "Recently applied".
class HistoryEntry {
  const HistoryEntry(this.themeId, this.at);

  final String themeId;
  final DateTime at;
}

/// The Me tab's switches.
enum UserSetting {
  /// A note 7 days before a festival theme goes live. Saved; the
  /// notification itself needs Android permissions (not built yet).
  festivalReminders('festival_reminders', true),

  /// Switch theme when a festival starts. Saved; needs background work
  /// (not built yet).
  followNextFestival('follow_next_festival', false),

  /// The store's own colours follow the festival or theme on screen.
  matchAppToTheme('match_app_to_theme', true);

  const UserSetting(this.key, this.defaultValue);

  final String key;
  final bool defaultValue;
}

/// The user's own data, by catalog ID: favourites, history, recent searches
/// and settings. Saved on the phone; nothing leaves it.
class UserStore extends ChangeNotifier {
  UserStore({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static const historyLimit = 10;
  static const _favThemesKey = 'fav_themes_v2';
  static const _favWallsKey = 'fav_wallpapers_v2';
  static const _historyKey = 'history_v2';
  static const _searchesKey = 'recent_searches';
  static const _accentsKey = 'theme_accents_v1';

  final _favThemes = <String>[];
  final _favWalls = <String>[];
  final _history = <HistoryEntry>[];
  var _searches = <String>[];
  final _settings = <UserSetting, bool>{};

  /// The accent the user last picked for each theme (solid, gradient or
  /// custom), by theme ID.
  final _accents = <String, Accent>{};

  /// Newest first.
  List<String> get favouriteThemes => List.unmodifiable(_favThemes);
  List<String> get favouriteWallpapers => List.unmodifiable(_favWalls);
  List<HistoryEntry> get history => List.unmodifiable(_history);
  List<String> get recentSearches => List.unmodifiable(_searches);

  /// False until the first [load] finishes.
  bool get isLoaded => _loaded;
  bool _loaded = false;

  bool isFavouriteTheme(String id) => _favThemes.contains(id);
  bool isFavouriteWallpaper(String id) => _favWalls.contains(id);
  bool setting(UserSetting s) => _settings[s] ?? s.defaultValue;

  /// The accent the user last picked for [themeId], or null.
  Accent? accentFor(String themeId) => _accents[themeId];

  Future<void> load() async {
    _favThemes
      ..clear()
      ..addAll(await _prefs.getStringList(_favThemesKey) ?? const []);
    _favWalls
      ..clear()
      ..addAll(await _prefs.getStringList(_favWallsKey) ?? const []);
    _searches = await _prefs.getStringList(_searchesKey) ?? const [];
    _history.clear();
    try {
      final raw = await _prefs.getString(_historyKey);
      for (final e in (raw == null ? const [] : jsonDecode(raw) as List)) {
        final m = e as Map<String, dynamic>;
        _history.add(
          HistoryEntry(m['id'] as String, DateTime.parse(m['at'] as String)),
        );
      }
    } on Object catch (e) {
      debugPrint('Ignoring damaged history: $e');
    }
    _accents.clear();
    try {
      final raw = await _prefs.getString(_accentsKey);
      if (raw != null) {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((id, a) {
          _accents[id] = Accent.fromJson(JsonReader.of(a, 'accent.$id'));
        });
      }
    } on Object catch (e) {
      debugPrint('Ignoring damaged accent picks: $e');
      _accents.clear();
    }
    for (final s in UserSetting.values) {
      final v = await _prefs.getBool(s.key);
      if (v != null) _settings[s] = v;
    }
    _loaded = true;
    notifyListeners();
  }

  // --- favourites ---

  /// Told about each heart and un-heart the user makes (not sync merges):
  /// popularity events.
  void Function(String themeId, {required bool added})? onThemeFavourite;

  /// Hearts or un-hearts a theme. Returns its old position when removed,
  /// for [restoreTheme] (the Me tab's Undo).
  Future<int?> toggleTheme(String id) async {
    final at = await _toggle(_favThemes, _favThemesKey, id);
    onThemeFavourite?.call(id, added: at == null);
    return at;
  }

  Future<int?> toggleWallpaper(String id) =>
      _toggle(_favWalls, _favWallsKey, id);

  /// Undo: puts a removed favourite back where it was.
  Future<void> restoreTheme(String id, int at) async {
    if (_favThemes.contains(id)) return;
    await _restore(_favThemes, _favThemesKey, id, at);
    onThemeFavourite?.call(id, added: true);
  }

  Future<int?> _toggle(List<String> list, String key, String id) async {
    final at = list.indexOf(id);
    if (at >= 0) {
      list.removeAt(at);
    } else {
      list.insert(0, id);
    }
    notifyListeners();
    await _prefs.setStringList(key, list);
    return at >= 0 ? at : null;
  }

  Future<void> _restore(
    List<String> list,
    String key,
    String id,
    int at,
  ) async {
    if (list.contains(id)) return;
    list.insert(at.clamp(0, list.length), id);
    notifyListeners();
    await _prefs.setStringList(key, list);
  }

  /// Both favourite lists at once, newest first: the account sync's merge.
  Future<void> replaceFavourites({
    required List<String> themes,
    required List<String> wallpapers,
  }) async {
    if (listEquals(themes, _favThemes) && listEquals(wallpapers, _favWalls)) {
      return;
    }
    _favThemes
      ..clear()
      ..addAll(themes);
    _favWalls
      ..clear()
      ..addAll(wallpapers);
    notifyListeners();
    await _prefs.setStringList(_favThemesKey, _favThemes);
    await _prefs.setStringList(_favWallsKey, _favWalls);
  }

  // --- history ---

  /// A theme was applied: newest first, one entry per theme.
  Future<void> recordApplied(String themeId, DateTime at) async {
    if (_history.firstOrNull?.themeId == themeId) return;
    _history
      ..removeWhere((e) => e.themeId == themeId)
      ..insert(0, HistoryEntry(themeId, at));
    if (_history.length > historyLimit) {
      _history.removeRange(historyLimit, _history.length);
    }
    notifyListeners();
    await _prefs.setString(
      _historyKey,
      jsonEncode([
        for (final e in _history)
          {'id': e.themeId, 'at': e.at.toUtc().toIso8601String()},
      ]),
    );
  }

  // --- accents ---

  /// Remembers [accent] as [themeId]'s, so the theme opens with it next time.
  Future<void> rememberAccent(String themeId, Accent accent) async {
    _accents[themeId] = accent;
    notifyListeners();
    await _prefs.setString(
      _accentsKey,
      jsonEncode({for (final e in _accents.entries) e.key: e.value.toJson()}),
    );
  }

  // --- search ---

  Future<void> rememberQuery(String query) async {
    final next = rememberSearch(_searches, query);
    if (listEquals(next, _searches)) return;
    _searches = next;
    notifyListeners();
    await _prefs.setStringList(_searchesKey, _searches);
  }

  Future<void> clearSearches() async {
    _searches = const [];
    notifyListeners();
    await _prefs.remove(_searchesKey);
  }

  // --- settings ---

  Future<void> set(UserSetting s, bool on) async {
    _settings[s] = on;
    notifyListeners();
    await _prefs.setBool(s.key, on);
  }
}
