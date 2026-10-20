import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_version.dart' as build;
import '../../core/clock.dart';
import 'api_client.dart';
import 'install_id.dart';

/// The events the backend counts for popularity (docs/app-api.md §4).
enum AppEventType {
  themeApplied('theme_applied'),
  themeFavourited('theme_favourited'),
  themeUnfavourited('theme_unfavourited'),
  wallpaperApplied('wallpaper_applied'),
  iconPackApplied('icon_pack_applied'),
  fontApplied('font_applied');

  const AppEventType(this.wire);

  final String wire;
}

class AppEvent {
  const AppEvent(this.type, this.itemId, this.at);

  final String type;
  final String itemId;
  final DateTime at;

  static AppEvent? tryParse(Object? json) {
    if (json is! Map) return null;
    final type = json['type'], id = json['itemId'], at = json['at'];
    final time = at is String ? DateTime.tryParse(at) : null;
    if (type is! String || id is! String || time == null) return null;
    return AppEvent(type, id, time);
  }

  Map<String, Object?> toJson() => {
    'type': type,
    'itemId': itemId,
    'at': at.toUtc().toIso8601String(),
  };
}

enum FlushResult {
  /// Nothing queued.
  empty,

  /// Sent; the server answered 202.
  sent,

  /// Rate limited: waiting for `Retry-After` to pass.
  waiting,

  /// Offline or server trouble; the queue is kept for next time.
  failed,
}

/// Anonymous usage events, queued on the phone and sent in batches
/// (docs/app-api.md §4): on app start and every few hours, never per tap.
///
/// Everything here is best-effort: [record] and [flush] never throw, and
/// nothing waits on them. Events leave the queue only after a `202`.
///
/// The queue lives in shared preferences, read and written whole on every
/// change, so wallp Home (a separate engine) can [record] into it too.
class EventQueue extends ChangeNotifier {
  EventQueue({
    this.client,
    InstallId? installId,
    SharedPreferencesAsync? prefs,
    this.clock = const SystemClock(),
    this.appVersion = build.appVersion,
  }) : _prefs = prefs ?? SharedPreferencesAsync(),
       _installId = installId ?? InstallId(prefs: prefs);

  /// Null in engines that only record (wallp Home); [flush] then does
  /// nothing.
  final ApiClient? client;
  final SharedPreferencesAsync _prefs;
  final InstallId _installId;
  final Clock clock;
  final String appVersion;

  static const _queueKey = 'event_queue_v1';
  static const _retryKey = 'event_retry_after';

  /// Per request (server limit: 422 above this).
  static const batchSize = 100;

  /// Oldest are dropped past this: they'd be too old to count anyway.
  static const maxQueued = 500;

  /// The server drops events older than 7 days; stop a little before.
  static const maxAge = Duration(days: 6, hours: 23);

  /// Batches per [flush], well under the 30 requests/hour limit.
  static const maxBatchesPerFlush = 3;

  Future<void> _lock = Future.value();
  Future<FlushResult>? _flushing;
  int _pending = 0;
  DateTime? _retryAfter;

  /// Events waiting to be sent, as of the last change.
  int get pending => _pending;

  /// Set while rate limited.
  DateTime? get retryAfter => _retryAfter;

  /// Runs [body] after every earlier queue change in this engine.
  Future<T> _serial<T>(Future<T> Function() body) {
    final run = _lock.then((_) => body());
    _lock = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Adds one event. Item IDs over 100 characters are skipped (the server
  /// would drop them).
  Future<void> record(AppEventType type, String itemId) async {
    if (itemId.isEmpty || itemId.length > 100) return;
    try {
      await _serial(() async {
        final queue = await _read();
        queue.add(AppEvent(type.wire, itemId, clock.now()));
        if (queue.length > maxQueued) {
          queue.removeRange(0, queue.length - maxQueued);
        }
        await _write(queue);
      });
    } on Object catch (e) {
      debugPrint('Event not recorded: $e');
    }
  }

  /// Reads the queue's size, for Developer settings.
  Future<void> load() async {
    try {
      await _serial(() async {
        _pending = (await _read()).length;
        final retry = await _prefs.getString(_retryKey);
        _retryAfter = retry == null ? null : DateTime.tryParse(retry);
      });
      notifyListeners();
    } on Object catch (e) {
      debugPrint('Event queue unreadable: $e');
    }
  }

  /// Sends what's queued. Only one flush runs at a time.
  Future<FlushResult> flush() =>
      _flushing ??= _flush().whenComplete(() => _flushing = null);

  Future<FlushResult> _flush() async {
    final api = client;
    if (api == null) return FlushResult.failed;
    try {
      final retry = await _prefs.getString(_retryKey);
      final until = retry == null ? null : DateTime.tryParse(retry);
      if (until != null && clock.now().isBefore(until)) {
        _retryAfter = until;
        return FlushResult.waiting;
      }
      _retryAfter = null;

      var result = FlushResult.empty;
      for (var i = 0; i < maxBatchesPerFlush; i++) {
        final batch = await _serial(() async {
          final queue = await _read();
          final fresh = _withinWindow(queue);
          if (fresh.length != queue.length) await _write(fresh);
          return fresh.take(batchSize).toList();
        });
        if (batch.isEmpty) break;
        final sent = await _send(api, batch);
        if (sent != FlushResult.sent) return sent;
        result = FlushResult.sent;
      }
      return result;
    } on Object catch (e) {
      debugPrint('Event flush failed: $e');
      return FlushResult.failed;
    } finally {
      notifyListeners();
    }
  }

  Future<FlushResult> _send(ApiClient api, List<AppEvent> batch) async {
    try {
      await api.post(
        'events',
        body: {
          'installId': await _installId.get(),
          'appVersion': appVersion,
          'events': [for (final e in batch) e.toJson()],
        },
      );
    } on ApiException catch (e) {
      if (e.status == 429) {
        final until = clock.now().add(e.retryAfter ?? const Duration(hours: 1));
        _retryAfter = until;
        await _prefs.setString(_retryKey, until.toIso8601String());
        return FlushResult.waiting;
      }
      if (e.isTransient || e.status == 401) {
        debugPrint('Events kept for later: $e');
        return FlushResult.failed;
      }
      // 400, 413, 422: this batch will never be accepted. Drop it, or it
      // blocks every later event.
      debugPrint('Events dropped: $e');
    }
    await _serial(() async => _write(_removeSent(await _read(), batch)));
    await _prefs.remove(_retryKey);
    return FlushResult.sent;
  }

  List<AppEvent> _withinWindow(List<AppEvent> queue) {
    final now = clock.now();
    final oldest = now.subtract(maxAge);
    final newest = now.add(const Duration(minutes: 5));
    return [
      for (final e in queue)
        if (e.at.isAfter(oldest) && e.at.isBefore(newest)) e,
    ];
  }

  /// [queue] without one copy of each event in [sent]. Events recorded
  /// meanwhile (or by wallp Home) stay.
  static List<AppEvent> _removeSent(List<AppEvent> queue, List<AppEvent> sent) {
    final keys = [for (final e in sent) jsonEncode(e.toJson())];
    return [
      for (final e in queue)
        if (!keys.remove(jsonEncode(e.toJson()))) e,
    ];
  }

  Future<List<AppEvent>> _read() async {
    final raw = await _prefs.getString(_queueKey);
    if (raw == null) return [];
    try {
      return [for (final e in jsonDecode(raw) as List) ?AppEvent.tryParse(e)];
    } on Object catch (e) {
      debugPrint('Ignoring damaged event queue: $e');
      return [];
    }
  }

  Future<void> _write(List<AppEvent> queue) async {
    _pending = queue.length;
    if (queue.isEmpty) {
      await _prefs.remove(_queueKey);
    } else {
      await _prefs.setString(
        _queueKey,
        jsonEncode([for (final e in queue) e.toJson()]),
      );
    }
  }
}
