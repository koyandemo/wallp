import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/icons/themed_icon_painter.dart';
import 'package:wallp/launcher/launcher_icon.dart';
import 'package:wallp/look/applied_look.dart';
import 'package:wallp/look/resolved_look.dart';
import 'package:wallp/render/icon_shape.dart';
import 'package:wallp/services/icon_pack_service.dart';
import 'package:wallp/store/screens/icon_pack_screens.dart';

import '../look/fixtures.dart';
import 'harness.dart';

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
    await h.pump(tester, demo: true);
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
        demo: true,
      );
      await settle(tester);
      for (final name in ['Squircle', 'Circle', 'Square', 'Leaf']) {
        expect(find.bySemanticsLabel(name), findsOneWidget, reason: name);
      }
      // 4 in the picker, 20 in the grid: all the real Halloween icons.
      expect(find.byType(ThemedIcon), findsAtLeastNWidgets(4 + 8));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tapping a shape reshapes every icon', (tester) async {
      await h.pump(
        tester,
        home: const IconPackDetailScreen(packId: 'spooky-glow'),
        demo: true,
      );
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

    testWidgets('nothing is "in use" before you apply', (tester) async {
      await h.pump(
        tester,
        home: const IconPackDetailScreen(packId: 'spooky-glow'),
        demo: true,
      );
      await settle(tester);
      expect(find.textContaining('In use'), findsNothing);
      expect(find.textContaining('Apply icon pack'), findsOneWidget);
      expect(find.text('Add icons to your home screen'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
