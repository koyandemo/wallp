import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/core/store_palette.dart';
import 'package:wallp/look/accent_contrast.dart' as wcag;
import 'package:wallp/store/screens/festival_screen.dart';
import 'package:wallp/store/screens/themes_screen.dart';
import 'package:wallp/store/state/user_store.dart';
import 'package:wallp/store/widgets/store_look_scope.dart';

import '../look/fixtures.dart';
import 'harness.dart';

HexColor _hex(Color c) => HexColor(
  '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
);
double _contrast(Color a, Color b) => wcag.contrast(_hex(a), _hex(b));

void main() {
  final catalog = mockCatalog();

  group('every festival look stays readable', () {
    for (final f in catalog.festivals) {
      test(f.id, () {
        final p = StorePalette.of(f.look, catalog);
        expect(
          _contrast(p.text, p.background),
          greaterThanOrEqualTo(4.5),
          reason: 'text',
        );
        expect(
          _contrast(p.text, p.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'text on cards',
        );
        expect(
          _contrast(p.muted, p.background),
          greaterThanOrEqualTo(4.5),
          reason: 'muted text',
        );
        // Links and the selected tab: large or bold UI text.
        expect(
          _contrast(p.brand, p.background),
          greaterThanOrEqualTo(3),
          reason: 'brand',
        );
        expect(
          _contrast(p.onBrand, p.brand),
          greaterThanOrEqualTo(4.5),
          reason: 'button label',
        );
      });
    }
  });

  group('which look applies', () {
    final h = StoreHarness();

    StorePalette paletteAt(WidgetTester tester, Finder finder) =>
        Theme.of(tester.element(finder)).extension<StorePalette>()!;

    Color bg(String festivalId) =>
        Color(catalog.festival(festivalId)!.look.background.argb);

    testWidgets('nothing applied: the plain wallp look', (tester) async {
      await h.pump(tester, home: const Scaffold(body: ThemesScreen()));
      await settle(tester);
      expect(
        paletteAt(tester, find.byType(ThemesScreen)).background,
        StorePalette.base.background,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the applied theme\'s festival everywhere', (tester) async {
      await h.pump(tester, home: const Scaffold(body: ThemesScreen()));
      await tester.runAsync(() => h.looks.applyTheme('halloween-night'));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400)); // the colour fade
      expect(
        paletteAt(tester, find.byType(ThemesScreen)).background,
        bg('halloween'),
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a festival page wears its own festival', (tester) async {
      await h.pump(
        tester,
        home: const StoreLookScope(
          festivalId: 'christmas',
          child: FestivalScreen(festivalId: 'christmas'),
        ),
      );
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      final p = paletteAt(tester, find.byType(FestivalScreen));
      expect(p.background, bg('christmas'));
      expect(p.displayFamily, 'Playfair Display');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an undated collection keeps the plain look', (tester) async {
      await h.pump(
        tester,
        home: const StoreLookScope(
          festivalId: 'minimal',
          child: FestivalScreen(festivalId: 'minimal'),
        ),
      );
      await settle(tester);
      expect(
        paletteAt(tester, find.byType(FestivalScreen)).background,
        StorePalette.base.background,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('switched off in Me: plain everywhere', (tester) async {
      await h.pump(
        tester,
        home: const StoreLookScope(
          festivalId: 'christmas',
          child: FestivalScreen(festivalId: 'christmas'),
        ),
      );
      await tester.runAsync(
        () => h.user.set(UserSetting.matchAppToTheme, false),
      );
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        paletteAt(tester, find.byType(FestivalScreen)).background,
        StorePalette.base.background,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });
}
