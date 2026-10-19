import 'dart:async';

import 'package:flutter/widgets.dart';

import 'catalog_repository.dart';

/// Checks for a new catalog while the store is on screen
/// (docs/app-client.md §2 step 2, §6 step 6): every [every], which is
/// also how long the server lets the manifest be cached.
///
/// Stops while the app is hidden; on coming back it checks at once if the
/// last check is older than [every]. The first check at launch is
/// [CatalogRepository.start]'s, not this.
class CatalogPoller {
  CatalogPoller(this.repo, {this.every = const Duration(minutes: 5)});

  final CatalogRepository repo;
  final Duration every;

  Timer? _timer;
  AppLifecycleListener? _lifecycle;

  bool get isRunning => _timer != null;

  void start({bool watchApp = true}) {
    _startTimer();
    if (watchApp) {
      _lifecycle ??= AppLifecycleListener(onShow: _onShow, onHide: _stop);
    }
  }

  void dispose() {
    _stop();
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  void _onShow() {
    final last = repo.lastCheckedAt;
    if (last != null && repo.clock.now().difference(last) >= every) {
      unawaited(repo.refresh());
    }
    _startTimer();
  }

  void _startTimer() =>
      _timer ??= Timer.periodic(every, (_) => unawaited(repo.refresh()));

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }
}
