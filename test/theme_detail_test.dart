import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter/services.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wallp/app.dart';
import 'package:wallp/services/my_themes.dart';
import 'package:wallp/services/theme_prefs.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2340);
    view.devicePixelRatio = 3;
  });

  const channel = MethodChannel('wallp/wallpaper');
  const launcher = MethodChannel('wallp/launcher');
  final calls = <MethodCall>[];

  /// Whether wallp is the default home app, and what the user picks in
  /// Android's "default home app" dialog.
  var isDefaultHome = true;
  var grantsHome = true;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    calls.clear();
    isDefaultHome = true;
    grantsHome = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'isDefaultHome':
              return isDefaultHome;
            case 'requestDefaultHome':
              isDefaultHome = grantsHome;
              return isDefaultHome;
          }
          return false;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            // Small size keeps PNG encoding fast in tests.
            'screenSize' => [108, 234],
            'setWallpaper' => true,
            'openLiveWallpaper' => true,
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(channel, null)
      ..setMockMethodCallHandler(launcher, null);
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  /// Scenes animate forever, so step time instead of pumpAndSettle.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('tapping a card opens the preview; tabs, accent and apply work', (
    tester,
  ) async {
    await tester.pumpWidget(const WallpApp());
    await tester.tap(find.byKey(const ValueKey('chip-halloween')));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Halloween theme')));
    await settle(tester);

    expect(find.text('Apply'), findsOneWidget);
    expect(find.text('Lock'), findsOneWidget);

    // Home tab swipes to the home-screen preview with its app grid.
    await tester.tap(find.text('Home'));
    await settle(tester);
    expect(find.text('Photos'), findsOneWidget);

    // Picking another accent keeps the screen working.
    await tester.tap(find.bySemanticsLabel('Accent color 2'));
    await settle(tester);

    await tester.tap(find.text('Apply'));
    await settle(tester);
    expect(find.text('Set wallpaper on'), findsOneWidget);
    expect(find.text('Home & lock screens'), findsOneWidget);

    await tester.tap(find.text('Lock screen'));
    await settle(tester);
    // Rendering the PNG runs on the engine, outside the fake test clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await settle(tester);

    final set = calls.singleWhere((c) => c.method == 'setWallpaper');
    final args = set.arguments as Map;
    expect(args['target'], 'lock');
    final png = args['bytes'] as Uint8List;
    expect(png.sublist(1, 4), 'PNG'.codeUnits);
    expect(find.text('Wallpaper set on lock screen'), findsOneWidget);

    // My Themes now shows it as the applied theme.
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.tap(find.text('My Themes'));
    await settle(tester);
    expect(find.bySemanticsLabel('Applied: Halloween'), findsOneWidget);

    // The home screen will follow the applied theme and picked accent.
    final applied = await tester.runAsync(() => ThemePrefs().load());
    expect(applied!.theme.id, 'halloween-night');
    expect(applied.accent, applied.theme.palette.accentOptions[1]);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Live wallpaper records the theme and opens the picker', (
    tester,
  ) async {
    await tester.pumpWidget(const WallpApp());
    await tester.tap(find.byKey(const ValueKey('chip-christmas')));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Christmas theme')));
    await settle(tester);

    await tester.tap(find.text('Apply'));
    await settle(tester);
    await tester.tap(find.text('Live wallpaper (animated)'));
    await settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);

    expect(calls.map((c) => c.method), contains('openLiveWallpaper'));
    expect(calls.map((c) => c.method), isNot(contains('setWallpaper')));
    expect(
      find.text('Tap "Set wallpaper" to make Christmas live'),
      findsOneWidget,
    );
    final applied = await tester.runAsync(() => ThemePrefs().load());
    expect(applied!.theme.id, 'christmas-eve');

    await tester.pumpWidget(const SizedBox());
  });

  Future<void> openHalloweenAndApply(WidgetTester tester) async {
    await tester.pumpWidget(const WallpApp());
    await tester.tap(find.byKey(const ValueKey('chip-halloween')));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Halloween theme')));
    await settle(tester);
    await tester.tap(find.text('Apply'));
    await settle(tester);
  }

  testWidgets('not the home app: Cancel in the popup applies nothing', (
    tester,
  ) async {
    isDefaultHome = false;
    await openHalloweenAndApply(tester);

    expect(find.text('Set wallp as your home app?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(find.text('Set wallpaper on'), findsNothing);
    final methods = calls.map((c) => c.method);
    expect(methods, isNot(contains('requestDefaultHome')));
    expect(methods, isNot(contains('setWallpaper')));
    final my = await tester.runAsync(() async {
      final m = MyThemes();
      await m.load();
      return m;
    });
    expect(my!.current, isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('not the home app: accepting continues to apply', (tester) async {
    isDefaultHome = false;
    await openHalloweenAndApply(tester);

    await tester.tap(find.text('Set as home app'));
    await settle(tester);
    expect(calls.map((c) => c.method), contains('requestDefaultHome'));
    expect(find.text('Set wallpaper on'), findsOneWidget);

    await tester.tap(find.text('Home & lock screens'));
    await settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await settle(tester);
    expect(calls.map((c) => c.method), contains('setWallpaper'));
    expect(find.text('Wallpaper set on home & lock screens'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('not the home app: declining Android\'s dialog applies nothing', (
    tester,
  ) async {
    isDefaultHome = false;
    grantsHome = false;
    await openHalloweenAndApply(tester);

    await tester.tap(find.text('Set as home app'));
    await settle(tester);

    expect(find.text('Set wallpaper on'), findsNothing);
    expect(calls.map((c) => c.method), isNot(contains('setWallpaper')));
    expect(
      find.text("wallp isn't your home app, so the theme wasn't applied"),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });
}
