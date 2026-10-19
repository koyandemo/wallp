import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/core/clock.dart';
import 'package:wallp/data/api/account_models.dart';
import 'package:wallp/data/api/account_service.dart';
import 'package:wallp/data/api/api_exception.dart';
import 'package:wallp/data/api/auth_session.dart';
import 'package:wallp/data/api/token_store.dart';

import 'fake_backend.dart';

const _email = 'ana@example.com';
const _password = 'correct horse battery';

final _ana = AccountUser(
  id: 'u1',
  email: _email,
  displayName: 'Ana',
  createdAt: DateTime.utc(2026, 10, 18),
);

Matcher _fails(ApiErrorCode code) =>
    throwsA(isA<ApiException>().having((e) => e.code, 'code', code));

void main() {
  late FakeBackend server;
  late MemoryTokenStore store;
  late AuthSession session;
  late AccountService account;

  setUp(() {
    server = FakeBackend()..addUser(_email, _password);
    store = MemoryTokenStore();
    session = AuthSession(api: server.api, store: store);
    account = AccountService(server.api, session);
  });

  group('sign in', () {
    test('login saves the refresh token, not the access token', () async {
      await session.login(email: _email, password: _password);
      expect(session.isSignedIn, isTrue);
      expect(session.user?.displayName, 'Ana');
      expect(store.saved?.refreshToken, startsWith('r'));
      expect(store.saved?.user.email, _email);
    });

    test('wrong password', () async {
      await expectLater(
        session.login(email: _email, password: 'nope nope nope'),
        _fails(ApiErrorCode.badCredentials),
      );
      expect(session.isSignedIn, isFalse);
    });

    test('register, and register again with the same email', () async {
      await session.register(
        email: 'bo@example.com',
        password: 'long enough pass',
        displayName: 'Bo',
      );
      expect(session.user?.displayName, 'Bo');
      await expectLater(
        session.register(
          email: _email,
          password: 'long enough pass',
          displayName: 'X',
        ),
        _fails(ApiErrorCode.registrationFailed),
      );
    });

    test('logout signs out even with no connection', () async {
      await session.login(email: _email, password: _password);
      server.offline = true;
      await session.logout();
      expect(session.isSignedIn, isFalse);
      expect(store.saved, isNull);
      expect(session.lastSignOut, SignOutReason.signedOut);
    });
  });

  group('start', () {
    test('restores the saved sign-in and refreshes it', () async {
      store.saved = SavedLogin(server.issueRefresh(_email), _ana);
      final first = store.saved!.refreshToken;
      await session.start();
      expect(session.isSignedIn, isTrue);
      expect(session.user?.email, _email);
      await pumpEventQueue();
      expect(server.refreshCalls, 1);
      // Rotated and saved at once.
      expect(store.saved!.refreshToken, isNot(first));
    });

    test('a dead saved token signs out quietly', () async {
      store.saved = SavedLogin('r-unknown', _ana);
      await session.start();
      await pumpEventQueue();
      expect(session.isSignedIn, isFalse);
      expect(session.lastSignOut, SignOutReason.expired);
      expect(store.saved, isNull);
    });

    test('offline keeps the sign-in', () async {
      store.saved = SavedLogin(server.issueRefresh(_email), _ana);
      server.offline = true;
      await session.start();
      await pumpEventQueue();
      expect(session.isSignedIn, isTrue);
      expect(store.saved, isNotNull);
      await expectLater(account.me(), _fails(ApiErrorCode.offline));
      expect(session.isSignedIn, isTrue);
    });
  });

  group('refresh', () {
    test(
      'an expired access token is refreshed once and the call retried',
      () async {
        await session.login(email: _email, password: _password);
        server.expireAccessTokens();
        expect((await account.me()).email, _email);
        expect(server.refreshCalls, 1);
      },
    );

    test('calls failing together share one refresh', () async {
      await session.login(email: _email, password: _password);
      server
        ..expireAccessTokens()
        ..holdRefresh = Completer<void>();
      final calls = [account.me(), account.me(), account.me()];
      await pumpEventQueue();
      server.holdRefresh!.complete();
      await Future.wait(calls);
      // A second refresh with the same token would sign out everywhere.
      expect(server.refreshCalls, 1);
      expect(session.isSignedIn, isTrue);
    });

    test('refreshes early when the token is about to end', () async {
      final now = DateTime.utc(2026, 10, 18, 10);
      server.expiresAt = now.add(const Duration(seconds: 30));
      session = AuthSession(
        api: server.api,
        store: store,
        clock: FixedClock(now),
      );
      account = AccountService(server.api, session);
      await session.login(email: _email, password: _password);
      await account.me();
      expect(server.refreshCalls, 1);
    });

    test('a reused refresh token signs out everywhere', () async {
      final stolen = server.issueRefresh(_email);
      store.saved = SavedLogin(stolen, _ana);
      // Someone else refreshes with it first.
      final thief = AuthSession(
        api: server.newApi(),
        store: MemoryTokenStore(SavedLogin(stolen, _ana)),
      );
      await thief.start();
      await pumpEventQueue();

      await session.start();
      await pumpEventQueue();
      expect(session.isSignedIn, isFalse);
      expect(session.lastSignOut, SignOutReason.reused);
    });
  });

  group('account', () {
    setUp(() => session.login(email: _email, password: _password));

    test('rename updates the saved user', () async {
      await account.updateDisplayName('Ana M');
      expect(session.user?.displayName, 'Ana M');
      expect(store.saved?.user.displayName, 'Ana M');
    });

    test('password change signs back in with the new password', () async {
      final ok = await account.changePassword(
        current: _password,
        next: 'a new long password',
      );
      expect(ok, isTrue);
      expect(session.isSignedIn, isTrue);
      expect((await account.me()).email, _email);
    });

    test('wrong current password names the field', () async {
      await expectLater(
        account.changePassword(current: 'wrong one!!', next: 'whatever long'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.field,
            'field',
            'currentPassword',
          ),
        ),
      );
      expect(session.isSignedIn, isTrue);
    });

    test('sessions mark this phone', () async {
      server.issueRefresh(_email); // another phone
      final list = await account.sessions();
      expect(list, hasLength(2));
      expect(list.where((s) => s.current), hasLength(1));
    });

    test('revoking this phone signs out', () async {
      final mine = (await account.sessions()).singleWhere((s) => s.current);
      await account.revokeSession(mine);
      expect(session.isSignedIn, isFalse);
    });

    test('delete account', () async {
      await account.deleteAccount(_password);
      expect(session.isSignedIn, isFalse);
      expect(session.lastSignOut, SignOutReason.deleted);
      expect(server.users, isEmpty);
    });
  });
}
