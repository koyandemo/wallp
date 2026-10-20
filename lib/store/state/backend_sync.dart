import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_version.dart';
import '../../data/account/account_repository.dart';
import '../../data/api/event_queue.dart';
import '../../data/api/install_id.dart';
import '../../data/catalog/catalog_repository.dart';
import 'favourites_sync.dart';
import 'user_store.dart';

/// The app's start-up and background talk with the backend
/// (docs/app-api.md §6). Nothing here blocks the UI or throws.
///
/// 1. The catalog shows from cache at once (CatalogRepository.start).
/// 2. The install ID exists.
/// 3. A saved login refreshes; on `401` the app carries on signed out.
///    Then favourites sync and the install is linked to the account.
/// 4. Queued events go out. Theme hearts are counted as events too.
/// 5. While the app is open: the manifest every 5 minutes, events every
///    few hours, and both again when the app comes back after a while.
class BackendSync {
  BackendSync({
    required this.catalog,
    required this.events,
    required this.account,
    required this.favourites,
    required this.user,
    InstallId? installId,
    SharedPreferencesAsync? prefs,
  }) : _prefs = prefs ?? SharedPreferencesAsync(),
       _installId = installId ?? InstallId(prefs: prefs);

  final CatalogRepository catalog;
  final EventQueue events;
  final AccountRepository account;
  final FavouritesSync favourites;
  final UserStore user;
  final InstallId _installId;
  final SharedPreferencesAsync _prefs;

  static const manifestEvery = Duration(minutes: 5);
  static const eventsEvery = Duration(hours: 3);
  static const _linkedKey = 'install_linked_user';

  Timer? _manifestTimer;
  Timer? _eventsTimer;
  AppLifecycleListener? _lifecycle;
  StreamSubscription<AccountChange>? _accountChanges;
  StreamSubscription<FavouriteChange>? _hearts;
  DateTime? _pausedAt;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _lifecycle = AppLifecycleListener(onResume: _resumed, onPause: _paused);
    _accountChanges = account.changes.listen((c) {
      if (c is SignedIn) unawaited(_linkInstall());
    });
    _hearts = user.favouriteChanges.listen((c) {
      if (c.kind != FavouriteKind.theme) return;
      unawaited(
        events.record(
          c.added
              ? AppEventType.themeFavourited
              : AppEventType.themeUnfavourited,
          c.id,
        ),
      );
    });
    favourites.start();
    _schedule();
    try {
      await _installId.get();
      await events.load();
      // restore() signals SignedIn, which syncs favourites and links.
      await account.restore();
    } on Object catch (e) {
      debugPrint('Backend start-up: $e');
    }
    unawaited(events.flush());
  }

  void _schedule() {
    _manifestTimer?.cancel();
    _eventsTimer?.cancel();
    _manifestTimer = Timer.periodic(manifestEvery, (_) => catalog.refresh());
    _eventsTimer = Timer.periodic(eventsEvery, (_) => events.flush());
  }

  void _paused() {
    _pausedAt = DateTime.now();
    _manifestTimer?.cancel();
    _eventsTimer?.cancel();
  }

  void _resumed() {
    final away = _pausedAt == null
        ? Duration.zero
        : DateTime.now().difference(_pausedAt!);
    _pausedAt = null;
    _schedule();
    if (away >= manifestEvery) {
      unawaited(catalog.refresh());
      unawaited(favourites.sync());
    }
    if (away >= eventsEvery) unawaited(events.flush());
  }

  /// `POST /v1/me/installs`, once per account on this phone.
  Future<void> _linkInstall() async {
    final userId = account.user?.id;
    if (userId == null) return;
    try {
      if (await _prefs.getString(_linkedKey) == userId) return;
      await account.linkInstall(await _installId.get(), appVersion);
      await _prefs.setString(_linkedKey, userId);
    } on Object catch (e) {
      debugPrint('Install not linked yet: $e');
    }
  }

  void dispose() {
    _manifestTimer?.cancel();
    _eventsTimer?.cancel();
    _lifecycle?.dispose();
    _accountChanges?.cancel();
    _hearts?.cancel();
  }
}
