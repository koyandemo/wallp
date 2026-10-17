import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_theme.dart';
import 'data/assets/asset_cache.dart';
import 'data/assets/download_manager.dart';
import 'data/catalog/catalog_repository.dart';
import 'data/catalog/catalog_source.dart';
import 'data/catalog/catalog_store.dart';
import 'data/catalog/mock_catalog_source.dart';
import 'dev/dev_settings.dart';
import 'look/look_controller.dart';
import 'look/my_accents.dart';
import 'render/font_registry.dart';
import 'core/clock.dart';
import 'store/state/live_wallpaper_status.dart';
import 'store/state/user_store.dart';
import 'store/store_shell.dart';
import 'store/widgets/download_overlay.dart';
import 'store/widgets/store_look_scope.dart';

class WallpApp extends StatelessWidget {
  const WallpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Favourites, history, recent searches and settings.
        ChangeNotifierProvider(create: (_) => UserStore()..load()),
        ChangeNotifierProvider(create: (_) => DevSettings()..load()),
        // "Now" for countdowns and badges (Developer settings can pretend).
        Provider<Clock>(
          create: (context) => context.read<DevSettings>().liveClock,
        ),
        // Custom accents the user saved, for every theme's picker.
        ChangeNotifierProvider(create: (_) => MyAccents()..load()),
        // Where catalog files come from, for the catalog and downloads
        // alike. The mock Theme API; when the real one exists, only this
        // changes: an HTTP source pointed at the CDN.
        Provider<CatalogSource>(
          create: (context) {
            final dev = context.read<DevSettings>();
            return MockCatalogSource(conditions: () => dev.conditions);
          },
        ),
        // The same instance SceneAssets and FontRegistry read through.
        Provider(create: (_) => AssetCache.shared),
        ChangeNotifierProvider(
          create: (context) => DownloadManager(
            source: context.read<CatalogSource>(),
            cache: context.read<AssetCache>(),
          ),
        ),
        // Not lazy: the catalog loads and refreshes from launch, before
        // any screen asks for it.
        ChangeNotifierProvider(create: _catalog, lazy: false),
        // What the phone looks like, and every way to change it. Not lazy:
        // on launch it re-pins (and if needed re-downloads) the applied
        // look's files.
        ChangeNotifierProvider(create: _looks, lazy: false),
        // Previews animate only while wallp's live wallpaper is on.
        ChangeNotifierProvider(create: (_) => LiveWallpaperStatus()),
      ],
      child: MaterialApp(
        title: 'Wallp Themes',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        // The download progress card shows above every screen.
        // The applied theme's colours everywhere ("Match app to my
        // theme"); pages for one festival switch to its look.
        builder: (context, child) =>
            StoreLookScope(child: DownloadOverlay(child: child!)),
        home: const StoreShell(),
      ),
    );
  }

  static CatalogRepository _catalog(BuildContext context) {
    final dev = context.read<DevSettings>();
    final repo = CatalogRepository(
      source: context.read<CatalogSource>(),
      store: FileCatalogStore.appSupport(),
      clock: dev.liveClock,
    );
    // Wait for saved Developer switches, so "Offline" applies from the
    // very first request.
    dev.load().then((_) => repo.start());
    return repo;
  }

  static LookController _looks(BuildContext context) {
    final downloads = context.read<DownloadManager>();
    final cache = context.read<AssetCache>();
    final controller = LookController(
      catalog: context.read<CatalogRepository>(),
      clock: context.read<DevSettings>().liveClock,
      // Every file first; nothing is applied until they're all here.
      prepare: (next, label) => downloads.ensure(next.assets, label: label),
      pin: cache.pin,
    );
    // The store draws the applied look too (previews, Me): load its fonts
    // whenever it changes.
    controller.addListener(() {
      final look = controller.look;
      if (look != null) FontRegistry.shared.ensureAll(look.fonts.values);
    });
    controller.load().then((_) => controller.repair());
    return controller;
  }
}
