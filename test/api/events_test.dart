import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wallp/core/clock.dart';
import 'package:wallp/data/api/auth_session.dart';
import 'package:wallp/data/api/event_queue.dart';
import 'package:wallp/data/api/install_id.dart';
import 'package:wallp/data/api/install_link.dart';
import 'package:wallp/data/api/token_store.dart';
import 'package:wallp/store/state/user_store.dart';

import 'fake_backend.dart';

class _Clock implements Clock {
  DateTime t = DateTime.utc(2026, 10, 18, 9);

  @override
  DateTime now() => t;
}

void main() {
  late FakeBackend server;
  late _Clock clock;
  late EventQueue events;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    server = FakeBackend();
    clock = _Clock();
    events = EventQueue(api: server.api, clock: clock);
  });

  group('InstallId', () {
    test('a v4 UUID, made once and kept', () async {
      final id = await InstallId().get();
      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(await InstallId().get(), id);
    });

    test('random each install', () {
      final r = Random(1);
      expect(InstallId.uuidV4(r), isNot(InstallId.uuidV4(r)));
    });
  });

  group('EventQueue', () {
    test('sends with the install id, no token, then empties', () async {
      await events.add(AppEventType.themeApplied, 'spider-night');
      await events.add(AppEventType.wallpaperApplied, 'web-corner');
      expect(await events.flush(), 2);
      final batch = server.eventBatches.single;
      expect(batch.first, {
        'type': 'theme_applied',
        'itemId': 'spider-night',
        'at': '2026-10-18T09:00:00.000Z',
      });
      expect(await events.pending(), isEmpty);
    });

    test('repeats while waiting are dropped', () async {
      await events.add(AppEventType.themeApplied, 'spider-night');
      await events.add(AppEventType.themeApplied, 'spider-night');
      await events.add(AppEventType.themeFavourited, 'spider-night');
      expect(await events.pending(), hasLength(2));
    });

    test('kept when offline or the server fails', () async {
      await events.add(AppEventType.themeApplied, 'spider-night');
      server.offline = true;
      expect(await events.flush(), 0);
      expect(await events.pending(), hasLength(1));
      server.offline = false;
      expect(await events.flush(), 1);
    });

    test('429 waits for Retry-After, across restarts', () async {
      await events.add(AppEventType.themeApplied, 'spider-night');
      server.rateLimitFor = const Duration(minutes: 20);
      expect(await events.flush(), 0);
      server.rateLimitFor = null;

      final again = EventQueue(api: server.api, clock: clock);
      clock.t = clock.t.add(const Duration(minutes: 10));
      expect(await again.flush(), 0);
      expect(server.eventBatches, isEmpty);

      clock.t = clock.t.add(const Duration(minutes: 11));
      expect(await again.flush(), 1);
    });

    test('batches of 100', () async {
      for (var i = 0; i < 250; i++) {
        await events.add(AppEventType.themeApplied, 'theme-$i');
      }
      expect(await events.flush(), 250);
      expect(server.eventBatches.map((b) => b.length), [100, 100, 50]);
    });

    test('older than 7 days is dropped before sending', () async {
      await events.add(AppEventType.themeApplied, 'old-one');
      clock.t = clock.t.add(const Duration(days: 8));
      await events.add(AppEventType.themeApplied, 'new-one');
      expect(await events.flush(), 1);
      expect(server.eventBatches.single.single['itemId'], 'new-one');
    });

    test('the queue stays bounded', () async {
      for (var i = 0; i < EventQueue.maxQueued + 20; i++) {
        await events.add(AppEventType.themeApplied, 'theme-$i');
      }
      final waiting = await events.pending();
      expect(waiting, hasLength(EventQueue.maxQueued));
      expect(waiting.first.itemId, 'theme-20');
    });

    test(
      'a batch the server refuses is dropped, not retried forever',
      () async {
        // An install id the server rejects.
        final bad = EventQueue(
          api: server.api,
          clock: clock,
          installId: _FixedId('not-a-uuid'),
        );
        await bad.add(AppEventType.themeApplied, 'spider-night');
        await bad.flush();
        expect(await bad.pending(), isEmpty);
      },
    );

    test('recording only (wallp Home) needs no server', () async {
      final home = EventQueue(clock: clock);
      await home.add(AppEventType.themeApplied, 'spider-night');
      expect(await home.flush(), 0);
      // The store's queue, same phone, sends it.
      expect(await events.flush(), 1);
    });

    test('hearts are counted through UserStore', () async {
      final user = UserStore();
      await user.load();
      user.onThemeFavourite = (id, {required added}) => events.add(
        added ? AppEventType.themeFavourited : AppEventType.themeUnfavourited,
        id,
      );
      await user.toggleTheme('spider-night');
      final at = await user.toggleTheme('spider-night');
      await user.restoreTheme('spider-night', at!);
      // Sync merges don't count.
      await user.replaceFavourites(themes: ['neon-night'], wallpapers: []);
      await pumpEventQueue();
      expect(
        [for (final e in await events.pending()) '${e.type.wire} ${e.itemId}'],
        ['theme_favourited spider-night', 'theme_unfavourited spider-night'],
      );
    });
  });

  group('InstallLink', () {
    test(
      'links once after sign-in; another account\'s install is fine',
      () async {
        server
          ..addUser('ana@example.com', 'correct horse battery')
          ..addUser('bo@example.com', 'correct horse battery');
        final session = AuthSession(api: server.api, store: MemoryTokenStore());
        final installId = InstallId();
        final link = InstallLink(
          api: server.api,
          session: session,
          installId: installId,
        );
        await session.login(
          email: 'ana@example.com',
          password: 'correct horse battery',
        );
        await pumpEventQueue();
        await link.idle;
        final id = await installId.get();
        expect(server.installs[id], 'ana@example.com');

        // Again for the same account: no second call.
        final calls = server.log
            .where((l) => l.endsWith('/me/installs'))
            .length;
        await session.updateUser(session.user!);
        await pumpEventQueue();
        await link.idle;
        expect(
          server.log.where((l) => l.endsWith('/me/installs')),
          hasLength(calls),
        );

        // Bo on the same phone: 409, accepted quietly.
        await session.logout();
        await session.login(
          email: 'bo@example.com',
          password: 'correct horse battery',
        );
        await pumpEventQueue();
        await link.idle;
        expect(server.installs[id], 'ana@example.com');
        expect(
          await SharedPreferencesAsync().getString('install_linked_account'),
          session.user!.id,
        );
      },
    );
  });
}

class _FixedId implements InstallId {
  _FixedId(this.value);

  final String value;

  @override
  Future<String> get() async => value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
