import 'package:flutter/material.dart';

import '../look/look_store.dart';
import '../look/resolved_look.dart';
import '../render/font_registry.dart';
import '../scenes/scene_view.dart';

/// Root of the live wallpaper engine (LiveWallpaperService → `wallpaperMain`):
/// the applied theme's animated scene, full screen, at 30 fps. No clock: the
/// phone's own lock screen clock shows on top.
class LiveWallpaperApp extends StatefulWidget {
  const LiveWallpaperApp({super.key, this.looks, this.clock = DateTime.now});

  /// The applied look: what to draw.
  final LookStore? looks;

  /// The current time (fixed in tests).
  final DateTime Function() clock;

  static const fps = 30;

  @override
  State<LiveWallpaperApp> createState() => _LiveWallpaperAppState();
}

class _LiveWallpaperAppState extends State<LiveWallpaperApp> {
  late final LookStore _looks = widget.looks ?? LookStore();
  late final AppLifecycleListener _lifecycle;
  ResolvedLook? _applied;

  @override
  void initState() {
    super.initState();
    // The wallpaper becomes visible again after the user applied another
    // theme in the store: pick it up.
    _lifecycle = AppLifecycleListener(onResume: _load);
    _load();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // From saved data only: this engine may start before any network,
    // e.g. right after a reboot.
    final now = widget.clock();
    final look = await _looks.load(now: now);
    // Draw at once; redraw in the downloaded fonts once loaded.
    FontRegistry.shared.ensureAll(look.fonts.values).then((_) {
      if (mounted) setState(() {});
    });
    final applied = ResolvedLook.of(look, now);
    if (!mounted) return;
    setState(() => _applied = applied);
  }

  @override
  Widget build(BuildContext context) {
    final applied = _applied;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: applied?.wallpaperTheme.palette.background ?? Colors.black,
        child: applied == null
            ? const SizedBox.expand()
            : SceneView(
                key: ValueKey(applied.wallpaperTheme.id),
                theme: applied.wallpaperTheme,
                accent: applied.wallpaperAccent,
                animate: true,
                maxFps: LiveWallpaperApp.fps,
              ),
      ),
    );
  }
}
