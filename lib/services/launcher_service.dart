import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Home-screen actions, backed by NativeBridge.kt over `wallp/launcher`.
class LauncherService {
  const LauncherService();

  static const _channel = MethodChannel('wallp/launcher');

  static bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.android;

  Future<bool> launchApp(String packageName) =>
      _call('launchApp', {'package': packageName});

  Future<bool> openAppInfo(String packageName) =>
      _call('appInfo', {'package': packageName});

  /// Opens the theme store (MainActivity) from the home screen.
  Future<bool> openThemes() => _call('openThemes');

  Future<bool> isDefaultHome() => _call('isDefaultHome');

  /// Opens wallp Home.
  Future<bool> goHome() => _call('goHome');

  /// Shows Android's "default home app" dialog and completes when the user
  /// is back: true if wallp is now the default home app. When wallp already
  /// is, opens Android's Home app settings instead, to pick another.
  Future<bool> requestDefaultHome() => _call('requestDefaultHome');

  /// Listens for messages from the home screen's native side:
  /// [onHomePressed] when Home is pressed while the home screen is showing,
  /// [onAppsChanged] when apps are installed/updated or removed.
  static void listen({
    VoidCallback? onHomePressed,
    void Function(List<String> packages, {required bool removed})?
    onAppsChanged,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'homePressed':
          onHomePressed?.call();
        case 'appsChanged':
          final args = call.arguments as Map;
          onAppsChanged?.call(
            (args['packages'] as List).cast<String>(),
            removed: args['removed'] as bool,
          );
      }
    });
  }

  Future<bool> _call(String method, [Map<String, Object?>? args]) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
