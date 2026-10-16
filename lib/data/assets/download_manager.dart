import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../catalog/catalog.dart';
import '../catalog/catalog_source.dart';
import 'asset_cache.dart';

enum DownloadState { downloading, done, failed, cancelled }

/// One "get these files" job, e.g. everything Cozy Cabin needs. The Apply
/// sheet's progress bar listens to it.
class DownloadTask extends ChangeNotifier {
  DownloadTask._(this.label, this.files, this.totalBytes);

  /// What's downloading, for the sheet: "Cozy Cabin".
  final String label;

  /// Only the files that weren't on the phone yet.
  final List<AssetRef> files;
  final int totalBytes;

  DownloadState _state = DownloadState.downloading;
  int _receivedBytes = 0;
  int _doneFiles = 0;
  Object? _error;
  bool _cancelRequested = false;
  final _done = Completer<void>();

  DownloadState get state => _state;
  int get receivedBytes => _receivedBytes;
  int get doneFiles => _doneFiles;

  /// 0–1 for the progress bar.
  double get progress => totalBytes == 0 ? 1 : _receivedBytes / totalBytes;

  /// Why it failed: a [CatalogFetchException] or [AssetCheckException].
  Object? get error => _error;

  bool get isActive => _state == DownloadState.downloading;

  /// Completes when every file is on disk; throws [DownloadFailedException]
  /// or [DownloadCancelledException] otherwise.
  Future<void> get done => _done.future;

  /// Stops after the chunks in flight. Files already finished stay cached,
  /// so trying again continues where this stopped.
  void cancel() {
    if (!isActive) return;
    _cancelRequested = true;
  }

  void _received(int bytes) {
    _receivedBytes += bytes;
    notifyListeners();
  }

  void _finish(DownloadState state, [Object? error]) {
    _state = state;
    _error = error;
    notifyListeners();
    switch (state) {
      case DownloadState.done:
        _done.complete();
      case DownloadState.cancelled:
        _done.completeError(DownloadCancelledException(label));
      case DownloadState.failed:
        _done.completeError(DownloadFailedException(label, error!));
      case DownloadState.downloading:
        break;
    }
    // Nobody awaiting `done` is fine: the manager reports it too.
    _done.future.ignore();
  }
}

/// Downloads catalog files into the [AssetCache] (docs/theme-api.md §7.2):
/// several at a time, retrying brief network problems, checking every file,
/// and reporting progress. Fetches through the same [CatalogSource] as the
/// catalog, so the mock network's Slow / Offline / Flaky settings apply.
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this._source,
    required this.cache,
    this.parallel = 3,
    this.retryDelays = const [
      Duration(milliseconds: 600),
      Duration(seconds: 2),
    ],
  });

  final CatalogSource _source;
  final AssetCache cache;

  /// Files downloading at once.
  final int parallel;

  /// Waits before each retry of a brief failure (offline, timeout, 5xx).
  final List<Duration> retryDelays;

  DownloadTask? _current;

  /// The task the Apply sheet shows, or null.
  DownloadTask? get current => _current;

  /// Makes sure every file in [refs] is on disk, downloading what's
  /// missing. Throws [DownloadFailedException] or
  /// [DownloadCancelledException]; nothing is half done either way.
  ///
  /// A second call while the same files download joins that task.
  Future<void> ensure(Iterable<AssetRef> refs, {required String label}) async {
    final task = await start(refs, label: label);
    await task.done;
  }

  /// Starts (or joins) the download and returns its task straight away.
  Future<DownloadTask> start(
    Iterable<AssetRef> refs, {
    required String label,
  }) async {
    final wanted = refs.toSet();
    final missing = await cache.missing(wanted);
    final task = DownloadTask._(
      label,
      missing,
      missing.fold<int>(0, (s, r) => s + r.bytes),
    );
    if (missing.isEmpty) {
      // Everything's on the phone: nothing to show.
      await cache.touch(wanted);
      task._finish(DownloadState.done);
      return task;
    }
    final running = _current;
    if (running != null &&
        running.isActive &&
        running.files.toSet().containsAll(missing)) {
      return running;
    }
    _current = task;
    notifyListeners();
    unawaited(_run(task, wanted));
    return task;
  }

  Future<void> _run(DownloadTask task, Set<AssetRef> wanted) async {
    final queue = [...task.files];
    final fetched = <String>{};
    Object? failure;

    Future<void> worker() async {
      while (queue.isNotEmpty && failure == null && !task._cancelRequested) {
        final ref = queue.removeAt(0);
        try {
          await _fetchWithRetry(task, ref);
          fetched.add(ref.sha256);
          task._doneFiles++;
        } on _Cancelled {
          return;
        } on Object catch (e) {
          failure ??= e;
        }
      }
    }

    await Future.wait([for (var i = 0; i < parallel; i++) worker()]);

    if (task._cancelRequested) {
      task._finish(DownloadState.cancelled);
    } else if (failure != null) {
      task._finish(DownloadState.failed, failure);
    } else {
      await cache.touch(wanted);
      task._finish(DownloadState.done);
    }
    // Over the limit now? Never evict what this task just fetched.
    unawaited(
      cache.evict(keep: fetched).catchError((Object e) {
        // Clean-up is best effort; the download itself is done.
        debugPrint('Asset cache clean-up failed: $e');
      }),
    );
    notifyListeners();
  }

  Future<void> _fetchWithRetry(DownloadTask task, AssetRef ref) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await _fetch(task, ref);
        return;
      } on CatalogFetchException catch (e) {
        if (!e.isTransient || attempt >= retryDelays.length) rethrow;
        await Future<void>.delayed(retryDelays[attempt]);
        if (task._cancelRequested) throw const _Cancelled();
      }
    }
  }

  Future<void> _fetch(DownloadTask task, AssetRef ref) async {
    final file = await cache.incoming(ref);
    try {
      await for (final chunk in _source.open(ref.url)) {
        if (task._cancelRequested) throw const _Cancelled();
        file.add(chunk);
        task._received(chunk.length);
      }
      await file.commit();
    } on Object {
      // Give back this attempt's progress, so a retry doesn't overcount.
      task._received(-file.received);
      await file.discard();
      rethrow;
    }
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class DownloadFailedException implements Exception {
  const DownloadFailedException(this.label, this.cause);

  final String label;

  /// A [CatalogFetchException] or [AssetCheckException].
  final Object cause;

  bool get isOffline =>
      cause is CatalogFetchException &&
      (cause as CatalogFetchException).failure == FetchFailure.offline;

  /// What the Apply sheet says.
  String get message => isOffline
      ? "Couldn't download $label. Check your connection."
      : "Couldn't download $label. Try again.";

  @override
  String toString() => 'DownloadFailedException: $label: $cause';
}

class DownloadCancelledException implements Exception {
  const DownloadCancelledException(this.label);

  final String label;

  @override
  String toString() => 'DownloadCancelledException: $label';
}
