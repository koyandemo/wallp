import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/data/assets/asset_cache.dart';
import 'package:wallp/launcher/launcher_icon.dart';
import 'package:wallp/look/applied_look.dart';
import 'package:wallp/look/resolved_look.dart';
import 'package:wallp/render/font_registry.dart';
import 'package:wallp/render/image_icons.dart';
import 'package:wallp/render/scene_assets.dart';
import 'package:wallp/services/icon_pack_service.dart';
import 'package:wallp/store/screens/icon_pack_screens.dart' show sampleApps;

import '../catalog/fakes.dart';
import '../look/fixtures.dart';

void main() {
  final catalog = mockCatalog();
  late Directory dir;
  late AssetCache cache;
  late SceneAssets assets;

  Future<void> download(Iterable<AssetRef> refs) async {
    for (final ref in refs) {
      await cache.put(ref, File('$mockDir/${ref.url}').readAsBytesSync());
    }
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wallp_icons_');
    cache = AssetCache(dir);
    assets = SceneAssets(cache);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('every sample app in the store\'s previews has a symbol', () {
    for (final app in sampleApps) {
      expect(app.glyph, isNotNull, reason: app.label);
    }
  });

  group('FontRegistry', () {
    test('loads a downloaded font and draws text in it', () async {
      final creepster = catalog.font('creepster')!;
      await download(creepster.files.map((f) => f.asset));
      final registry = FontRegistry(assets: assets);
      expect(await registry.ensure(creepster), isTrue);
      final style = registry.style('Creepster', const TextStyle(fontSize: 40));
      expect(style.fontFamily, 'wallp-creepster');
      expect(style.fontSize, 40);
    });

    test('a font whose files aren\'t on the phone isn\'t loaded', () async {
      final registry = FontRegistry(assets: assets);
      expect(await registry.ensure(catalog.font('bebas-neue')!), isFalse);
      expect(registry.loadedFamily('Bebas Neue'), isNull);
    });

    test('Burmese text falls back to Padauk once it\'s loaded', () async {
      final creepster = catalog.font('creepster')!;
      final padauk = catalog.font('padauk')!;
      await download([
        ...creepster.files.map((f) => f.asset),
        ...padauk.files.map((f) => f.asset),
      ]);
      final registry = FontRegistry(assets: assets);
      await registry.ensureAll([creepster, padauk]);
      expect(registry.style('Creepster').fontFamilyFallback, ['wallp-padauk']);
      expect(registry.style('Padauk').fontFamilyFallback, isNull);
    });
  });

  group('wallp Home icons from a downloaded pack', () {
    final look =
        AppliedLook.wholeTheme(
          catalog,
          mockTheme('spider-night'),
          at: designDay,
        ).withIconPack(
          catalog.iconPack('web-slinger')!,
          at: designDay,
          shape: IconShape.circle,
        );
    final home = ResolvedLook.of(look, designDay).homeTheme;

    test('the resolved look carries the pack and the user\'s shape', () {
      expect(home.imageIcons, isNotNull);
      expect(home.imageIcons!.shape, IconShape.circle);
      expect(home.hasIconPack, isFalse, reason: 'not a painted pack');
    });

    PackTilePainter painterIn(WidgetTester tester) =>
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(PackTileIcon),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as PackTilePainter;

    testWidgets('a sample app shows its symbol on the tile', (tester) async {
      const whatsapp = InstalledApp(
        packageName: 'com.whatsapp',
        label: 'WhatsApp',
      );
      await tester.pumpWidget(
        SceneAssetsScope(
          assets: assets,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: LauncherIcon(
              app: whatsapp,
              theme: home,
              accent: Colors.orange,
            ),
          ),
        ),
      );
      expect(painterIn(tester).symbol, Icons.forum_rounded);
      expect(find.byType(ClipRRect), findsOneWidget);
    });

    testWidgets('an app with no known symbol gets a generic one', (
      tester,
    ) async {
      const game = InstalledApp(
        packageName: 'com.example.game',
        label: 'Cool Game',
      );
      await tester.pumpWidget(
        SceneAssetsScope(
          assets: assets,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: LauncherIcon(app: game, theme: home, accent: Colors.orange),
          ),
        ),
      );
      expect(painterIn(tester).symbol, Icons.apps_rounded);
    });

    testWidgets('a pack with a background puts the app on that picture', (
      tester,
    ) async {
      final background = look.icons.pack.background!;
      expect(home.imageIcons!.background, background);
      await tester.runAsync(() async {
        await download([background]);
        await assets.image(background);
      });
      const game = InstalledApp(
        packageName: 'com.example.game',
        label: 'Cool Game',
      );
      await tester.pumpWidget(
        SceneAssetsScope(
          assets: assets,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: LauncherIcon(app: game, theme: home, accent: Colors.orange),
          ),
        ),
      );
      // The plain tile until the picture loads, then the picture.
      expect(painterIn(tester).background, isNull);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(painterIn(tester).background, isNotNull);
    });

    testWidgets('a real app keeps its own logo', (tester) async {
      late ui.Image icon, logo;
      await tester.runAsync(() async {
        icon = await _square(const Color(0xFF25D366));
        logo = await _square(const Color(0xFFFFFFFF));
      });
      final whatsapp = InstalledApp(
        packageName: 'com.whatsapp',
        label: 'WhatsApp',
        icon: icon,
        logo: logo,
      );
      await tester.pumpWidget(
        SceneAssetsScope(
          assets: assets,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: LauncherIcon(
              app: whatsapp,
              theme: home,
              accent: Colors.orange,
            ),
          ),
        ),
      );
      expect(painterIn(tester).logo, logo);
    });

    test(
      'a pinned shortcut draws the app\'s logo on the pack\'s tile',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        await download(look.icons.pack.assets);
        const channel = MethodChannel('wallp/icons');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        Object? sent;
        messenger.setMockMethodCallHandler(channel, (call) async {
          sent = (call.arguments as Map)['icon'];
          return true;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

        await const IconPackService().pin(
          theme: home,
          app: InstalledApp(
            packageName: 'com.whatsapp',
            label: 'WhatsApp',
            icon: await _square(const Color(0xFF25D366)),
            logo: await _square(const Color(0xFFFFFFFF)),
          ),
          accent: Colors.orange,
          assets: assets,
        );
        expect(sent, isA<Uint8List>());
      },
    );

    test('a pinned shortcut for an app with no logo is still themed', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('wallp/icons');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Object? sent;
      messenger.setMockMethodCallHandler(channel, (call) async {
        sent = (call.arguments as Map)['icon'];
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final added = await const IconPackService().pin(
        theme: home,
        app: const InstalledApp(packageName: 'com.shopee.mm', label: 'Shopee'),
        accent: Colors.orange,
        assets: assets,
      );
      expect(added, isTrue);
      expect(sent, isA<Uint8List>());
    });
  });
}

/// A plain coloured square standing in for an app icon or logo.
Future<ui.Image> _square(Color color) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
      .drawRect(const Rect.fromLTWH(0, 0, 48, 48), Paint()..color = color);
  return recorder.endRecording().toImage(48, 48);
}
