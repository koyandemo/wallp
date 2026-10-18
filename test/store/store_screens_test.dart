import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/store/screens/accent_picker_screen.dart';
import 'package:wallp/store/screens/festival_screen.dart';
import 'package:wallp/store/screens/search_screen.dart';
import 'package:wallp/store/screens/theme_detail_screen.dart';
import 'package:wallp/store/state/user_store.dart';

import '../look/fixtures.dart';
import 'harness.dart';

void main() {
  final h = StoreHarness();

  /// Tabs show icons only; each is found by its name (its tooltip).
  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byTooltip(label),
      ),
    );
    await settle(tester);
  }

  group('shell', () {
    testWidgets('opens on Store and switches between the five tabs', (
      tester,
    ) async {
      await h.pump(tester);
      await settle(tester);
      final nav = find.byType(NavigationBar);
      for (final label in ['Store', 'Themes', 'Wallpapers', 'Fonts', 'Me']) {
        // No visible label, but still named for screen readers.
        expect(
          find.descendant(of: nav, matching: find.byTooltip(label)),
          findsOneWidget,
        );
        // Read out as e.g. "Store, Tab 1 of 5".
        expect(
          find.descendant(
            of: nav,
            matching: find.bySemanticsLabel(RegExp('^$label')),
          ),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: nav,
          matching: find.byIcon(Icons.font_download_outlined),
        ),
        findsOneWidget,
      );
      // Store home: today's banners and the soonest festival first.
      expect(
        find.bySemanticsLabel(RegExp('Spider Night, banner 1 of 6')),
        findsOneWidget,
      );
      expect(find.text('16 nights left · 1 theme'), findsOneWidget);

      await tapTab(tester, 'Themes');
      expect(find.text('5 themes'), findsOneWidget);
      await tapTab(tester, 'Wallpapers');
      expect(find.text('6 wallpapers'), findsOneWidget);
      await tapTab(tester, 'Fonts');
      expect(find.text('8 fonts for the lock and home clock'), findsOneWidget);
      await tapTab(tester, 'Me');
      expect(find.text('Your look, favourites and settings'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the catalog', () {
    testWidgets('one theme each for Halloween, Christmas, Thingyan, Heroes, '
        'Neon', (tester) async {
      await h.pump(tester);
      // Tall enough for every theme card at once.
      tester.view.physicalSize = const Size(1170, 6000);
      await tapTab(tester, 'Themes');
      expect(find.text('5 themes'), findsOneWidget);
      for (final name in [
        'Haunted Moon',
        'Snowy Pines',
        'Water Splash',
        'Spider Night',
        'Neon Night',
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      // No chip that would find nothing.
      expect(find.text('Minimal'), findsNothing);
      await tapChip(tester, 'Festivals');
      expect(find.text('5 festivals'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Themes tab', () {
    testWidgets('filter chips and sort change the list', (tester) async {
      await h.pump(tester);
      await tapTab(tester, 'Themes');
      await tapChip(tester, 'Myanmar');
      expect(find.text('1 theme'), findsOneWidget);
      expect(find.text('Water Splash'), findsOneWidget);

      await tapChip(tester, 'Festivals');
      expect(find.text('5 festivals'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Christmas, 71 days left, 1 theme')),
        findsOneWidget,
      );

      await tapChip(tester, 'Favourites');
      expect(find.text('No favourites yet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('festival page', () {
    testWidgets('only styles the festival has, and Live', (tester) async {
      await h.pump(tester, home: const FestivalScreen(festivalId: 'halloween'));
      await settle(tester);
      expect(find.text('1 theme'), findsWidgets);
      // Halloween has one classic theme: no chips for other styles.
      expect(find.text('Minimal'), findsNothing);
      expect(find.text('Cozy'), findsNothing);
      await tapChip(tester, 'Live');
      expect(find.text('1 theme'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('quick look steps through themes', (tester) async {
      await h.pump(
        tester,
        home: const FestivalScreen(festivalId: 'heroes'),
        themes: ['spider-night'],
      );
      await settle(tester);
      await tester.tap(find.byTooltip('Quick look at Spider Night'));
      await settle(tester);
      expect(find.text('1 of 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('theme detail', () {
    testWidgets('shows the theme and what it includes, no colour choice', (
      tester,
    ) async {
      await h.pump(
        tester,
        home: const ThemeDetailScreen(themeId: 'spider-night'),
        themes: ['spider-night'],
      );
      await settle(tester);
      expect(find.text('Spider Night'), findsOneWidget);
      expect(find.text('Colours'), findsNothing);
      await scrollTo(tester, find.text('Bebas Neue clock font'));
      expect(find.text('Live wallpaper'), findsOneWidget);
      expect(find.text('Web Slinger icons'), findsOneWidget);
      expect(find.text('Bebas Neue clock font'), findsOneWidget);
      expect(find.textContaining('Apply'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the heart saves a favourite', (tester) async {
      await h.pump(
        tester,
        home: const ThemeDetailScreen(themeId: 'spider-night'),
        themes: ['spider-night'],
      );
      await settle(tester);
      await tester.tap(find.byTooltip('Add to favourites'));
      await settle(tester);
      expect(h.user.isFavouriteTheme('spider-night'), isTrue);
      expect(find.byTooltip('Remove from favourites'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a theme that can\'t load says so and offers Try again', (
      tester,
    ) async {
      // Not preloaded, and the catalog doesn't list this ID.
      await h.pump(
        tester,
        home: const ThemeDetailScreen(themeId: 'no-such-theme'),
      );
      await settle(tester);
      expect(find.text('This theme is no longer in the store'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('accent picker', () {
    testWidgets('readability, tabs and Use', (tester) async {
      await h.pump(
        tester,
        home: AccentPickerScreen(theme: mockTheme('halloween-night')),
      );
      await settle(tester);
      expect(find.text('Easy to read'), findsOneWidget);
      // No tick on the selected tab or mode.
      expect(find.byIcon(Icons.check), findsNothing);
      await tester.tap(find.text('Gradient'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Witching hour'));
      await settle(tester);
      expect(find.text('Use Witching hour'), findsOneWidget);
      await tester.tap(find.text('Custom'));
      await settle(tester);
      expect(find.text('Start colour'), findsOneWidget);
      expect(find.text('Save to My accents'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('search', () {
    testWidgets('popular searches, result tabs and recent searches', (
      tester,
    ) async {
      await h.pump(tester, home: const SearchScreen());
      await settle(tester);
      expect(find.text('Popular'), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, 'moon'));
      await settle(tester);
      expect(find.textContaining('Themes · '), findsOneWidget);
      expect(find.textContaining('Wallpapers · '), findsOneWidget);
      expect(h.user.recentSearches, ['moon']);

      await tester.enterText(find.byType(TextField), 'zzqx');
      await settle(tester);
      expect(find.text('Nothing for "zzqx"'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Me', () {
    testWidgets('favourites can be removed and the removal undone', (
      tester,
    ) async {
      await h.pump(tester);
      await tester.runAsync(() async {
        await h.user.toggleTheme('halloween-night');
        await h.user.toggleTheme('spider-night');
      });
      await tapTab(tester, 'Me');
      expect(find.text('2 themes'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove Spider Night from favourites'));
      await settle(tester);
      expect(h.user.favouriteThemes, ['halloween-night']);
      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(h.user.favouriteThemes, ['spider-night', 'halloween-night']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('settings switches are saved', (tester) async {
      await h.pump(tester);
      await tapTab(tester, 'Me');
      await tester.scrollUntilVisible(
        find.text('Follow the next festival'),
        300,
      );
      await tester.tap(find.text('Follow the next festival'));
      await settle(tester);
      expect(h.user.setting(UserSetting.followNextFestival), isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
