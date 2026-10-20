import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/clock.dart';
import '../data/catalog/mock_catalog_source.dart';

/// Switches for trying the app against a pretend network and another date.
///
/// Saved on the phone so they survive restarts. Release builds ignore them:
/// the catalog always comes from the server, [conditions] is always fast
/// and [clock] always the real time.
class DevSettings extends ChangeNotifier {
  DevSettings({SharedPreferencesAsync? prefs, this.enabled = kDebugMode})
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  /// False in release builds.
  final bool enabled;

  static const _networkKey = 'dev_network';
  static const _todayKey = 'dev_pretend_today';
  static const _mockKey = 'dev_mock_catalog';

  String _network = 'fast';
  bool _mockCatalog = false;
  DateTime? _pretendToday;
  Clock? _clock;

  /// A key of [NetworkConditions.presets].
  String get network => _network;

  /// Serve the catalog from the bundled mock instead of the API server.
  bool get mockCatalog => enabled && _mockCatalog;

  NetworkConditions get conditions => enabled
      ? NetworkConditions.presets[_network] ?? NetworkConditions.fast
      : NetworkConditions.fast;

  DateTime? get pretendToday => enabled ? _pretendToday : null;

  /// The app's clock: the real one, or [pretendToday] with the real time.
  Clock get clock => _clock ??= pretendToday == null
      ? const SystemClock()
      : ShiftedClock(pretendToday!);

  /// Reads the saved switches once; later calls return the same future.
  Future<void> load() => _loading ??= _load();
  Future<void>? _loading;

  Future<void> _load() async {
    final network = await _prefs.getString(_networkKey);
    final today = await _prefs.getString(_todayKey);
    _network = NetworkConditions.presets.containsKey(network)
        ? network!
        : 'fast';
    _pretendToday = today == null ? null : DateTime.tryParse(today);
    _mockCatalog = await _prefs.getBool(_mockKey) ?? false;
    _clock = null;
    notifyListeners();
  }

  Future<void> setMockCatalog(bool on) async {
    _mockCatalog = on;
    notifyListeners();
    await _prefs.setBool(_mockKey, on);
  }

  Future<void> setNetwork(String preset) async {
    if (!NetworkConditions.presets.containsKey(preset)) {
      throw ArgumentError.value(preset, 'preset');
    }
    _network = preset;
    notifyListeners();
    await _prefs.setString(_networkKey, preset);
  }

  /// One clock object that always follows the current setting, for code
  /// that keeps a [Clock] (CatalogRepository, countdowns).
  late final Clock liveClock = _LiveClock(this);

  /// Null goes back to the real date.
  Future<void> setPretendToday(DateTime? day) async {
    _pretendToday = day == null ? null : DateTime(day.year, day.month, day.day);
    _clock = null;
    notifyListeners();
    if (_pretendToday == null) {
      await _prefs.remove(_todayKey);
    } else {
      await _prefs.setString(_todayKey, _pretendToday!.toIso8601String());
    }
  }
}

class _LiveClock implements Clock {
  _LiveClock(this._settings);

  final DevSettings _settings;

  @override
  DateTime now() => _settings.clock.now();
}
