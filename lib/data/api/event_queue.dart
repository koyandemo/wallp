import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_version.dart' as build;
import '../../core/clock.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'install_id.dart';

/// What the server counts for popularity (docs/app-client.md §4).
enum AppEventType {
  themeApplied('theme_applied'),
  themeFavourited('theme_favourited'),
  themeUnfavourited('theme_unfavourited'),
  wallpaperApplied('wallpaper_applied'),
  iconPackApplied('icon_pack_applied'),
  fontApplied('font_applied');

  const AppEventType(this.wire);

  final String wire;

  static final _byWire = {for (final t in values) t.wire: t};
}

class AppEvent {
  const AppEvent(this.type, this.itemId, this.at);

  final AppEventType type;
  final String itemId;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'type': type.wire,
    'itemId': itemId,
    'at': at.toUtc().toIso8601String(),
  };

  static AppEvent? fromJson(Object? json) {
    if (json case {
      'type': final String t,
      'itemId': final String id,
      'at': final String at,
    }) {
      final type = AppEventType._byWire[t];
      final when = DateTime.tryParse(at);
      if (type != null && when != null) return AppEvent(type, id, when);
    }
    return null;
  }
}

/// Anonymous usage events, queued on the phone and sent in batches
/// (docs/app-client.md §4). Optional: nothing waits for it, and a full,
/// offline or rate-limited queue just waits.
///
/// * [add] only writes to shared prefs, so wallp Home's engine can record
///   too (it finishes pending applies). Repeats of the same (type, item)
///   while one is waiting are dropped, as the server would.
/// * [flush] sends up to 100 at a time, with no token. Events leave the
///   queue only after `202`. `429` waits for `Retry-After`; a batch the
///   server refuses outright (`413`, `422`) is dropped, since it never
///   will succeed.
/// * The store sends on start, every [every] while open, and when the app
///   goes to the background (at most once per [minGap]).
class EventQueue {
  EventQueue({
    this.api,
    InstallId? installId,
    SharedPreferencesAsync? prefs,
    this.clock = const SystemClock(),
    this.appVersion = build.appVersion,
    this.every = const Duration(hours: 3),
    this.minGap = const Duration(minutes: 5),
  }) : _prefs = prefs ?? SharedPreferencesAsync(),
       installId = installId ?? InstallId(prefs: prefs);

  /// Null in engines that only record (wallp Home).
  final ApiClient? api;

  /// This install's id, shared with InstallLink.
  final InstallId installId;
  final SharedPreferencesAsync _prefs;

  /// The real time, never Developer settings' pretend date: the server
  /// drops events outside the last 7 days.
  final Clock clock;
  final String appVersion;
  final Duration every;
  final Duration minGap;

  static const maxQueued = 500;
  static const maxBatch = 100;
  static const maxAge = Duration(days: 7);
  static const maxAhead = Duration(minutes: 5);

  static const _queueKey = 'event_queue_v1';
  static const _retryKey = 'event_retry_after';

  /// Reads and writes of the queue, one at a time.
  Future<void> _lock = Future.value();
  Future<int>? _flushing;
  DateTime? _lastFlush;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;

  /// Starts sending: once now, then on a timer and when the app hides.
  void start({bool watchApp = true}) {
    unawaited(flush());
    _timer ??= Timer.periodic(every, (_) => flush());
    if (watchApp) {
      _lifecycle ??= AppLifecycleListener(
        onHide: () {
          final last = _lastFlush;
          if (last == null || clock.now().difference(last) >= minGap) {
            unawaited(flush());
          }
        },
      );
    }
  }

  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
  }

  /// Queues one event. Never throws.
  Future<void> add(AppEventType type, String itemId) => _locked(() async {
    if (itemId.isEmpty || itemId.length > 100) return;
    final queue = await _read();
    if (queue.any((e) => e.type == type && e.itemId == itemId)) return;
    queue.add(AppEvent(type, itemId, clock.now().toUtc()));
    if (queue.length > maxQueued) {
      queue.removeRange(0, queue.length - maxQueued);
    }
    await _write(queue);
  });

  /// What's waiting. For Developer settings and tests.
  Future<List<AppEvent>> pending() => _locked(_read);

  /// Sends what's waiting; returns how many the server took. Runs one at
  /// a time; a second call waits for the first.
  Future<int> flush() =>
      _flushing ??= _flush().whenComplete(() => _flushing = null);

  Future<int> _flush() async {
    final api = this.api;
    if (api == null) return 0;
    _lastFlush = clock.now();
    try {
      final until = DateTime.tryParse(await _prefs.getString(_retryKey) ?? '');
      if (until != null && clock.now().isBefore(until)) return 0;
    } on Object {
      // Unreadable: send anyway.
    }

    var sent = 0;
    while (true) {
      final batch = await _locked(() async {
        final now = clock.now();
        final all = await _read();
        final fresh = [
          for (final e in all)
            if (now.difference(e.at) < maxAge - const Duration(minutes: 10) &&
                e.at.difference(now) < maxAhead)
              e,
        ];
        if (fresh.length != all.length) await _write(fresh);
        return fresh.take(maxBatch).toList();
      });
      if (batch.isEmpty) return sent;

      try {
        await api.post(
          'events',
          body: {
            'installId': await installId.get(),
            'appVersion': appVersion,
            'events': [for (final e in batch) e.toJson()],
          },
        );
      } on ApiException catch (e) {
        if (e.code == ApiErrorCode.rateLimited) {
          final wait = e.retryAfter ?? const Duration(hours: 1);
          await _prefs.setString(
            _retryKey,
            clock.now().add(wait).toUtc().toIso8601String(),
          );
          return sent;
        }
        if (e.isTransient) return sent;
        // 413, 422, ...: this batch can never go through.
        debugPrint('Events refused, dropping ${batch.length}: $e');
      }
      await _locked(() async {
        final sentKeys = {for (final e in batch) _key(e)};
        await _write([
          for (final e in await _read())
            if (!sentKeys.contains(_key(e))) e,
        ]);
      });
      sent += batch.length;
    }
  }

  static String _key(AppEvent e) =>
      '${e.type.wire}/${e.itemId}/${e.at.microsecondsSinceEpoch}';

  Future<T> _locked<T>(Future<T> Function() run) {
    final next = _lock.then((_) => run());
    _lock = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<List<AppEvent>> _read() async {
    try {
      final raw = await _prefs.getString(_queueKey);
      if (raw == null) return [];
      return [for (final e in jsonDecode(raw) as List) ?AppEvent.fromJson(e)];
    } on Object catch (e) {
      debugPrint('Ignoring damaged event queue: $e');
      return [];
    }
  }

  Future<void> _write(List<AppEvent> queue) async {
    try {
      await _prefs.setString(
        _queueKey,
        jsonEncode([for (final e in queue) e.toJson()]),
      );
    } on Object catch (e) {
      debugPrint('Saving events failed: $e');
    }
  }
}
