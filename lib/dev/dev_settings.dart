import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/clock.dart';

/// Switches for trying the app on another date. The catalog always comes
/// from the API server, in every build.
///
/// Saved on the phone so they survive restarts. Release builds ignore them:
/// [clock] is always the real time.
class DevSettings extends ChangeNotifier {
  DevSettings({SharedPreferencesAsync? prefs, this.enabled = kDebugMode})
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  /// False in release builds.
  final bool enabled;

  static const _todayKey = 'dev_pretend_today';

  DateTime? _pretendToday;
  Clock? _clock;

  DateTime? get pretendToday => enabled ? _pretendToday : null;

  /// The app's clock: the real one, or [pretendToday] with the real time.
  Clock get clock => _clock ??= pretendToday == null
      ? const SystemClock()
      : ShiftedClock(pretendToday!);

  /// Reads the saved switches once; later calls return the same future.
  Future<void> load() => _loading ??= _load();
  Future<void>? _loading;

  Future<void> _load() async {
    final today = await _prefs.getString(_todayKey);
    _pretendToday = today == null ? null : DateTime.tryParse(today);
    _clock = null;
    notifyListeners();
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
