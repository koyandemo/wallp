import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog/catalog.dart';
import 'accent_choices.dart';

/// The user's saved custom accents ("My accents"), newest first, at most
/// [limit]. Saved on the phone; shared by every theme's picker.
class MyAccents extends ChangeNotifier {
  MyAccents({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static const limit = 6;
  static const _listKey = 'my_accents_v1';
  static const _counterKey = 'my_accents_next';

  final _accents = <Accent>[];
  int _next = 1;

  List<Accent> get accents => List.unmodifiable(_accents);

  Future<void> load() async {
    final raw = await _prefs.getString(_listKey);
    final next = await _prefs.getInt(_counterKey);
    _accents.clear();
    if (raw != null) {
      try {
        _accents.addAll([
          for (final (i, a) in (jsonDecode(raw) as List).indexed)
            Accent.fromJson(JsonReader.of(a, 'myAccents[$i]')),
        ]);
      } on Object catch (e) {
        debugPrint('Ignoring damaged My accents: $e');
        _accents.clear();
      }
    }
    _next = next ?? _accents.length + 1;
    notifyListeners();
  }

  /// Saves a custom accent and returns it, named "Mine N". Saving the same
  /// colours again moves the existing one to the front instead.
  Future<Accent> add({
    required HexColor start,
    HexColor? end,
    int angle = 135,
  }) async {
    final draft = customAccent(
      id: 'mine-$_next',
      name: 'Mine $_next',
      start: start,
      end: end,
      angle: angle,
    );
    final existing = _accents.where((a) => sameLook(a, draft)).firstOrNull;
    final saved = existing ?? draft;
    _accents
      ..remove(saved)
      ..insert(0, saved);
    if (existing == null) _next++;
    if (_accents.length > limit) _accents.removeRange(limit, _accents.length);
    notifyListeners();
    await _save();
    return saved;
  }

  Future<void> remove(String id) async {
    _accents.removeWhere((a) => a.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    await _prefs.setString(
      _listKey,
      jsonEncode([for (final a in _accents) a.toJson()]),
    );
    // Never reuse a number, even after removing: names stay unique.
    await _prefs.setInt(_counterKey, _next);
  }
}
