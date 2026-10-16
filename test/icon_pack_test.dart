import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:wallp/core/app_theme.dart';
import 'package:wallp/icons/app_glyphs.dart';
import 'package:wallp/store/screens/pin_shortcuts_screen.dart';

import 'look/fixtures.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('glyphFor', () {
    test('matches well-known apps by package or label', () {
      expect(
        glyphFor('com.google.android.dialer', 'Phone'),
        Icons.phone_rounded,
      );
      expect(glyphFor('com.whatsapp', 'WhatsApp'), Icons.forum_rounded);
      expect(
        glyphFor('com.google.android.apps.messaging', 'Messages'),
        Icons.chat_bubble_rounded,
      );
      expect(glyphFor('com.android.chrome', 'Chrome'), Icons.public_rounded);
      expect(
        glyphFor('com.google.android.youtube', 'YouTube'),
        Icons.play_arrow_rounded,
      );
    });

    test('returns null for unknown apps and avoids loose matches', () {
      expect(glyphFor('com.example.deadline', 'Deadline'), isNull);
      expect(glyphFor('org.knowledge.base', 'Knowledge'), isNull);
      expect(glyphFor('com.coloros.backuprestore', 'Clone Phone'), isNull);
    });
  });

  testWidgets('lists apps and pins a Halloween icon shortcut', (tester) async {
    const channel = MethodChannel('wallp/icons');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'canPinShortcuts' => true,
            'listApps' => [
              {'package': 'com.whatsapp', 'label': 'WhatsApp', 'icon': null},
              {
                'package': 'com.example.game',
                'label': 'Cool Game',
                'icon': null,
              },
            ],
            'pinShortcut' => true,
            _ => null,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final halloween = builtInTheme('halloween-night');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: PinShortcutsScreen(
          theme: halloween,
          accent: halloween.palette.accent,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Cool Game'), findsOneWidget);

    await tester.tap(find.text('Add').first);
    // Rendering the icon PNG runs on the engine, outside the fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pumpAndSettle();

    final pin = calls.singleWhere((c) => c.method == 'pinShortcut');
    final args = pin.arguments as Map;
    expect(args['id'], 'halloween-night-com.whatsapp');
    expect(args['package'], 'com.whatsapp');
    expect(args['label'], 'WhatsApp');
    final png = args['icon'] as Uint8List;
    expect(png.sublist(1, 4), 'PNG'.codeUnits);
    // Adaptive icon bitmap: 432 × 432.
    final header = ByteData.sublistView(png, 16, 24);
    expect(header.getUint32(0), 432);
    expect(header.getUint32(4), 432);

    expect(find.text('Added'), findsOneWidget);
    expect(
      find.text('Confirm to add WhatsApp to your home screen'),
      findsOneWidget,
    );
  });

  /// Mocks a home screen app that can't pin shortcuts; [wallpIsHome] says
  /// whether that home app is wallp itself.
  void mockCannotPin({required bool wallpIsHome}) {
    const icons = MethodChannel('wallp/icons');
    const launcher = MethodChannel('wallp/launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      icons,
      (call) async => switch (call.method) {
        'listApps' => [
          {'package': 'com.whatsapp', 'label': 'WhatsApp', 'icon': null},
        ],
        _ => false,
      },
    );
    messenger.setMockMethodCallHandler(
      launcher,
      (call) async => call.method == 'isDefaultHome' && wallpIsHome,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(icons, null);
      messenger.setMockMethodCallHandler(launcher, null);
    });
  }

  Future<void> pumpIconPack(WidgetTester tester) async {
    final halloween = builtInTheme('halloween-night');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: PinShortcutsScreen(
          theme: halloween,
          accent: halloween.palette.accent,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('explains when the launcher cannot pin shortcuts', (
    tester,
  ) async {
    mockCannotPin(wallpIsHome: false);
    await pumpIconPack(tester);

    expect(find.text('Not available on this phone'), findsOneWidget);
  });

  testWidgets('lists themed icons without Add when wallp is the home app', (
    tester,
  ) async {
    mockCannotPin(wallpIsHome: true);
    await pumpIconPack(tester);

    expect(find.text('Your Haunted Moon icons'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Add'), findsNothing);
    expect(find.text('Not available on this phone'), findsNothing);
  });
}
