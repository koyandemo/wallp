import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_theme.dart';
import 'data/account/account_repository.dart';
import 'data/api/api_client.dart';
import 'data/api/event_queue.dart';
import 'data/assets/asset_cache.dart';
import 'data/assets/download_manager.dart';
import 'data/catalog/catalog_repository.dart';
import 'data/catalog/catalog_source.dart';
import 'data/catalog/catalog_store.dart';
import 'data/catalog/http_catalog_source.dart';
import 'dev/dev_settings.dart';
import 'look/look_controller.dart';
import 'look/my_accents.dart';
import 'render/font_registry.dart';
import 'core/clock.dart';
import 'store/state/backend_sync.dart';
import 'store/state/catalog_fonts.dart';
import 'store/state/favourites_sync.dart';
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
        // The app API at API_BASE_URL (env/*.json): events and accounts.
        Provider(create: (_) => ApiClient(), dispose: (_, c) => c.close()),
        // Where catalog files come from, for the catalog and downloads
        // alike: the server's /catalog/v1/.
        Provider<CatalogSource>(create: (_) => HttpCatalogSource()),
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
        // Every catalog font, from the API, for the store's previews.
        Provider(
          create: (context) => CatalogFonts(
            catalog: context.read<CatalogRepository>(),
            downloads: context.read<DownloadManager>(),
            cache: context.read<AssetCache>(),
          ),
          dispose: (_, f) => f.dispose(),
          lazy: false,
        ),
        // Previews animate only while wallp's live wallpaper is on.
        ChangeNotifierProvider(create: (_) => LiveWallpaperStatus()),
        // Anonymous usage events, sent in batches.
        ChangeNotifierProvider(
          create: (context) => EventQueue(
            client: context.read<ApiClient>(),
            clock: context.read<DevSettings>().liveClock,
          ),
        ),
        // The optional account: cross-device favourites.
        ChangeNotifierProvider(
          create: (context) =>
              AccountRepository(client: context.read<ApiClient>()),
        ),
        ChangeNotifierProvider(
          create: (context) => FavouritesSync(
            account: context.read<AccountRepository>(),
            user: context.read<UserStore>(),
          ),
        ),
        // Not lazy: the start-up sequence and the periodic refreshes.
        Provider(create: _backend, dispose: (_, b) => b.dispose(), lazy: false),
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
    // Only the server's items: nothing shipped in the app is shown.
    final repo = CatalogRepository(
      source: context.read<CatalogSource>(),
      store: FileCatalogStore.appSupport(),
      clock: dev.liveClock,
    )..hideShipped = true;
    // Wait for the saved pretend date, so the first catalog shows with it.
    dev.load().then((_) => repo.start());
    return repo;
  }

  static BackendSync _backend(BuildContext context) {
    final sync = BackendSync(
      catalog: context.read<CatalogRepository>(),
      events: context.read<EventQueue>(),
      account: context.read<AccountRepository>(),
      favourites: context.read<FavouritesSync>(),
      user: context.read<UserStore>(),
    );
    context.read<DevSettings>().load().then((_) => sync.start());
    return sync;
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
