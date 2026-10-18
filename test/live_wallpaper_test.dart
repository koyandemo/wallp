import 'package:flutter/material.dart';
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

  testWidgets('a partial apply: another theme\'s wallpaper, and no clock', (
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

    await tester.pumpWidget(LiveWallpaperApp(clock: () => designDay));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Halloween's scene on the wallpaper...
    expect(scene(tester).theme.id, 'halloween-night');
    expect(scene(tester).theme.scene, SceneKind.halloween);
    expect(find.textContaining('until Christmas'), findsNothing);

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
}
