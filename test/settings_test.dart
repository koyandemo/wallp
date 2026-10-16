import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:wallp/core/app_theme.dart';
import 'package:wallp/data/theme_catalog.dart';
import 'package:wallp/screens/settings_screen.dart';
import 'package:wallp/services/my_themes.dart';
import 'package:wallp/widgets/current_theme_card.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> pumpSettings(WidgetTester tester, MyThemes my) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: my,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('shows the applied theme as the current theme', (tester) async {
    final halloween = ThemeCatalog.byId('halloween-night')!;
    final my = MyThemes();
    await my.load();
    await my.recordApplied(halloween, halloween.palette.accent);

    await pumpSettings(tester, my);

    expect(find.text('Current theme'), findsOneWidget);
    final card = tester.widget<CurrentThemeCard>(find.byType(CurrentThemeCard));
    expect(card.entry.theme, halloween);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('says no theme is applied yet', (tester) async {
    final my = MyThemes();
    await my.load();

    await pumpSettings(tester, my);

    expect(find.byType(CurrentThemeCard), findsNothing);
    expect(
      find.text('No theme applied yet. Pick one in Explore and apply it.'),
      findsOneWidget,
    );
  });
}
