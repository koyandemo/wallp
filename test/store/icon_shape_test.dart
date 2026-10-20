import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/icons/themed_icon_painter.dart';
import 'package:wallp/launcher/launcher_icon.dart';
import 'package:wallp/look/applied_look.dart';
import 'package:wallp/look/resolved_look.dart';
import 'package:wallp/render/icon_shape.dart';
import 'package:wallp/services/icon_pack_service.dart';
import 'package:wallp/services/launcher_service.dart';
import 'package:wallp/store/screens/icon_pack_screens.dart';

import '../look/fixtures.dart';
import 'harness.dart';

/// Android's answer to "is wallp the home app?", pretended.
class _Launcher extends LauncherService {
  const _Launcher({required this.isHome});

  final bool isHome;

  @override
  Future<bool> isDefaultHome() async => isHome;
}

void main() {
  final catalog = mockCatalog();

  test('each shape has its own corners', () {
    expect(iconShapeRadius(IconShape.circle, 60).topLeft.x, 30);
    expect(iconShapeRadius(IconShape.square, 60).topLeft.x, closeTo(7.2, 0.01));
    expect(iconShapeRadius(IconShape.squircle, 60).topLeft.x, 18);
    final leaf = iconShapeRadius(IconShape.leaf, 60);
    expect(leaf.topLeft.x, 30);
    expect(leaf.bottomLeft.x, closeTo(7.2, 0.01));
  });

  test('the chosen shape reaches wallp Home for painted packs', () {
    final look =
        AppliedLook.wholeTheme(
          catalog,
          mockTheme('halloween-night'),
          at: designDay,
        ).withIconPack(
          catalog.iconPack('spooky-glow')!,
          at: designDay,
          shape: IconShape.leaf,
        );
    final home = ResolvedLook.of(look, designDay).homeTheme;
    expect(home.iconShape, IconShape.leaf);
    expect(
      home.iconStyle,
      isNotNull,
      reason: 'still the painted Halloween icons',
    );
  });

  testWidgets('wallp Home draws the painted icon in that shape', (
    tester,
  ) async {
    final look =
        AppliedLook.wholeTheme(
          catalog,
          mockTheme('halloween-night'),
          at: designDay,
        ).withIconPack(
          catalog.iconPack('spooky-glow')!,
          at: designDay,
          shape: IconShape.circle,
        );
    final home = ResolvedLook.of(look, designDay).homeTheme;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: LauncherIcon(
            app: const InstalledApp(
              packageName: 'com.google.android.dialer',
              label: 'Phone',
            ),
            theme: home,
            accent: Colors.orange,
          ),
        ),
      ),
    );
    expect(
      tester.widget<ThemedIcon>(find.byType(ThemedIcon)).shape,
      IconShape.circle,
    );
    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clip.borderRadius, iconShapeRadius(IconShape.circle, 56));
  });

  testWidgets('the store home\'s icon pack row shows the real icons', (
    tester,
  ) async {
    final h = StoreHarness();
    await h.pump(tester);
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text('Spooky Glow'),
      300,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await settle(tester);
    final row = find.ancestor(
      of: find.text('Spooky Glow'),
      matching: find.byType(InkWell),
    );
    final icons = find.descendant(of: row, matching: find.byType(ThemedIcon));
    expect(icons, findsNWidgets(3));
    expect(tester.widgetList<ThemedIcon>(icons).map((i) => i.glyph), [
      Icons.phone_rounded,
      Icons.chat_bubble_rounded,
      Icons.photo_camera_rounded,
    ]);
    await tester.pumpWidget(const SizedBox());
  });

  group('icon pack page', () {
    final h = StoreHarness();

    testWidgets('the shape picker shows the theme\'s real icon in each shape', (
      tester,
    ) async {
      await h.pump(
        tester,
        home: const IconPackDetailScreen(packId: 'spooky-glow'),
      );
      await settle(tester);
      for (final name in ['Squircle', 'Circle', 'Square', 'Leaf']) {
        expect(find.bySemanticsLabel(name), findsOneWidget, reason: name);
      }
      // 4 in the picker, 20 in the grid: all the real Halloween icons.
      expect(find.byType(ThemedIcon), findsAtLeastNWidgets(4 + 8));
      await tester.pumpWidget(const SizedBox());
    });

    /// Icon packs go on wallp Home, which applying a theme sets up.
    Future<void> applyTheme(WidgetTester tester) =>
        tester.runAsync(() => h.looks.applyTheme('christmas-eve'));

    testWidgets('before a theme is applied: no Apply, shapes ask for one', (
      tester,
    ) async {
      await h.pump(
        tester,
        home: const IconPackDetailScreen(packId: 'spooky-glow'),
      );
      await settle(tester);
      expect(h.looks.isApplied, isFalse);
      expect(find.text('Apply icons'), findsNothing);
      expect(find.textContaining('Apply a theme first'), findsOneWidget);
      final before = tester
          .widgetList<ThemedIcon>(find.byType(ThemedIcon))
          .map((i) => i.shape)
          .toList();
      await tester.tap(find.bySemanticsLabel('Leaf'));
      await tester.pump();
      expect(
        find.text('Apply a theme first to use icon packs'),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<ThemedIcon>(find.byType(ThemedIcon))
            .map((i) => i.shape)
            .toList(),
        before,
        reason: 'the tap changed nothing',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a theme applied but wallp not the home app: still locked', (
      tester,
    ) async {
      await h.pump(
        tester,
        home: const IconPackDetailScreen(
          packId: 'spooky-glow',
          launcher: _Launcher(isHome: false),
        ),
        themes: ['christmas-eve'],
      );
      await applyTheme(tester);
      await settle(tester);
      expect(find.text('Apply icons'), findsNothing);
      expect(find.textContaining('Apply a theme first'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tapping a shape reshapes every icon', (tester) async {
      await h.pump(
        tester,
        home: const IconPackDetailScreen(
          packId: 'spooky-glow',
          launcher: _Launcher(isHome: true),
        ),
        themes: ['christmas-eve'],
      );
      await applyTheme(tester);
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Leaf'));
      await settle(tester);
      final shapes = tester
          .widgetList<ThemedIcon>(find.byType(ThemedIcon))
          .map((i) => i.shape)
          .toList();
      // The picker keeps one of each; the grid all turns to leaf.
      expect(shapes.where((s) => s == IconShape.leaf).length, greaterThan(4));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('choices preview; Apply puts the pack on wallp Home', (
      tester,
    ) async {
      await h.pump(
        tester,
        home: const IconPackDetailScreen(
          packId: 'spooky-glow',
          launcher: _Launcher(isHome: true),
        ),
        themes: ['christmas-eve'],
      );
      await applyTheme(tester);
      await settle(tester);
      expect(h.looks.look!.icons.pack.id, 'gold-ornament');
      expect(find.text('Apply icons'), findsOneWidget);
      expect(find.textContaining('then apply to wallp Home'), findsOneWidget);

      /// Lets the apply's real file work run until [done] holds.
      Future<void> until(bool Function() done) async {
        for (var i = 0; i < 300 && !done(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await settle(tester);
      }

      // A tap only previews.
      await tester.tap(find.bySemanticsLabel('Leaf'));
      await settle(tester);
      expect(h.looks.look!.icons.pack.id, 'gold-ornament');

      await tester.tap(find.text('Apply icons'));
      await until(() => h.looks.look!.icons.pack.id == 'spooky-glow');
      expect(h.looks.look!.icons.pack.id, 'spooky-glow');
      expect(h.looks.look!.icons.shape, IconShape.leaf);
      await until(() => find.text('Applied').evaluate().isNotEmpty);
      expect(find.text('Applied'), findsOneWidget);

      // A later change waits for Apply changes.
      await tester.ensureVisible(find.text('System font'));
      await tester.pump();
      await tester.tap(find.text('System font'));
      await settle(tester);
      expect(h.looks.look!.icons.labelFont, isNot(LabelFont.system));
      await tester.tap(find.text('Apply changes'));
      await until(() => h.looks.look!.icons.labelFont == LabelFont.system);
      expect(h.looks.look!.icons.labelFont, LabelFont.system);
      expect(h.looks.look!.icons.shape, IconShape.leaf);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
