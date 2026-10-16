import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:wallp/launcher/home_arrangement.dart';
import 'package:wallp/launcher/home_layout.dart';
import 'package:wallp/icons/themed_icon_painter.dart';
import 'package:wallp/launcher/launcher_app.dart';
import 'package:wallp/look/applied_look.dart';
import 'package:wallp/look/look_store.dart';
import 'package:wallp/services/icon_pack_service.dart';
import 'package:wallp/store/state/user_store.dart';

import 'look/fixtures.dart';

InstalledApp app(String pkg, String label) =>
    InstalledApp(packageName: pkg, label: label);

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('suggested layout puts phone/messages/browser/camera in the dock', () {
    final apps = [
      app('com.android.chrome', 'Chrome'),
      app('com.example.zgame', 'Z Game'),
      app('com.google.android.dialer', 'Phone'),
      app('com.whatsapp', 'WhatsApp'),
      app('com.android.camera', 'Camera'),
      app('com.google.android.apps.messaging', 'Messages'),
      app('com.example.agame', 'A Game'),
    ];
    final layout = HomeLayout.suggested(apps);
    expect(layout.dock.map((a) => a.label), [
      'Phone',
      'Messages',
      'Chrome',
      'Camera',
    ]);
    // Known apps first, then the rest in their original (alphabetical) order.
    expect(layout.home.map((a) => a.label), ['WhatsApp', 'Z Game', 'A Game']);
  });

  testWidgets('home screen shows themed apps, launches and opens the drawer', (
    tester,
  ) async {
    final launched = <String>[];
    const icons = MethodChannel('wallp/icons');
    const launcher = MethodChannel('wallp/launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(icons, (call) async {
      if (call.method != 'listApps') return null;
      return [
        {'package': 'com.google.android.dialer', 'label': 'Phone'},
        {'package': 'com.whatsapp', 'label': 'WhatsApp'},
        {'package': 'com.example.game', 'label': 'Cool Game'},
      ];
    });
    messenger.setMockMethodCallHandler(launcher, (call) async {
      if (call.method == 'launchApp') {
        launched.add((call.arguments as Map)['package'] as String);
      }
      return true;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(icons, null);
      messenger.setMockMethodCallHandler(launcher, null);
    });

    await applyBuiltIn('halloween-night');

    await tester.pumpWidget(const LauncherApp());
    await tester.pumpAndSettle();

    // Countdown chip, home grid and dock.
    expect(find.textContaining('· Halloween'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.bySemanticsLabel('Phone'), findsOneWidget);

    await tester.tap(find.text('WhatsApp'));
    await tester.pump();
    expect(launched, ['com.whatsapp']);

    await tester.tap(find.bySemanticsLabel('All apps'));
    await tester.pumpAndSettle();
    expect(find.text('Search apps'), findsOneWidget);
    // Drawer lists every app (Cool Game is on the home grid too).
    expect(find.text('Cool Game'), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('edit mode: remove from menu, drag into the dock, saved', (
    tester,
  ) async {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2340);
    view.devicePixelRatio = 3;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    const icons = MethodChannel('wallp/icons');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(icons, (call) async {
      if (call.method != 'listApps') return null;
      return [
        {'package': 'com.google.android.dialer', 'label': 'Phone'},
        {'package': 'com.whatsapp', 'label': 'WhatsApp'},
        {'package': 'com.example.game', 'label': 'Cool Game'},
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(icons, null));

    await applyBuiltIn('halloween-night');
    await tester.pumpWidget(const LauncherApp());
    await tester.pumpAndSettle();

    // Long-press an app → Remove from home screen.
    await tester.longPress(find.text('Cool Game'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from home screen'));
    await tester.pumpAndSettle();
    expect(find.text('Cool Game'), findsNothing);

    // Long-press an app → Edit home screen.
    await tester.longPress(find.text('WhatsApp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit home screen'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);
    expect(find.bySemanticsLabel('Remove WhatsApp'), findsOneWidget);

    // Drag WhatsApp onto the second (empty) dock slot.
    final dockEmpty = find.byWidgetPredicate((w) => w is DragTarget<String>);
    final from = tester.getCenter(find.text('WhatsApp'));
    // Dock slots are the last four DragTargets; Phone fills the first.
    final to = tester.getCenter(dockEmpty.at(dockEmpty.evaluate().length - 3));
    final gesture = await tester.startGesture(from);
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final saved = await tester.runAsync(() => HomeStore().load());
    expect(saved!.dock, ['com.google.android.dialer', 'com.whatsapp']);
    expect(saved.pages, [<String>[]]);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('installs and removals update the home screen right away', (
    tester,
  ) async {
    const icons = MethodChannel('wallp/icons');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(icons, (call) async {
      switch (call.method) {
        case 'listApps':
          return [
            {'package': 'com.whatsapp', 'label': 'WhatsApp'},
            {'package': 'com.example.game', 'label': 'Cool Game'},
          ];
        case 'getApp':
          return {'package': 'com.example.newapp', 'label': 'Brand New'};
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(icons, null));

    Future<void> sendAppsChanged(List<String> packages, bool removed) async {
      await messenger.handlePlatformMessage(
        'wallp/launcher',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('appsChanged', {'packages': packages, 'removed': removed}),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    await applyBuiltIn('halloween-night');
    await tester.pumpWidget(const LauncherApp());
    await tester.pumpAndSettle();
    expect(find.text('Cool Game'), findsOneWidget);

    await sendAppsChanged(['com.example.game'], true);
    expect(find.text('Cool Game'), findsNothing);
    final saved = await tester.runAsync(() => HomeStore().load());
    expect(saved!.contains('com.example.game'), isFalse);

    await sendAppsChanged(['com.example.newapp'], false);
    await tester.tap(find.text('Swipe up for all apps'));
    await tester.pumpAndSettle();
    expect(find.text('Brand New'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('applies a theme left pending by switching the home app', (
    tester,
  ) async {
    const icons = MethodChannel('wallp/icons');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(icons, (call) async {
      if (call.method != 'listApps') return null;
      return [
        {'package': 'com.whatsapp', 'label': 'WhatsApp'},
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(icons, null));

    // Halloween was the fallback; the user was applying Christmas when
    // Android jumped to wallp Home.
    await LookStore().savePending(
      AppliedLook.wholeTheme(
        mockCatalog(),
        mockTheme('christmas-eve'),
        at: DateTime.now(),
      ),
    );

    await tester.pumpWidget(const LauncherApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('· Christmas'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    // The catalog's name for christmas-eve.
    expect(find.text('Snowy Pines applied'), findsOneWidget);
    expect((await LookStore().load()).theme.id, 'christmas-eve');
    // wallp Home recorded it in the store's history too.
    final user = UserStore();
    await user.load();
    expect(user.history.first.themeId, 'christmas-eve');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('follows a partial apply: icon pack and clock places', (
    tester,
  ) async {
    const icons = MethodChannel('wallp/icons');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(icons, (call) async {
      if (call.method != 'listApps') return null;
      return [
        {'package': 'com.google.android.dialer', 'label': 'Phone'},
        {'package': 'com.whatsapp', 'label': 'WhatsApp'},
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(icons, null));

    final catalog = mockCatalog();
    final halloween = AppliedLook.wholeTheme(
      catalog,
      mockTheme('halloween-night'),
      at: designDay,
    );
    await LookStore().save(halloween);
    await tester.pumpWidget(const LauncherApp());
    await tester.pumpAndSettle();
    expect(find.byType(ThemedIcon), findsWidgets, reason: 'Spooky Glow icons');

    // A downloaded (image) icon pack: drawn in Phase 6, own icons until then.
    await LookStore().save(
      halloween.withIconPack(catalog.iconPack('moonlit')!, at: designDay),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(ThemedIcon), findsNothing);
    expect(find.textContaining('· Halloween'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
