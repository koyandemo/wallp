import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/data/api/auth_session.dart';
import 'package:wallp/services/launcher_service.dart';
import 'package:wallp/store/screens/me_screen.dart';

import 'harness.dart';

const _email = 'ana@example.com';
const _password = 'correct horse battery';

class _NoLauncher extends LauncherService {
  @override
  Future<bool> isDefaultHome() async => false;
}

void main() {
  late StoreHarness h;

  Future<void> pumpMe(WidgetTester tester) async {
    h = StoreHarness()..server.addUser(_email, _password);
    await h.pump(
      tester,
      home: Scaffold(body: MeScreen(launcher: _NoLauncher())),
    );
    await settle(tester);
    await scrollTo(tester, find.text('Account'));
  }

  Future<void> fill(WidgetTester tester, String label, String text) =>
      tester.enterText(find.widgetWithText(TextFormField, label), text);

  testWidgets('signed out by default, and nothing needs a sign-in', (
    tester,
  ) async {
    await pumpMe(tester);
    expect(find.text('Sign in'), findsOneWidget);
    expect(
      find.text('Optional: keep your favourites on every phone'),
      findsOneWidget,
    );
    expect(h.server.log, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sign in, open the account, sign out', (tester) async {
    await pumpMe(tester);
    await tester.tap(find.text('Sign in'));
    await settle(tester);

    await fill(tester, 'Email', _email);
    await fill(tester, 'Password', 'wrong password!');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester);
    expect(find.text('Wrong email or password.'), findsOneWidget);

    await fill(tester, 'Password', _password);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester);
    expect(find.text('Signed in as Ana'), findsOneWidget);
    expect(find.text(_email), findsOneWidget);

    await tester.tap(find.text('Ana'));
    await settle(tester);
    expect(find.text('This phone'), findsOneWidget);

    await scrollTo(tester, find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await settle(tester);
    expect(h.session.isSignedIn, isFalse);
    expect(find.text('Sign in'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('create an account; short passwords are caught first', (
    tester,
  ) async {
    await pumpMe(tester);
    await tester.tap(find.text('Sign in'));
    await settle(tester);
    await tester.tap(find.text('New here? Create an account'));
    await settle(tester);

    await fill(tester, 'Name', 'Bo');
    await fill(tester, 'Email', 'bo@example.com');
    await fill(tester, 'Password', 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await settle(tester);
    expect(find.text('Use 10 to 256 characters'), findsOneWidget);
    expect(h.server.log, isEmpty);

    await fill(tester, 'Password', 'long enough password');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await settle(tester);
    expect(h.session.user?.displayName, 'Bo');
    expect(find.text('Signed in as Bo'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a sign-in that ended elsewhere says so', (tester) async {
    await pumpMe(tester);
    await h.session.signOutLocally(SignOutReason.reused);
    await settle(tester);
    expect(find.text('You were signed out. Sign in again.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
