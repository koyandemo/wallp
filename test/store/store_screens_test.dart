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

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
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
      for (final label in ['Store', 'Themes', 'Wallpapers', 'Fonts', 'Me']) {
        expect(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
      // Store home: today's banners and the soonest festival first.
      expect(
        find.bySemanticsLabel(RegExp('Halloween Night, banner 1 of 4')),
        findsOneWidget,
      );
      expect(find.text('16 nights left · 8 themes'), findsOneWidget);

      await tapTab(tester, 'Themes');
      expect(find.text('30 themes'), findsOneWidget);
      await tapTab(tester, 'Wallpapers');
      expect(find.text('12 wallpapers'), findsOneWidget);
      await tapTab(tester, 'Fonts');
      expect(find.text('10 fonts for the lock and home clock'), findsOneWidget);
      await tapTab(tester, 'Me');
      expect(find.text('Your look, favourites and settings'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Themes tab', () {
    testWidgets('filter chips and sort change the list', (tester) async {
      await h.pump(tester);
      await tapTab(tester, 'Themes');
      await tapChip(tester, 'Myanmar');
      expect(find.text('9 themes'), findsOneWidget);

      await tapChip(tester, 'Festivals');
      expect(find.text('5 festivals'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Christmas, 71 days left, 10 themes')),
        findsOneWidget,
      );

      await tapChip(tester, 'Favourites');
      expect(find.text('No favourites yet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('festival page', () {
    testWidgets('style chips, sort, and the empty message', (tester) async {
      await h.pump(
        tester,
        home: const FestivalScreen(festivalId: 'thadingyut'),
      );
      await settle(tester);
      expect(find.text('3 themes'), findsWidgets);
      await tapChip(tester, 'Minimal');
      expect(find.text('No minimal Thadingyut themes yet'), findsOneWidget);
      await tapChip(tester, 'Live');
      expect(find.text('2 themes'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('quick look steps through themes', (tester) async {
      await h.pump(
        tester,
        home: const FestivalScreen(festivalId: 'thadingyut'),
        themes: ['festival-of-lights', 'candle-glow', 'paper-lanterns'],
      );
      await settle(tester);
      await tester.tap(find.byTooltip('Quick look at Festival of Lights'));
      await settle(tester);
      expect(find.text('1 of 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Next theme'));
      await settle(tester);
      expect(find.text('2 of 3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('theme detail', () {
    testWidgets('shows the theme, its colours and what it includes', (
      tester,
    ) async {
      await h.pump(
        tester,
        home: const ThemeDetailScreen(themeId: 'cozy-cabin'),
        themes: ['cozy-cabin'],
      );
      await settle(tester);
      expect(find.text('Cozy Cabin'), findsOneWidget);
      expect(find.bySemanticsLabel('Snowed in'), findsOneWidget);
      await scrollTo(tester, find.text('Caveat clock font'));
      expect(find.text('Wallpaper'), findsOneWidget);
      expect(find.text('Candy Cane icons'), findsOneWidget);
      expect(find.text('Caveat clock font'), findsOneWidget);
      expect(find.textContaining('Apply'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the heart saves a favourite', (tester) async {
      await h.pump(
        tester,
        home: const ThemeDetailScreen(themeId: 'cozy-cabin'),
        themes: ['cozy-cabin'],
      );
      await settle(tester);
      await tester.tap(find.byTooltip('Add to favourites'));
      await settle(tester);
      expect(h.user.isFavouriteTheme('cozy-cabin'), isTrue);
      expect(find.byTooltip('Remove from favourites'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the Apply sheet offers all three ways', (tester) async {
      await h.pump(
        tester,
        home: const ThemeDetailScreen(themeId: 'cozy-cabin'),
        themes: ['cozy-cabin'],
      );
      await settle(tester);
      await tester.tap(find.byType(FilledButton));
      await settle(tester);
      expect(find.text('Apply Cozy Cabin'), findsOneWidget);
      expect(find.text('Whole theme'), findsOneWidget);
      expect(find.text('Wallpaper only'), findsOneWidget);
      expect(find.text('Clock font only'), findsOneWidget);
      expect(find.text('Caveat on the lock and home clock'), findsOneWidget);
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
      await tester.tap(find.text('Gradient'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Witching hour'));
      await settle(tester);
      expect(find.text('Use Witching hour'), findsOneWidget);
      await tester.tap(find.text('Custom'));
      await settle(tester);
      expect(find.text('Start colour'), findsOneWidget);
      expect(find.text('Save to My accents'), findsOneWidget);
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
        await h.user.toggleTheme('ember');
        await h.user.toggleTheme('cozy-cabin');
      });
      await tapTab(tester, 'Me');
      expect(find.text('2 themes'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove Cozy Cabin from favourites'));
      await settle(tester);
      expect(h.user.favouriteThemes, ['ember']);
      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(h.user.favouriteThemes, ['cozy-cabin', 'ember']);
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
