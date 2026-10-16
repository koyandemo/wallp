import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../scenes/scene_view.dart';
import '../services/theme_prefs.dart';
import '../widgets/screen_overlays.dart';

/// Root of the live wallpaper engine (LiveWallpaperService → `wallpaperMain`):
/// the applied theme's animated scene, full screen, at 30 fps. On the lock
/// screen it also draws the theme's clock, since apps can't restyle the
/// phone's own lock screen clock.
class LiveWallpaperApp extends StatefulWidget {
  const LiveWallpaperApp({super.key, this.prefs, this.clock = DateTime.now});

  final ThemePrefs? prefs;

  /// The current time (fixed in tests).
  final DateTime Function() clock;

  static const fps = 30;

  /// Told by LiveWallpaperService.kt when the lock screen shows or hides.
  static const channel = MethodChannel('wallp/live_wallpaper');

  @override
  State<LiveWallpaperApp> createState() => _LiveWallpaperAppState();
}

class _LiveWallpaperAppState extends State<LiveWallpaperApp> {
  late final ThemePrefs _prefs = widget.prefs ?? ThemePrefs();
  late final AppLifecycleListener _lifecycle;
  AppliedTheme? _applied;
  bool _clockOn = true;
  bool _locked = false;

  /// Redraws the clock on the minute while it shows.
  Timer? _minute;

  @override
  void initState() {
    super.initState();
    // The wallpaper becomes visible again after the user applied another
    // theme in the store: pick it up.
    _lifecycle = AppLifecycleListener(onResume: _load);
    LiveWallpaperApp.channel.setMethodCallHandler((call) async {
      if (call.method == 'lockClock') _setLocked(call.arguments == true);
    });
    _load();
    _askLocked();
  }

  @override
  void dispose() {
    LiveWallpaperApp.channel.setMethodCallHandler(null);
    _minute?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final applied = await _prefs.load();
    final clockOn = await _prefs.loadLockClock();
    if (!mounted) return;
    setState(() {
      _applied = applied;
      _clockOn = clockOn;
    });
    _syncTimer();
  }

  Future<void> _askLocked() async {
    try {
      final locked = await LiveWallpaperApp.channel.invokeMethod<bool>(
        'showLockClock',
      );
      _setLocked(locked ?? false);
    } on MissingPluginException {
      // Not running in the wallpaper service (tests).
    } on PlatformException {
      // Keep the clock hidden.
    }
  }

  void _setLocked(bool locked) {
    if (!mounted || locked == _locked) return;
    setState(() => _locked = locked);
    _syncTimer();
  }

  bool get _showClock => _clockOn && _locked;

  void _syncTimer() {
    _minute?.cancel();
    _minute = null;
    if (!_showClock) return;
    final now = widget.clock();
    final next = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _minute = Timer(next.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _syncTimer();
    });
  }

  @override
  Widget build(BuildContext context) {
    final applied = _applied;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: applied?.theme.palette.background ?? Colors.black,
        child: applied == null
            ? const SizedBox.expand()
            : Stack(
                fit: StackFit.expand,
                children: [
                  SceneView(
                    key: ValueKey(applied.theme.id),
                    theme: applied.theme,
                    accent: applied.accent,
                    animate: true,
                    maxFps: LiveWallpaperApp.fps,
                  ),
                  if (_showClock)
                    LayoutBuilder(
                      // Below the phone's own clock, above the scene's
                      // ground and the lock screen shortcuts.
                      builder: (context, size) => LockScreenOverlay(
                        theme: applied.theme,
                        accent: applied.accent,
                        now: widget.clock(),
                        top: size.maxHeight * 0.3,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
