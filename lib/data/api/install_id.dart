import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// A random UUID made on first launch (docs/app-api.md §4, §6). Not tied
/// to any device identifier; it only groups this phone's events.
class InstallId {
  InstallId({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static const _key = 'install_id';
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  Future<String>? _value;

  /// The saved ID, made and saved the first time.
  Future<String> get() => _value ??= _load();

  Future<String> _load() async {
    final saved = await _prefs.getString(_key);
    if (saved != null && _uuid.hasMatch(saved)) return saved;
    final id = uuidV4();
    await _prefs.setString(_key, id);
    return id;
  }

  static String uuidV4([Random? random]) {
    final r = random ?? Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final hex = [for (final x in b) x.toRadixString(16).padLeft(2, '0')];
    return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
        '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
        '${hex.sublist(10).join()}';
  }
}
