import 'package:shared_preferences/shared_preferences.dart';

import '../store/state/user_store.dart';

/// The one setting the live wallpaper reads directly: whether it draws the
/// theme's clock on the lock screen (Me › Themed lock screen clock).
///
/// The applied look itself lives in LookStore.
class ThemePrefs {
  ThemePrefs({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static final _lockClock = UserSetting.themedLockClock;

  Future<bool> loadLockClock() async =>
      await _prefs.getBool(_lockClock.key) ?? _lockClock.defaultValue;

  Future<void> saveLockClock(bool on) => _prefs.setBool(_lockClock.key, on);
}
