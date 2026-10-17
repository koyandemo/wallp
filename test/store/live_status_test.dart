import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:wallp/models/phone_theme.dart';
import 'package:wallp/models/wallpaper_target.dart';
import 'package:wallp/services/wallpaper_service.dart';
import 'package:wallp/store/apply_flow.dart';
import 'package:wallp/store/screens/theme_detail_screen.dart';
import 'package:wallp/store/state/live_wallpaper_status.dart';
import 'package:wallp/widgets/theme_preview.dart';

import 'harness.dart';

const _channel = MethodChannel('wallp/wallpaper');

void _native(Object? Function(MethodCall call) answer) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async => answer(call));
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
}

void main() {
  group('the live picker says how it ended', () {
    for (final (answer, expected) in [
      ('set', LivePickerResult.set),
      ('cancelled', LivePickerResult.cancelled),
      ('unavailable', LivePickerResult.unavailable),
      (null, LivePickerResult.unavailable),
    ]) {
      test('$answer', () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        _native((_) => answer);
        expect(await const WallpaperService().openLiveWallpaper(), expected);
      });
    }
  });

  group('Apply asks where; "Live wallpaper" goes straight to it', () {
    final h = StoreHarness();

    Future<String> apply(WidgetTester tester, _FakeWallpapers fake) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      late BuildContext context;
      await h.pump(
        tester,
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
        demo: true,
      );
      final wallpaper = h.catalog.catalog.wallpapers.first;
      final flow = ApplyFlow(wallpapers: fake);
      // The "Set wallpaper on" sheet, then its Live row.
      // Started in the real zone: applying reads files first.
      late Future<void> done;
      await tester.runAsync(() async {
        done = flow.applyWallpaper(context, wallpaper);
      });
      // Until the sheet is up, however long the file reads take.
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find.text('Set wallpaper on').evaluate().isNotEmpty) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await settle(tester);
      expect(find.text('Set wallpaper on'), findsOneWidget);
      expect(find.text('Home & lock screens'), findsOneWidget);
      await tester.tap(find.text(WallpaperTarget.live.label));
      await settle(tester);
      await tester.runAsync(() => done);
      await tester.pump();
      final toast = tester.widget<SnackBar>(find.byType(SnackBar));
      final text = ((toast.content as Text).data)!;
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
      return text;
    }

    testWidgets('not live yet: opens the live preview at once', (tester) async {
      final fake = _FakeWallpapers(live: false);
      expect(await apply(tester, fake), 'Live wallpaper on');
      expect(fake.pickers, 1);
      expect(fake.stills, 0);
    });

    testWidgets('already live: nothing to open, it redraws itself', (
      tester,
    ) async {
      final fake = _FakeWallpapers(live: true);
      expect(await apply(tester, fake), 'Live wallpaper updated');
      expect(fake.pickers, 0);
      expect(fake.stills, 0);
    });
  });

  group('the theme page animates only with the live wallpaper on', () {
    final h = StoreHarness();

    Future<bool> animates(WidgetTester tester, {required bool live}) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      _native((call) => call.method == 'isLiveWallpaperActive' ? live : null);
      late LiveWallpaperStatus status;
      await h.pump(
        tester,
        home: ChangeNotifierProvider(
          create: (_) => status = LiveWallpaperStatus(),
          child: const ThemeDetailScreen(themeId: 'halloween-night'),
        ),
        themes: ['halloween-night'],
      );
      await tester.runAsync(() => status.refresh());
      await settle(tester);
      final animate = tester
          .widget<ThemePreview>(find.byType(ThemePreview))
          .animate;
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
      return animate;
    }

    testWidgets('still wallpaper: a still preview', (tester) async {
      expect(await animates(tester, live: false), isFalse);
    });

    testWidgets('live wallpaper: an animated preview', (tester) async {
      expect(await animates(tester, live: true), isTrue);
    });
  });
}

/// Counts what Apply asks of the wallpaper side.
class _FakeWallpapers implements WallpaperService {
  _FakeWallpapers({required this.live});

  bool live;
  int pickers = 0;
  int stills = 0;

  @override
  Future<bool> isLiveWallpaperActive() async => live;

  @override
  Future<LivePickerResult> openLiveWallpaper() async {
    pickers++;
    live = true;
    return LivePickerResult.set;
  }

  @override
  Future<ApplyResult> apply({
    required PhoneTheme theme,
    required Color accent,
    required WallpaperTarget target,
    required Size fallbackPixelSize,
  }) async {
    stills++;
    return ApplyResult.applied;
  }
}
