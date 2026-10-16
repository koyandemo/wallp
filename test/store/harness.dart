import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wallp/core/app_theme.dart';
import 'package:wallp/core/clock.dart';
import 'package:wallp/data/assets/asset_cache.dart';
import 'package:wallp/data/assets/download_manager.dart';
import 'package:wallp/data/catalog/catalog_repository.dart';
import 'package:wallp/data/catalog/catalog_source.dart';
import 'package:wallp/data/catalog/catalog_store.dart';
import 'package:wallp/data/catalog/mock_catalog_source.dart';
import 'package:wallp/dev/dev_settings.dart';
import 'package:wallp/look/look_controller.dart';
import 'package:wallp/look/my_accents.dart';
import 'package:wallp/render/scene_assets.dart';
import 'package:wallp/store/state/user_store.dart';
import 'package:wallp/store/store_shell.dart';
import 'package:wallp/store/widgets/download_overlay.dart';
import 'package:wallp/store/widgets/store_look_scope.dart';

import '../catalog/fakes.dart';
import '../look/fixtures.dart';

/// The store with every real provider, on the mock catalog, on the
/// design's date. Loading happens for real (runAsync) before pumping:
/// inside testWidgets' fake clock, file reads never finish.
class StoreHarness {
  late CatalogRepository catalog;
  late LookController looks;
  late UserStore user;
  late MyAccents accents;
  late AssetCache cache;
  late Directory dir;

  /// Builds and pumps the store, with full theme files preloaded for
  /// [themes] (detail pages open them).
  Future<void> pump(
    WidgetTester tester, {
    Widget? home,
    List<String> themes = const [],
    bool demo = false,
  }) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final view = tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      dir = Directory.systemTemp.createTempSync('wallp_store_');
      cache = AssetCache(dir);
      // The app's own demo catalog, or the full fixture (the default).
      final CatalogSource source = demo
          ? MockCatalogSource()
          : TamperingSource();
      catalog = CatalogRepository(source: source, store: MemoryCatalogStore());
      await catalog.start(refresh: false);
      await catalog.refresh();
      for (final id in themes) {
        await catalog.theme(id);
      }
      final downloads = DownloadManager(source: source, cache: cache);
      looks = LookController(
        catalog: catalog,
        clock: FixedClock(designDay),
        prepare: (next, label) => downloads.ensure(next.assets, label: label),
        pin: cache.pin,
      );
      await looks.load();
      user = UserStore();
      await user.load();
      accents = MyAccents();
      await accents.load();
    });
    addTearDown(() => dir.deleteSync(recursive: true));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: user),
          ChangeNotifierProvider(create: (_) => DevSettings(enabled: false)),
          ChangeNotifierProvider.value(value: accents),
          Provider<Clock>.value(value: FixedClock(designDay)),
          Provider.value(value: cache),
          ChangeNotifierProvider(
            create: (_) =>
                DownloadManager(source: TamperingSource(), cache: cache),
          ),
          ChangeNotifierProvider.value(value: catalog),
          ChangeNotifierProvider.value(value: looks),
        ],
        child: SceneAssetsScope(
          assets: SceneAssets(cache),
          child: MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) =>
                StoreLookScope(child: DownloadOverlay(child: child!)),
            home: home ?? const StoreShell(),
          ),
        ),
      ),
    );
    await tester.pump();
  }
}

/// Lets animated scenes tick without waiting for them to "settle" (they
/// never do).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Taps the chip [label], scrolling its row sideways first: chip rows
/// scroll, and chips off screen aren't built yet.
Future<void> tapChip(WidgetTester tester, String label) async {
  final chip = find.text(label);
  if (chip.hitTestable().evaluate().isEmpty) {
    // The chip row on screen (other tabs' rows are built but hidden).
    await tester.scrollUntilVisible(
      chip,
      80,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
          )
          .hitTestable()
          .first,
    );
  }
  // Built but maybe half off the edge: bring it fully into view. Only
  // then: ensureVisible scrolls the page too.
  if (chip.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(chip);
    await tester.pump();
  }
  await tester.tap(chip.hitTestable());
  await settle(tester);
}

/// Scrolls the page until [finder] is on screen.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first,
  );
  await settle(tester);
}
