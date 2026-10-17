import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/data/assets/asset_cache.dart';
import 'package:wallp/icons/app_glyphs.dart';
import 'package:wallp/launcher/launcher_icon.dart';
import 'package:wallp/look/applied_look.dart';
import 'package:wallp/look/resolved_look.dart';
import 'package:wallp/render/font_registry.dart';
import 'package:wallp/render/image_icons.dart';
import 'package:wallp/render/scene_assets.dart';
import 'package:wallp/services/icon_pack_service.dart';

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

  group('glyph keys', () {
    test('apps map to the catalog\'s glyph keys', () {
      expect(glyphKeyFor('com.whatsapp', 'WhatsApp'), 'messages');
      expect(glyphKeyFor('com.google.android.dialer', 'Phone'), 'phone');
      expect(glyphKeyFor('com.instagram.android', 'Instagram'), 'camera');
      expect(glyphKeyFor('com.google.android.youtube', 'YouTube'), 'video');
      expect(glyphKeyFor('com.android.settings', 'Settings'), 'settings');
    });

    test('calls, pay and device-care apps get a picture too', () {
      expect(glyphKeyFor('com.google.android.apps.tachyon', 'Meet'), 'video');
      expect(glyphKeyFor('com.example.unknown', 'NugPay'), 'wallet');
      expect(
        glyphKeyFor('com.coloros.phonemanager', 'Phone Manager'),
        'settings',
      );
      expect(
        glyphKeyFor('com.google.android.apps.safetyhub', 'Safety'),
        'settings',
      );
    });

    test('apps no pack draws have no key, and keep their own icon', () {
      expect(glyphKeyFor('com.facebook.katana', 'Facebook'), isNull);
      expect(glyphKeyFor('com.example.game', 'Cool Game'), isNull);
    });

    test('every key an app can get is one packs draw', () {
      for (final (pkg, label) in [
        ('com.whatsapp', 'WhatsApp'),
        ('com.android.chrome', 'Chrome'),
        ('com.google.android.gm', 'Gmail'),
        ('com.spotify.music', 'Spotify'),
        ('com.android.vending', 'Play Store'),
        ('com.android.calculator2', 'Calculator'),
        ('com.google.android.keep', 'Keep Notes'),
      ]) {
        expect(GlyphKeys.all, contains(glyphKeyFor(pkg, label)), reason: pkg);
      }
    });
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
      expect(await registry.ensure(catalog.font('pacifico')!), isFalse);
      expect(registry.loadedFamily('Pacifico'), isNull);
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
          mockTheme('ember'),
          at: designDay,
        ).withIconPack(
          catalog.iconPack('mono-ember')!,
          at: designDay,
          shape: IconShape.circle,
        );
    final home = ResolvedLook.of(look, designDay).homeTheme;

    test('the resolved look carries the pack and the user\'s shape', () {
      expect(home.imageIcons, isNotNull);
      expect(home.imageIcons!.shape, IconShape.circle);
      expect(home.hasIconPack, isFalse, reason: 'not a painted pack');
    });

    testWidgets('an app with a picture shows it, clipped to the shape', (
      tester,
    ) async {
      // Download and decode for real first: inside testWidgets' fake clock,
      // file reads never finish.
      await tester.runAsync(() async {
        await download(look.icons.pack.glyphs.values);
        await assets.image(look.icons.pack.glyphs['messages']!);
      });
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
      // The picture was decoded in the real zone; its callback runs there,
      // so give real async a turn, then draw.
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.byType(ClipRRect), findsOneWidget);
      expect(find.byType(RawImage), findsOneWidget);
    });

    testWidgets('an app the pack doesn\'t draw is framed in its tile', (
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
      expect(find.byType(PackPictureIcon), findsNothing);
      expect(find.byType(PackFallbackIcon), findsOneWidget);
      expect(find.byIcon(Icons.apps_rounded), findsOneWidget);
    });

    testWidgets('a pack with a background puts the app on that picture', (
      tester,
    ) async {
      // Any of the pack's pictures stands in for its empty tile.
      final background = look.icons.pack.glyphs['phone']!;
      final pack = home.imageIcons!;
      final withBackground = home.copyWith(
        imageIcons: ImageIconPack(
          glyphs: pack.glyphs,
          shape: pack.shape,
          ring: pack.ring,
          tile: pack.tile,
          background: background,
        ),
      );
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
            child: LauncherIcon(
              app: game,
              theme: withBackground,
              accent: Colors.orange,
            ),
          ),
        ),
      );
      PackFallbackPainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byType(PackFallbackIcon),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter!
              as PackFallbackPainter;
      // The plain tile until the picture loads, then the picture.
      expect(find.byIcon(Icons.apps_rounded), findsOneWidget);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.byIcon(Icons.apps_rounded), findsNothing);
      expect(painter().background, isNotNull);
    });

    test('a pinned shortcut sends the pack\'s picture as is', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await download(look.icons.pack.glyphs.values);
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
        app: const InstalledApp(packageName: 'com.whatsapp', label: 'WhatsApp'),
        accent: Colors.orange,
        assets: assets,
      );
      final picture = look.icons.pack.glyphs['messages']!;
      expect(sent, File('$mockDir/${picture.url}').readAsBytesSync());
    });

    test(
      'a pinned shortcut for an app with no picture is still themed',
      () async {
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
          app: const InstalledApp(
            packageName: 'com.shopee.mm',
            label: 'Shopee',
          ),
          accent: Colors.orange,
          assets: assets,
        );
        expect(added, isTrue);
        expect(sent, isA<Uint8List>());
      },
    );
  });
}
