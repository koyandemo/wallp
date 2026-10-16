import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'launcher/launcher_app.dart';
import 'live_wallpaper/live_wallpaper_app.dart';

/// Theme store (MainActivity).
void main() {
  _setUp();
  runApp(const WallpApp());
}

/// Home screen (LauncherActivity), a separate engine on a transparent view.
@pragma('vm:entry-point')
void launcherMain() {
  _setUp();
  runApp(const LauncherApp());
}

/// Live wallpaper (LiveWallpaperService), rendered into the wallpaper surface.
@pragma('vm:entry-point')
void wallpaperMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LiveWallpaperApp());
}

void _setUp() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );
}
