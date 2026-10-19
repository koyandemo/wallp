import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wallp/data/api/account_service.dart';
import 'package:wallp/data/api/api_client.dart';
import 'package:wallp/data/api/auth_session.dart';
import 'package:wallp/data/api/token_store.dart';
import 'package:wallp/store/state/favourites_sync.dart';
import 'package:wallp/store/state/user_store.dart';

import '../api/fake_backend.dart';

const _email = 'ana@example.com';
const _password = 'correct horse battery';

/// One phone: its own favourites, sign-in and sync, on a shared server.
class _Phone {
  _Phone(FakeBackend server) : api = server.newApi() {
    session = AuthSession(api: api, store: MemoryTokenStore());
  }

  final ApiClient api;
  late final AuthSession session;
  final user = UserStore();
  late FavouritesSync sync;

  Future<void> start() async {
    await user.load();
    sync = FavouritesSync(api: api, session: session, user: user);
  }

  Future<void> signIn() async {
    await session.login(email: _email, password: _password);
    await settled();
  }

  Future<void> settled() async {
    await pumpEventQueue();
    await sync.idle;
    await pumpEventQueue();
  }
}

void main() {
  late FakeBackend server;
  List<String> serverFavs() => server.favourites[_email] ?? const [];

  setUp(() {
    // One prefs store per test, like one phone's disk: a second _Phone
    // is the same phone started again. Other phones are played by
    // editing the server's list directly.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    server = FakeBackend()..addUser(_email, _password);
  });

  test('signed out: nothing is sent', () async {
    final phone = _Phone(server);
    await phone.start();
    await phone.user.toggleTheme('spider-night');
    await phone.settled();
    expect(server.log, isEmpty);
  });

  test('first sign-in uploads what the phone has', () async {
    final phone = _Phone(server);
    await phone.start();
    await phone.user.toggleTheme('spider-night');
    await phone.user.toggleWallpaper('web-corner');
    await phone.signIn();
    expect(
      serverFavs(),
      unorderedEquals(['theme/spider-night', 'wallpaper/web-corner']),
    );
  });

  test('sign-in merges: server-only items come to the phone', () async {
    server.favourites[_email] = ['theme/neon-night', 'font/orbitron'];
    final phone = _Phone(server);
    await phone.start();
    await phone.user.toggleTheme('spider-night');
    await phone.signIn();
    expect(phone.user.favouriteThemes, ['neon-night', 'spider-night']);
    // Fonts aren't favourites in this app yet, but must not be wiped.
    expect(serverFavs(), contains('font/orbitron'));
    expect(
      serverFavs(),
      containsAll(['theme/neon-night', 'theme/spider-night']),
    );
  });

  test('hearts while signed in go out one by one', () async {
    final phone = _Phone(server);
    await phone.start();
    await phone.signIn();
    server.log.clear();

    await phone.user.toggleTheme('spider-night');
    await phone.settled();
    expect(server.log, ['POST /v1/me/favourites']);
    expect(serverFavs(), ['theme/spider-night']);

    final at = await phone.user.toggleTheme('spider-night');
    await phone.settled();
    expect(server.log.last, 'DELETE /v1/me/favourites/theme/spider-night');
    expect(serverFavs(), isEmpty);

    // The Me tab's Undo.
    await phone.user.restoreTheme('spider-night', at!);
    await phone.settled();
    expect(serverFavs(), ['theme/spider-night']);
  });

  test('an un-heart on another phone removes it here', () async {
    final a = _Phone(server);
    await a.start();
    await a.user.toggleTheme('spider-night');
    await a.user.toggleTheme('neon-night');
    await a.signIn();

    // Phone B (same account) removes Spider Night.
    server.favourites[_email]!.remove('theme/spider-night');

    // A starts again later: a fresh sync.
    final again = _Phone(server);
    await again.start();
    await again.signIn();
    expect(again.user.favouriteThemes, ['neon-night']);
    expect(serverFavs(), ['theme/neon-night']);
  });

  test('a change made offline reaches the server on the next sync', () async {
    final phone = _Phone(server);
    await phone.start();
    await phone.user.toggleTheme('spider-night');
    await phone.user.toggleTheme('neon-night');
    await phone.signIn();

    server.offline = true;
    await phone.user.toggleTheme('spider-night'); // un-heart, fails
    await phone.settled();
    server.offline = false;

    await phone.sync.syncIfNeeded();
    await phone.settled();
    // Not brought back by the merge: base remembers it was agreed on.
    expect(phone.user.favouriteThemes, ['neon-night']);
    expect(serverFavs(), ['theme/neon-night']);
  });

  test('a failed sign-in sync tries again on resume', () async {
    final phone = _Phone(server);
    await phone.start();
    await phone.user.toggleTheme('spider-night');
    await phone.session.login(email: _email, password: _password);
    server.offline = true;
    await phone.settled();
    expect(phone.sync.lastError, isNotNull);
    expect(serverFavs(), isEmpty);

    server.offline = false;
    await phone.sync.syncIfNeeded();
    await phone.settled();
    expect(serverFavs(), ['theme/spider-night']);
  });

  test('sign out keeps the phone\'s favourites', () async {
    final phone = _Phone(server);
    await phone.start();
    await phone.user.toggleTheme('spider-night');
    await phone.signIn();
    await phone.session.logout();
    await phone.settled();
    expect(phone.user.favouriteThemes, ['spider-night']);
  });

  test('deleting the account forgets its sync base', () async {
    final phone = _Phone(server);
    await phone.start();
    await phone.user.toggleTheme('spider-night');
    await phone.signIn();
    final id = phone.session.user!.id;
    final prefs = SharedPreferencesAsync();
    expect(await prefs.getString('fav_sync_base_$id'), isNotNull);

    await AccountService(phone.api, phone.session).deleteAccount(_password);
    await phone.settled();
    expect(await prefs.getString('fav_sync_base_$id'), isNull);
    expect(phone.user.favouriteThemes, ['spider-night']);
  });
}
