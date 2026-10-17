import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/services/launcher_service.dart';
import 'package:wallp/store/screens/me_screen.dart';

import 'harness.dart';

/// Android's home screen settings, pretended: [isDefault] is what the
/// phone says; asking switches it, as the user would in Settings.
class _FakeLauncher extends LauncherService {
  _FakeLauncher({required this.isDefault});

  bool isDefault;
  int requests = 0, opened = 0;

  @override
  Future<bool> isDefaultHome() async => isDefault;

  @override
  Future<bool> requestDefaultHome() async {
    requests++;
    isDefault = !isDefault; // The user picked the other one.
    return isDefault;
  }

  @override
  Future<bool> goHome() async {
    opened++;
    return true;
  }
}

void main() {
  final h = StoreHarness();

  Future<_FakeLauncher> pumpMe(
    WidgetTester tester, {
    required bool isDefault,
  }) async {
    final launcher = _FakeLauncher(isDefault: isDefault);
    await h.pump(
      tester,
      home: Scaffold(body: MeScreen(launcher: launcher)),
    );
    await settle(tester);
    await scrollTo(tester, find.text('What is wallp Home?'));
    return launcher;
  }

  testWidgets('not the home app: a clear button to use it', (tester) async {
    final launcher = await pumpMe(tester, isDefault: false);
    expect(find.text('Use wallp as your home screen'), findsOneWidget);
    expect(find.text('Change home app'), findsNothing);
    await tester.tap(find.text('Use wallp Home'));
    await settle(tester);
    expect(launcher.requests, 1);
    expect(find.text('wallp is your home screen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the home app: still tappable, with links to open or change it', (
    tester,
  ) async {
    final launcher = await pumpMe(tester, isDefault: true);
    expect(find.text('wallp is your home screen'), findsOneWidget);
    expect(find.text('Use wallp Home'), findsNothing);

    await tester.tap(find.text('Open wallp Home'));
    await settle(tester);
    expect(launcher.opened, 1);

    // Back to another home screen: opens Android's Home app settings.
    await tester.tap(find.text('Change home app'));
    await settle(tester);
    expect(launcher.requests, 1);
    expect(find.text('Use wallp as your home screen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('comes back from Android settings with the new status', (
    tester,
  ) async {
    final launcher = await pumpMe(tester, isDefault: true);
    // Changed in Settings behind the app's back.
    launcher.isDefault = false;
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await settle(tester);
    expect(find.text('Use wallp as your home screen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('"What is wallp Home?" explains, and how to switch back', (
    tester,
  ) async {
    await pumpMe(tester, isDefault: true);
    await tester.tap(find.text('What is wallp Home?'));
    await settle(tester);
    expect(
      find.textContaining('switch back to your old home screen'),
      findsOneWidget,
    );
    await tester.tap(find.text('OK'));
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('gray footer links: clear searches, free up space, version', (
    tester,
  ) async {
    final launcher = _FakeLauncher(isDefault: true);
    await h.pump(
      tester,
      home: Scaffold(body: MeScreen(launcher: launcher)),
    );
    await tester.runAsync(() => h.user.rememberQuery('moon'));
    await settle(tester);
    await scrollTo(tester, find.textContaining('wallp 1.0.0'));
    expect(find.text('Free up space'), findsOneWidget);
    await tester.tap(find.text('Clear recent searches'));
    await settle(tester);
    expect(h.user.recentSearches, isEmpty);
    expect(find.text('Clear recent searches'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('favourite wallpapers show up', (tester) async {
    final launcher = _FakeLauncher(isDefault: true);
    await h.pump(
      tester,
      home: Scaffold(body: MeScreen(launcher: launcher)),
    );
    await tester.runAsync(() => h.user.toggleWallpaper('red-moon-swing'));
    await settle(tester);
    await scrollTo(tester, find.text('Favourite wallpapers'));
    expect(find.text('1 wallpaper'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
