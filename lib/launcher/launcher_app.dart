import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import 'launcher_home.dart';

/// Root of the home-screen engine (LauncherActivity → `launcherMain`).
class LauncherApp extends StatelessWidget {
  const LauncherApp({super.key, this.home = const LauncherHome()});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'wallp Home',
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      // Transparent so the system wallpaper shows through.
      theme: AppTheme.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: home,
    );
  }
}
