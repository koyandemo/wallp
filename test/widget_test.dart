import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:wallp/app.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2340);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  /// The Next up card animates forever, so step time instead of settling.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Explore shows header, next-up card, chips and theme tiles', (
    tester,
  ) async {
    await tester.pumpWidget(const WallpApp());

    expect(find.text('Seasonal themes'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Next up: ')), findsOneWidget);
    expect(find.byKey(const ValueKey('chip-halloween')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chip-christmas')));
    await settle(tester);
    expect(find.bySemanticsLabel(RegExp(r'^Christmas theme')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('A coming-soon category shows its placeholder', (tester) async {
    await tester.pumpWidget(const WallpApp());

    // The chip row scrolls sideways; Kpop starts off-screen on a phone.
    final kpop = find.byKey(const ValueKey('chip-kpop'));
    await tester.scrollUntilVisible(
      kpop,
      150,
      scrollable: find
          .ancestor(
            of: find.byKey(const ValueKey('chip-halloween')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(kpop);
    await settle(tester);

    expect(find.text('Kpop themes'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Bottom navigation switches to My Themes', (tester) async {
    await tester.pumpWidget(const WallpApp());

    await tester.tap(find.text('My Themes'));
    await settle(tester);

    expect(find.text('Nothing here yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('♡ on Explore saves the theme to My Themes', (tester) async {
    await tester.pumpWidget(const WallpApp());
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('chip-christmas')));
    await settle(tester);
    await tester.tap(find.byTooltip('Add Christmas to favourites'));
    await settle(tester);
    expect(find.byTooltip('Remove Christmas from favourites'), findsOneWidget);

    await tester.tap(find.text('My Themes'));
    await settle(tester);
    expect(find.text('Favourites'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Christmas theme')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
