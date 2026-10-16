import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_theme.dart';
import 'screens/home_shell.dart';
import 'services/my_themes.dart';

class WallpApp extends StatelessWidget {
  const WallpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      // Favourites, apply history and remembered accents, app-wide.
      create: (_) => MyThemes()..load(),
      child: MaterialApp(
        title: 'Wallp Themes',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: const HomeShell(),
      ),
    );
  }
}
