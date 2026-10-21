import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/launcher/add_apps_sheet.dart';
import 'package:wallp/launcher/app_drawer.dart';
import 'package:wallp/launcher/launcher_icon.dart';
import 'package:wallp/look/applied_look.dart';
import 'package:wallp/look/resolved_look.dart';
import 'package:wallp/render/font_registry.dart';
import 'package:wallp/services/icon_pack_service.dart';
import 'package:wallp/store/logic/previews.dart';
import 'package:wallp/store/logic/queries.dart';
import 'package:wallp/store/screens/font_detail_screen.dart';
import 'package:wallp/store/screens/fonts_screen.dart';
import 'package:wallp/store/screens/icon_pack_screens.dart';
import 'package:wallp/widgets/theme_preview.dart';

import '../catalog/fakes.dart';
import '../look/fixtures.dart';
import 'harness.dart';

void main() {
  final catalog = mockCatalog();
  AppliedLook lookOf(String themeId) =>
      AppliedLook.wholeTheme(catalog, mockTheme(themeId), at: designDay);
  Color labelsOf(AppliedLook look) =>
      ResolvedLook.of(look, designDay).homeTheme.labelColor;

  group('the theme sets it', () {
    test('Halloween ships warm names; a theme without one keeps white', () {
      expect(mockTheme('halloween-night').labelColor?.hex, '#FFD9A8');
      expect(mockTheme('christmas-eve').labelColor, isNull);
      expect(labelsOf(lookOf('halloween-night')), const Color(0xFFFFD9A8));
      expect(labelsOf(lookOf('christmas-eve')), Colors.white);
    });

    test('labels.color survives toJson', () {
      final theme = mockTheme('halloween-night');
      final again = ThemeDetail.fromJson(
        JsonReader.of(jsonDecode(jsonEncode(theme.toJson())), 'again'),
      );
      expect(again.labelColor, theme.labelColor);
    });
  });

  group('the user overrides it', () {
    final pack = catalog.iconPack('spooky-glow')!;

    test('accent, or any colour', () {
      final base = lookOf('halloween-night');
      final accent = base.withIconPack(
        pack,
        at: designDay,
        labels: const LabelColor.accent(),
      );
      expect(labelsOf(accent), Color(base.accent.primary.argb));
      final mint = base.withIconPack(
        pack,
        at: designDay,
        labels: const LabelColor.fixed(HexColor('#7BD44A')),
      );
      expect(labelsOf(mint), const Color(0xFF7BD44A));
    });

    test('changing only the shape keeps the colour', () {
      final dark = lookOf('halloween-night').withIconPack(
        pack,
        at: designDay,
        labels: const LabelColor.fixed(HexColor('#1B1B1F')),
      );
      final leaf = dark.withIconPack(
        pack,
        at: designDay,
        shape: IconShape.leaf,
      );
      expect(leaf.icons.labels, dark.icons.labels);
    });

    test('it is saved, and older saves read as the theme\'s', () {
      final custom = lookOf('halloween-night').withIconPack(
        pack,
        at: designDay,
        labels: const LabelColor.fixed(HexColor('#FF8FC0')),
      );
      final json = jsonDecode(jsonEncode(custom.icons.toJson()));
      expect(
        IconChoice.fromJson(JsonReader.of(json, 'i')).labels,
        custom.icons.labels,
      );
      (json as Map).remove('labels');
      expect(
        IconChoice.fromJson(JsonReader.of(json, 'i')).labels,
        const LabelColor.theme(),
      );
    });
  });

  group('app name font', () {
    final pack = catalog.iconPack('spooky-glow')!;

    test('theme font by default; System font drops the family', () async {
      // Downloaded from the API, as CatalogFonts does in the app.
      final font = catalog.font(mockTheme('halloween-night').fonts.labels)!;
      await FontRegistry.shared.load(font, [
        for (final f in font.files)
          File('$mockDir/${f.asset.url}').readAsBytesSync(),
      ]);
      final base = lookOf('halloween-night');
      expect(base.icons.labelFont, LabelFont.theme);
      final home = ResolvedLook.of(base, designDay).homeTheme;
      expect(home.systemLabels, isFalse);
      expect(home.labelStyle(const TextStyle()).fontFamily, isNotNull);

      final system = ResolvedLook.of(
        base.withIconPack(pack, at: designDay, labelFont: LabelFont.system),
        designDay,
      ).homeTheme;
      expect(system.systemLabels, isTrue);
      expect(system.labelStyle(const TextStyle()).fontFamily, isNull);
    });

    test('it is saved, and kept when only the colour changes', () {
      final system = lookOf('halloween-night')
          .withIconPack(pack, at: designDay, labelFont: LabelFont.system);
      final json = jsonDecode(jsonEncode(system.icons.toJson()));
      expect(
        IconChoice.fromJson(JsonReader.of(json, 'i')).labelFont,
        LabelFont.system,
      );
      final white = system.withIconPack(
        pack,
        at: designDay,
        labels: const LabelColor.fixed(HexColor('#FFFFFF')),
      );
      expect(white.icons.labelFont, LabelFont.system);
    });
  });

  test('an unlisted font is hidden from the store, still usable by themes', () {
    final json = catalog.toJson();
    final fonts = (json['fonts']! as List).cast<Map<String, Object?>>();
    fonts.firstWhere((f) => f['id'] == 'creepster')['listed'] = false;
    final hidden = Catalog.fromJson(
      JsonReader.of(jsonDecode(jsonEncode(json)), 'c'),
    );
    expect(catalog.font('creepster')!.listed, isTrue);
    expect(hidden.font('creepster')!.listed, isFalse);
    expect(fontsTab(hidden).map((f) => f.id), isNot(contains('creepster')));
    expect(search(hidden, 'creepster').fonts, isEmpty);
    expect(hidden.issues, isEmpty);
  });

  test('theme previews use the user\'s shape, name colour and font', () {
    final look = lookOf('halloween-night').withIconPack(
      catalog.iconPack('spooky-glow')!,
      at: designDay,
      shape: IconShape.leaf,
      labels: const LabelColor.accent(),
      labelFont: LabelFont.system,
    );
    final christmas = phoneThemeOf(
      mockTheme('christmas-eve'),
      catalog.festival('christmas')!,
      {for (final f in catalog.fonts) f.id: f},
      now: designDay,
    );
    final shown = withUserIcons(christmas, look, Colors.red);
    expect(shown.iconShape, IconShape.leaf);
    expect(shown.labelColor, Colors.red, reason: 'the previewed accent');
    expect(shown.systemLabels, isTrue);
    // "Theme" colour is the previewed theme's, not the applied one's.
    final themeColour = lookOf('halloween-night');
    expect(
      withUserIcons(christmas, themeColour, Colors.red).labelColor,
      Colors.white,
    );
    expect(christmas.labelFont, 'Playfair Display');
  });

  testWidgets('wallp Home draws names in it, with a shadow to match', (
    tester,
  ) async {
    final home = ResolvedLook.of(
      lookOf('halloween-night').withIconPack(
        catalog.iconPack('spooky-glow')!,
        at: designDay,
        labels: const LabelColor.fixed(HexColor('#1B1B1F')),
      ),
      designDay,
    ).homeTheme;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          child: Center(
            child: LauncherAppTile(
              app: const InstalledApp(
                packageName: 'com.google.android.dialer',
                label: 'Phone',
              ),
              theme: home,
              accent: Colors.orange,
              onTap: () {},
              onLongPress: () {},
            ),
          ),
        ),
      ),
    );
    final style = tester.widget<Text>(find.text('Phone')).style!;
    expect(style.color, const Color(0xFF1B1B1F));
    // A dark name gets a light glow, not a dark shadow.
    expect(style.shadows!.single.color.computeLuminance(), greaterThan(0.5));
  });

  testWidgets('the same colour and font in the app drawer and app lists', (
    tester,
  ) async {
    final home = ResolvedLook.of(
      lookOf('halloween-night').withIconPack(
        catalog.iconPack('spooky-glow')!,
        at: designDay,
        labels: const LabelColor.fixed(HexColor('#7BD44A')),
        labelFont: LabelFont.system,
      ),
      designDay,
    ).homeTheme;
    const apps = [
      InstalledApp(packageName: 'com.google.android.dialer', label: 'Phone'),
      InstalledApp(packageName: 'com.android.chrome', label: 'Chrome'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: AppDrawer(
              apps: apps,
              theme: home,
              accent: Colors.orange,
              onLaunch: (_) {},
              onLongPress: (_) {},
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => showAddAppsSheet(
                context,
                apps: apps,
                theme: home,
                accent: Colors.orange,
              ),
            ),
          ),
        ),
      ),
    );
    void check(Finder f) {
      final style = tester.widget<Text>(f).style!;
      expect(style.color, const Color(0xFF7BD44A));
      expect(style.fontFamily, isNull, reason: 'System font');
      expect(style.shadows, isNotEmpty);
    }

    check(find.text('Chrome'));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    check(find.text('Chrome').last);
  });

  testWidgets('the fonts list previews "Welcome" (Burmese for Padauk)', (
    tester,
  ) async {
    final h = StoreHarness();
    await h.pump(tester, home: const Scaffold(body: FontsScreen()));
    await settle(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Welcome',
    );
    expect(find.text('Welcome'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('ကြိုဆိုပါတယ်'),
      300,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(find.text('ကြိုဆိုပါတယ်'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  group('icon pack page', () {
    final h = StoreHarness();

    // The preview strip comes before the grid, which has its own "Messages".
    Color previewColour(WidgetTester tester) =>
        tester.widget<Text>(find.text('Messages').first).style!.color!;

    testWidgets('starts on the theme\'s colour and previews each choice', (
      tester,
    ) async {
      await h.pump(
        tester,
        home: const IconPackDetailScreen(packId: 'spooky-glow'),
      );
      await settle(tester);
      expect(find.text('App name colour'), findsOneWidget);
      expect(previewColour(tester), const Color(0xFFFFD9A8));

      await tester.tap(find.bySemanticsLabel('Dark'));
      await tester.pump();
      expect(previewColour(tester), const Color(0xFF1B1B1F));

      await tester.tap(find.bySemanticsLabel('Accent'));
      await tester.pump();
      expect(previewColour(tester), Color(h.looks.look!.accent.primary.argb));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Theme font / System font switches the preview', (
      tester,
    ) async {
      await h.pump(
        tester,
        home: const IconPackDetailScreen(packId: 'spooky-glow'),
      );
      await settle(tester);
      String? family() =>
          tester.widget<Text>(find.text('Messages').first).style!.fontFamily;
      expect(family(), isNotNull);
      await tester.tap(find.text('System font'));
      await tester.pump();
      expect(family(), isNull);
      await tester.tap(find.text('Theme font'));
      await tester.pump();
      expect(family(), isNotNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the font page previews lock and home; each switch shows '
        'its screen', (tester) async {
      await h.pump(
        tester,
        home: const FontDetailScreen(fontId: 'playfair-display'),
      );
      // Tall enough for the preview and the switches at once.
      tester.view.physicalSize = const Size(1170, 6000);
      await settle(tester);
      expect(find.text('Colour'), findsNothing);
      ThemePreview preview() =>
          tester.widget<ThemePreview>(find.byType(ThemePreview));
      expect(preview().screen, PhoneScreen.lock);
      expect(preview().theme.displayFont, 'Playfair Display');

      await tester.tap(find.text('App labels'));
      await tester.pump();
      expect(preview().screen, PhoneScreen.home);
      expect(preview().theme.labelFont, 'Playfair Display');

      await tester.tap(find.text('wallp Home clock'));
      await tester.pump();
      // Home clock off: the home clock keeps the theme's font.
      expect(preview().theme.displayFont, isNot('Playfair Display'));

      await tester.tap(find.text('Lock screen clock'));
      await tester.pump();
      expect(preview().screen, PhoneScreen.lock);
      expect(preview().theme.displayFont, isNot('Playfair Display'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the icon grid\'s names follow the colour being picked', (
      tester,
    ) async {
      await h.pump(
        tester,
        home: const IconPackDetailScreen(packId: 'spooky-glow'),
      );
      await settle(tester);
      Color grid() => tester.widget<Text>(find.text('Calendar')).style!.color!;
      expect(grid(), const Color(0xFFFFD9A8));
      await tester.tap(find.bySemanticsLabel('Dark'));
      await tester.pump();
      expect(grid(), const Color(0xFF1B1B1F));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Custom takes any "#RRGGBB"', (tester) async {
      await h.pump(
        tester,
        home: const IconPackDetailScreen(packId: 'spooky-glow'),
      );
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Custom'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, '#2EC4B6');
      await tester.pump();
      await tester.tap(find.text('Use this colour'));
      await settle(tester);
      expect(previewColour(tester), const Color(0xFF2EC4B6));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
