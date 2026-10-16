import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:wallp/data/theme_catalog.dart';
import 'package:wallp/live_wallpaper/live_wallpaper_app.dart';
import 'package:wallp/scenes/scene_view.dart';
import 'package:wallp/services/theme_prefs.dart';
import 'package:wallp/widgets/screen_overlays.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  SceneView scene(WidgetTester tester) =>
      tester.widget<SceneView>(find.byType(SceneView));

  testWidgets('animates the applied theme at 30 fps and follows changes', (
    tester,
  ) async {
    final halloween = ThemeCatalog.byId('halloween-night')!;
    final thingyan = ThemeCatalog.byId('thingyan-water')!;
    await ThemePrefs().save(halloween, halloween.palette.accentOptions[1]);

    await tester.pumpWidget(const LiveWallpaperApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(scene(tester).theme, halloween);
    expect(scene(tester).accent, halloween.palette.accentOptions[1]);
    expect(scene(tester).animate, isTrue);
    expect(scene(tester).maxFps, LiveWallpaperApp.fps);

    // Hidden while the user applies Thingyan in the store, then visible.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await ThemePrefs().save(thingyan, thingyan.palette.accent);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(scene(tester).theme, thingyan);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  group('lock screen clock', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final now = DateTime(2026, 10, 15, 21, 7);

    /// Mocks the service; returns a way to report lock changes to Dart.
    Future<void> Function(bool) mockService({required bool locked}) {
      messenger.setMockMethodCallHandler(
        LiveWallpaperApp.channel,
        (call) async => call.method == 'showLockClock' ? locked : null,
      );
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(LiveWallpaperApp.channel, null),
      );
      return (locked) => messenger.handlePlatformMessage(
        LiveWallpaperApp.channel.name,
        LiveWallpaperApp.channel.codec.encodeMethodCall(
          MethodCall('lockClock', locked),
        ),
        (_) {},
      );
    }

    Future<void> pumpWallpaper(WidgetTester tester) async {
      final halloween = ThemeCatalog.byId('halloween-night')!;
      await ThemePrefs().save(halloween, halloween.palette.accent);
      await tester.pumpWidget(LiveWallpaperApp(clock: () => now));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('shows the themed clock while locked, hides it unlocked', (
      tester,
    ) async {
      final setLocked = mockService(locked: true);
      await pumpWallpaper(tester);

      final overlay = tester.widget<LockScreenOverlay>(
        find.byType(LockScreenOverlay),
      );
      expect(overlay.theme.id, 'halloween-night');
      expect(overlay.now, now);
      expect(find.text('9:07'), findsOneWidget);

      await setLocked(false);
      await tester.pump();
      expect(find.byType(LockScreenOverlay), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('stays hidden when switched off in Settings', (tester) async {
      mockService(locked: true);
      await ThemePrefs().saveLockClock(false);
      await pumpWallpaper(tester);

      expect(find.byType(LockScreenOverlay), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
