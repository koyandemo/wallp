import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api_config.dart';
import 'core/app_theme.dart';
import 'data/api/account_service.dart';
import 'data/api/api_client.dart';
import 'data/api/auth_session.dart';
import 'data/api/event_queue.dart';
import 'data/api/install_link.dart';
import 'data/api/token_store.dart';
import 'data/assets/asset_cache.dart';
import 'data/assets/download_manager.dart';
import 'data/catalog/catalog_poller.dart';
import 'data/catalog/catalog_repository.dart';
import 'data/catalog/catalog_source.dart';
import 'data/catalog/catalog_store.dart';
import 'data/catalog/http_catalog_source.dart';
import 'data/catalog/pretend_network.dart';
import 'dev/dev_settings.dart';
import 'look/look_controller.dart';
import 'look/my_accents.dart';
import 'render/font_registry.dart';
import 'core/clock.dart';
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
        // Where catalog files come from, for the catalog and downloads
        // alike: the server picked by the env file (env/*.json), behind
        // Developer settings' pretend network (always "fast" in release).
        Provider<CatalogSource>(
          create: (context) {
            final dev = context.read<DevSettings>();
            return PretendNetworkSource(
              HttpCatalogSource(base: ApiConfig.current.catalogBase),
              conditions: () => dev.conditions,
            );
          },
        ),
        // Accounts and events (/v1).
        Provider(
          create: (_) => ApiClient.forConfig(ApiConfig.current),
          dispose: (_, ApiClient api) => api.close(),
        ),
        // Anonymous popularity events, sent in batches. Not lazy: it sends
        // what's waiting on launch. Hearts are counted too.
        Provider(
          lazy: false,
          create: (context) {
            final events = EventQueue(api: context.read<ApiClient>())..start();
            context
                .read<UserStore>()
                .onThemeFavourite = (id, {required added}) => events.add(
              added
                  ? AppEventType.themeFavourited
                  : AppEventType.themeUnfavourited,
              id,
            );
            return events;
          },
          dispose: (_, EventQueue events) => events.dispose(),
        ),
        // The optional sign-in. Not lazy: a saved one refreshes at launch.
        ChangeNotifierProvider(
          lazy: false,
          create: (context) => AuthSession(
            api: context.read<ApiClient>(),
            store: SecureTokenStore(scope: ApiConfig.current.base.authority),
          )..start(),
        ),
        Provider(
          create: (context) => AccountService(
            context.read<ApiClient>(),
            context.read<AuthSession>(),
          ),
        ),
        // Favourites follow the account to other phones. Not lazy: it
        // syncs on launch when signed in.
        Provider(
          lazy: false,
          create: (context) => FavouritesSync(
            api: context.read<ApiClient>(),
            session: context.read<AuthSession>(),
            user: context.read<UserStore>(),
          ),
          dispose: (_, FavouritesSync sync) => sync.dispose(),
        ),
        // Ties this install to the account, for stats.
        Provider(
          lazy: false,
          create: (context) => InstallLink(
            api: context.read<ApiClient>(),
            session: context.read<AuthSession>(),
            installId: context.read<EventQueue>().installId,
          ),
          dispose: (_, InstallLink link) => link.dispose(),
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
        // Checks for a new catalog every 5 minutes while the store is open.
        Provider(
          lazy: false,
          create: (context) =>
              CatalogPoller(context.read<CatalogRepository>())..start(),
          dispose: (_, CatalogPoller poller) => poller.dispose(),
        ),
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
