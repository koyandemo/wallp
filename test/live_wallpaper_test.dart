import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:wallp/live_wallpaper/live_wallpaper_app.dart';
import 'package:wallp/look/applied_look.dart';
import 'package:wallp/look/look_store.dart';
import 'package:wallp/scenes/placeholder_scene.dart';
import 'package:wallp/models/phone_theme.dart';
import 'package:wallp/render/layers_painter.dart';
import 'package:wallp/scenes/scene_view.dart';
import 'package:wallp/services/theme_prefs.dart';
import 'package:wallp/widgets/screen_overlays.dart';

import 'look/fixtures.dart';

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
    final halloween = builtInTheme('halloween-night');
    final thingyan = builtInTheme('thingyan-water');
    await applyBuiltIn('halloween-night', accent: 1);

    await tester.pumpWidget(const LiveWallpaperApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Drawn from the saved look: the same theme, colours and accent.
    expect(scene(tester).theme.id, halloween.id);
    expect(scene(tester).theme.scene, SceneKind.halloween);
    expect(
      scene(tester).theme.palette.background,
      halloween.palette.background,
    );
    expect(scene(tester).accent, halloween.palette.accentOptions[1]);
    expect(scene(tester).animate, isTrue);
    expect(scene(tester).maxFps, LiveWallpaperApp.fps);

    // Hidden while the user applies Thingyan in the store, then visible.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await applyBuiltIn('thingyan-water');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(scene(tester).theme.id, thingyan.id);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a partial apply: wallpaper and clock from other themes', (
    tester,
  ) async {
    final catalog = mockCatalog();
    final look =
        AppliedLook.wholeTheme(
              catalog,
              mockTheme('christmas-eve'),
              at: designDay,
            )
            .apply(
              catalog,
              mockTheme('halloween-night'),
              ApplyOption.wallpaperOnly,
              at: designDay,
            )
            .withClockFont(
              catalog.font('bebas-neue')!,
              at: designDay,
              size: ClockSize.large,
            );
    await LookStore().save(look);

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      LiveWallpaperApp.channel,
      (call) async => call.method == 'showLockClock' ? true : null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(LiveWallpaperApp.channel, null),
    );
    await tester.pumpWidget(LiveWallpaperApp(clock: () => designDay));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Halloween's scene on the wallpaper...
    expect(scene(tester).theme.id, 'halloween-night');
    expect(scene(tester).theme.scene, SceneKind.halloween);
    // ...Snowy Pines' countdown, in the user's clock font and size.
    final overlay = tester.widget<LockScreenOverlay>(
      find.byType(LockScreenOverlay),
    );
    expect(overlay.theme.id, 'christmas-eve');
    expect(overlay.theme.displayFont, 'Bebas Neue');
    expect(overlay.clockScale, 1.25);
    expect(find.textContaining('until Christmas'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a dashboard theme draws with the layers engine', (tester) async {
    await LookStore().save(
      AppliedLook.wholeTheme(
        mockCatalog(),
        mockTheme('spider-night'),
        at: designDay,
      ),
    );
    await tester.pumpWidget(LiveWallpaperApp(clock: () => designDay));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(PlaceholderScene), findsNothing);
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(SceneView),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(paint.painter, isA<LayersPainter>());
    expect(scene(tester).animate, isTrue, reason: 'Spider Night is live');
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
      await applyBuiltIn('halloween-night');
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
