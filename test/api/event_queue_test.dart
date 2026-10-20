import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wallp/core/clock.dart';
import 'package:wallp/data/api/event_queue.dart';
import 'package:wallp/data/api/install_id.dart';

import 'fake_backend.dart';

class _Clock implements Clock {
  DateTime time = DateTime.utc(2026, 10, 20, 9);

  @override
  DateTime now() => time;
}

void main() {
  late FakeBackend server;
  late _Clock clock;
  late EventQueue queue;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    server = FakeBackend();
    clock = _Clock();
    queue = EventQueue(client: server.client(), clock: clock);
  });

  test('install ID is a UUID v4 and stays the same', () async {
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

  test('sends queued events and empties the queue on 202', () async {
    await queue.record(AppEventType.themeApplied, 'spider-night');
    await queue.record(AppEventType.wallpaperApplied, 'moon-1');
    expect(queue.pending, 2);

    expect(await queue.flush(), FlushResult.sent);
    expect(server.events, [
      {
        'type': 'theme_applied',
        'itemId': 'spider-night',
        'at': '2026-10-20T09:00:00.000Z',
      },
      {
        'type': 'wallpaper_applied',
        'itemId': 'moon-1',
        'at': '2026-10-20T09:00:00.000Z',
      },
    ]);
    expect(queue.pending, 0);
    expect(await queue.flush(), FlushResult.empty);
  });

  test(
    'a recording engine (wallp Home) queues for the store to send',
    () async {
      await EventQueue(clock: clock).record(AppEventType.themeApplied, 'a');
      expect(await queue.flush(), FlushResult.sent);
      expect(server.events.single['itemId'], 'a');
    },
  );

  test('offline or 5xx keeps the queue', () async {
    await queue.record(AppEventType.fontApplied, 'inter');
    server.offline = true;
    expect(await queue.flush(), FlushResult.failed);
    server
      ..offline = false
      ..eventsStatus = 503;
    expect(await queue.flush(), FlushResult.failed);
    expect(queue.pending, 1);
    server.eventsStatus = 202;
    expect(await queue.flush(), FlushResult.sent);
    expect(server.events, hasLength(1));
  });

  test('429 waits for Retry-After and keeps the queue', () async {
    await queue.record(AppEventType.iconPackApplied, 'moonlit');
    server
      ..eventsStatus = 429
      ..eventsRetryAfter = 600;
    expect(await queue.flush(), FlushResult.waiting);
    server.eventsStatus = 202;
    final before = server.count('POST /v1/events');
    expect(await queue.flush(), FlushResult.waiting);
    expect(server.count('POST /v1/events'), before, reason: 'no request');

    clock.time = clock.time.add(const Duration(minutes: 11));
    expect(await queue.flush(), FlushResult.sent);
    expect(queue.pending, 0);
  });

  test('drops events older than 7 days before sending', () async {
    await queue.record(AppEventType.themeApplied, 'old');
    clock.time = clock.time.add(const Duration(days: 8));
    await queue.record(AppEventType.themeApplied, 'new');
    await queue.flush();
    expect([for (final e in server.events) e['itemId']], ['new']);
  });

  test('sends at most 100 per request', () async {
    for (var i = 0; i < 150; i++) {
      await queue.record(AppEventType.themeApplied, 't$i');
    }
    await queue.flush();
    expect(server.count('POST /v1/events'), 2);
    expect(server.events, hasLength(150));
  });
}
