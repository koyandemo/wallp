import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wallp/data/account/account_repository.dart';
import 'package:wallp/data/account/token_store.dart';
import 'package:wallp/data/api/api_client.dart';
import 'package:wallp/store/state/favourites_sync.dart';
import 'package:wallp/store/state/user_store.dart';

import 'fake_backend.dart';

void main() {
  late FakeBackend server;
  late MemoryTokenStore tokens;

  AccountRepository repo() =>
      AccountRepository(client: server.client(), tokens: tokens);

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    server = FakeBackend()..addUser('ana@example.com', 'correct horse battery');
    tokens = MemoryTokenStore();
  });

  group('AccountRepository', () {
    test('login keeps the refresh token, not the access token', () async {
      final account = repo();
      final changes = <AccountChange>[];
      account.changes.listen(changes.add);
      final user = await account.login(
        email: 'ana@example.com',
        password: 'correct horse battery',
      );
      expect(user.displayName, 'Ana');
      expect(account.isSignedIn, isTrue);
      expect(tokens.login!.refreshToken, startsWith('r'));
      await pumpEventQueue();
      expect(
        changes.single,
        isA<SignedIn>().having((c) => c.fresh, 'fresh', true),
      );
    });

    test('wrong password is 401 bad_credentials', () async {
      expect(
        repo().login(email: 'ana@example.com', password: 'nope nope nope'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'bad_credentials'),
        ),
      );
    });

    test('register; a taken email is registration_failed', () async {
      final account = repo();
      await account.register(
        email: 'bo@example.com',
        password: 'long enough pw',
        displayName: 'Bo',
      );
      expect(account.user!.email, 'bo@example.com');
      expect(
        repo().register(
          email: 'bo@example.com',
          password: 'long enough pw',
          displayName: 'Bo',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'registration_failed',
          ),
        ),
      );
    });

    test('an expired access token is refreshed once, then retried', () async {
      final account = repo();
      await account.login(
        email: 'ana@example.com',
        password: 'correct horse battery',
      );
      final firstRefresh = tokens.login!.refreshToken;
      server.expireAccessTokens();

      final me = await account.reloadMe();
      expect(me.email, 'ana@example.com');
      expect(server.count('POST /v1/auth/refresh'), 1);
      expect(
        tokens.login!.refreshToken,
        isNot(firstRefresh),
        reason: 'rotated',
      );
    });

    test('calls racing on an expired token share one refresh', () async {
      final account = repo();
      await account.login(
        email: 'ana@example.com',
        password: 'correct horse battery',
      );
      server.expireAccessTokens();
      await Future.wait([
        account.reloadMe(),
        account.favourites(),
        account.sessions(),
      ]);
      expect(server.count('POST /v1/auth/refresh'), 1);
      expect(account.isSignedIn, isTrue);
    });

    test('restore: a saved login refreshes and stays signed in', () async {
      await repo().login(
        email: 'ana@example.com',
        password: 'correct horse battery',
      );
      final account = repo();
      final changes = <AccountChange>[];
      account.changes.listen(changes.add);
      await account.restore();
      expect(account.isSignedIn, isTrue);
      await pumpEventQueue();
      expect(
        changes.single,
        isA<SignedIn>().having((c) => c.fresh, 'fresh', false),
      );
    });

    test('restore offline keeps the login for later', () async {
      await repo().login(
        email: 'ana@example.com',
        password: 'correct horse battery',
      );
      server.offline = true;
      final account = repo();
      await account.restore();
      expect(account.isSignedIn, isTrue);
      expect(tokens.login, isNotNull);
    });

    test('a reused refresh token signs out', () async {
      await repo().login(
        email: 'ana@example.com',
        password: 'correct horse battery',
      );
      final stolen = tokens.login!;
      await repo().restore(); // uses and rotates it
      tokens.login = stolen; // the old one comes back
      final account = repo();
      final changes = <AccountChange>[];
      account.changes.listen(changes.add);
      await account.restore();
      expect(account.isSignedIn, isFalse);
      expect(tokens.login, isNull);
      await pumpEventQueue();
      expect(
        changes.single,
        isA<SignedOut>().having(
          (c) => c.reason,
          'reason',
          SignOutReason.reused,
        ),
      );
    });

    test('logout clears tokens even offline', () async {
      final account = repo();
      await account.login(
        email: 'ana@example.com',
        password: 'correct horse battery',
      );
      server.offline = true;
      await account.logout();
      expect(account.isSignedIn, isFalse);
      expect(tokens.login, isNull);
    });

    test('changing the password signs straight back in', () async {
      final account = repo();
      await account.login(
        email: 'ana@example.com',
        password: 'correct horse battery',
      );
      await account.changePassword(
        currentPassword: 'correct horse battery',
        newPassword: 'even better password',
      );
      expect(account.isSignedIn, isTrue);
      server.expireAccessTokens();
      await account.reloadMe(); // the new refresh token works
      expect(account.isSignedIn, isTrue);
    });

    test('install link: 409 from another account counts as done', () async {
      server.addUser('bo@example.com', 'another password');
      const install = '6f1c2e0a-7a53-4c4e-9a61-0d1e8f3b2c11';
      final bo = repo();
      await bo.login(email: 'bo@example.com', password: 'another password');
      await bo.linkInstall(install, '1.0.0');
      final ana = AccountRepository(
        client: server.client(),
        tokens: MemoryTokenStore(),
      );
      await ana.login(
        email: 'ana@example.com',
        password: 'correct horse battery',
      );
      await ana.linkInstall(install, '1.0.0');
      expect(server.installs[install], server.userId('bo@example.com'));
    });
  });

  group('FavouritesSync', () {
    late AccountRepository account;
    late UserStore user;
    late FavouritesSync sync;

    setUp(() async {
      account = repo();
      user = UserStore();
      await user.load();
      sync = FavouritesSync(account: account, user: user)..start();
    });

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await pumpEventQueue();
        await sync.sync();
      }
    }

    List<String> serverIds() => [
      for (final f in server.favourites[server.userId('ana@example.com')]!)
        '${f['itemType']}/${f['itemId']}',
    ];

    test('first sign-in merges phone and account, then uploads', () async {
      server.favourites[server.userId('ana@example.com')]!.addAll([
        {
          'itemType': 'theme',
          'itemId': 'from-other-phone',
          'createdAt': '2026-10-19T00:00:00Z',
        },
        {
          'itemType': 'font',
          'itemId': 'inter',
          'createdAt': '2026-10-19T00:00:00Z',
        },
      ]);
      await user.toggleTheme('local-theme');
      await user.toggleWallpaper('moon-1');

      await account.login(
        email: 'ana@example.com',
        password: 'correct horse battery',
      );
      await settle();

      expect(user.favouriteThemes, ['local-theme', 'from-other-phone']);
      expect(user.favouriteWallpapers, ['moon-1']);
      expect(
        serverIds(),
        unorderedEquals([
          'theme/local-theme',
          'theme/from-other-phone',
          'wallpaper/moon-1',
          'font/inter',
        ]),
        reason: "the font favourite isn't lost",
      );
    });

    test('hearts while signed in go straight to the account', () async {
      await account.login(
        email: 'ana@example.com',
        password: 'correct horse battery',
      );
      await settle();
      await user.toggleTheme('spider-night');
      await settle();
      expect(serverIds(), ['theme/spider-night']);
      await user.toggleTheme('spider-night');
      await settle();
      expect(serverIds(), isEmpty);
    });

    test('offline hearts are queued and sent later', () async {
      await account.login(
        email: 'ana@example.com',
        password: 'correct horse battery',
      );
      await settle();
      server.offline = true;
      await user.toggleTheme('halloween-night');
      await settle();
      expect(user.favouriteThemes, ['halloween-night']);
      server.offline = false;
      await settle();
      expect(serverIds(), ['theme/halloween-night']);
      expect(user.favouriteThemes, ['halloween-night']);
    });

    test(
      'after the first merge, removals on another phone show here',
      () async {
        await user.toggleTheme('a');
        await account.login(
          email: 'ana@example.com',
          password: 'correct horse battery',
        );
        await settle();
        expect(serverIds(), ['theme/a']);
        // Another phone un-hearts it.
        server.favourites[server.userId('ana@example.com')]!.clear();
        await settle();
        expect(user.favouriteThemes, isEmpty);
      },
    );

    test('signing out keeps the phone\'s favourites', () async {
      await account.login(
        email: 'ana@example.com',
        password: 'correct horse battery',
      );
      await user.toggleTheme('keep-me');
      await settle();
      await account.logout();
      await pumpEventQueue();
      expect(user.favouriteThemes, ['keep-me']);
      await user.toggleTheme('offline-only');
      await settle();
      expect(serverIds(), ['theme/keep-me'], reason: 'nothing sent signed out');
    });
  });
}
