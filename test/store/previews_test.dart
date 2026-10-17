import 'package:flutter/material.dart';

import 'dart:ui' show CheckedState;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wallp/icons/themed_icon_painter.dart';
import 'package:wallp/look/accent_paint.dart';
import 'package:wallp/store/screens/icon_pack_screens.dart';
import 'package:wallp/store/screens/theme_detail_screen.dart';
import 'package:wallp/store/state/user_store.dart';
import 'package:wallp/widgets/screen_overlays.dart';
import 'package:wallp/widgets/theme_preview.dart';

import '../look/fixtures.dart';
import 'harness.dart';

void main() {
  final h = StoreHarness();

  group('remembered accent per theme', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test(
      'a pick is saved for that theme only, and survives a restart',
      () async {
        final glow = mockTheme('halloween-night').accentById('pumpkin-glow')!;
        final user = UserStore();
        await user.load();
        await user.rememberAccent('halloween-night', glow);

        final again = UserStore();
        await again.load();
        expect(again.accentFor('halloween-night')?.colors, glow.colors);
        expect(again.accentFor('christmas-eve'), isNull);
      },
    );

    testWidgets('the theme reopens with the accent picked last time', (
      tester,
    ) async {
      // A page that opens the theme, as the store does.
      await h.pump(
        tester,
        themes: ['halloween-night'],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const ThemeDetailScreen(themeId: 'halloween-night'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Slime'));
      await settle(tester);
      expect(h.user.accentFor('halloween-night')?.id, 'slime');

      // Leave and open it again: Slime is still the one selected.
      await tester.pageBack();
      await settle(tester);
      await tester.tap(find.text('open'));
      await settle(tester);
      final slime = tester.getSemantics(find.bySemanticsLabel('Slime'));
      expect(slime.flagsCollection.isChecked, CheckedState.isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('segment labels never wrap, even on a narrow phone', (
    tester,
  ) async {
    await h.pump(
      tester,
      home: const IconPackDetailScreen(packId: 'spooky-glow'),
      demo: true,
    );
    tester.view.physicalSize = const Size(320 * 3, 2532);
    await settle(tester);
    // One line: no taller than one line of its text.
    for (final label in ['Theme font', 'System font']) {
      final size =
          tester.widget<Text>(find.text(label)).style?.fontSize ??
          DefaultTextStyle.of(tester.element(find.text(label))).style.fontSize!;
      expect(tester.getSize(find.text(label)).height, lessThan(size * 1.5));
    }
    // The tile shapes are icons only; their names are for screen readers.
    expect(find.text('Squircle'), findsNothing);
    expect(find.bySemanticsLabel('Squircle'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  group('previews', () {
    final halloween = builtInTheme('halloween-night');
    final glow = mockTheme('halloween-night').accentById('pumpkin-glow')!;

    Future<void> pumpPreview(WidgetTester tester, PhoneScreen screen) async {
      await h.pump(
        tester,
        home: SizedBox(
          width: 390,
          height: 844,
          child: ThemePreview(
            theme: halloween,
            now: designDay,
            screen: screen,
            accent: glow.color,
            accentGradient: glow.gradient,
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('home screen: the theme\'s real icons, in the gradient', (
      tester,
    ) async {
      await pumpPreview(tester, PhoneScreen.home);
      // 8 apps and 4 in the dock, drawn by the Halloween icon pack.
      expect(find.byType(ThemedIcon), findsNWidgets(12));
      final overlay = tester.widget<HomeScreenOverlay>(
        find.byType(HomeScreenOverlay),
      );
      expect(overlay.accentGradient, isNotNull);
      expect(
        find.byType(ShaderMask),
        findsWidgets,
        reason: 'name and countdown icon',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('lock screen: shortcuts, and a gradient clock', (tester) async {
      await pumpPreview(tester, PhoneScreen.lock);
      expect(find.byIcon(Icons.flashlight_on_rounded), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);
      final overlay = tester.widget<LockScreenOverlay>(
        find.byType(LockScreenOverlay),
      );
      expect(
        overlay.clockGradient,
        isNotNull,
        reason: 'Halloween clocks use the accent',
      );
      await tester.pumpWidget(const SizedBox());
    });
  });
}
