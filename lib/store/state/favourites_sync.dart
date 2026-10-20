import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/account/account_models.dart';
import '../../data/account/account_repository.dart';
import '../../data/api/api_client.dart';
import 'user_store.dart';

/// Keeps the phone's theme and wallpaper favourites and the account's in
/// step (docs/app-api.md §3, Favourites).
///
/// - First sync after signing in to an account on this phone: merge. The
///   account's list and the phone's are combined, uploaded with `PUT`, and
///   shown, so nothing hearted on either side is lost.
/// - Each heart or un-heart while signed in: queued, then sent with `POST`
///   or `DELETE`. The queue is saved, so changes made offline go out later.
/// - Later syncs (app start, coming back to the app): the account's list,
///   plus anything still queued, replaces the phone's. That way a removal
///   on another phone shows here too.
///
/// Font and icon-pack favourites on the account are kept as they are.
/// Signing out leaves the phone's favourites alone.
class FavouritesSync extends ChangeNotifier {
  FavouritesSync({
    required this.account,
    required this.user,
    SharedPreferencesAsync? prefs,
  }) : _prefs = prefs ?? SharedPreferencesAsync();

  final AccountRepository account;
  final UserStore user;
  final SharedPreferencesAsync _prefs;

  static const _pendingKey = 'fav_sync_pending_v1';
  static const _mergedKey = 'fav_sync_merged_user';

  final _subscriptions = <StreamSubscription<Object?>>[];
  Future<void> _lock = Future.value();
  Future<void>? _syncing;

  /// Bumped on every local heart, to spot changes made mid-sync.
  int _generation = 0;

  DateTime? _lastSyncedAt;
  Object? _lastError;

  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// Why the last sync failed, or null.
  Object? get lastError => _lastError;
  bool get isSyncing => _syncing != null;

  /// Starts listening to hearts and sign-ins.
  void start() {
    if (_subscriptions.isNotEmpty) return;
    _subscriptions
      ..add(user.favouriteChanges.listen(_onFavourite))
      ..add(account.changes.listen(_onAccount));
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  Future<T> _serial<T>(Future<T> Function() body) {
    final run = _lock.then((_) => body());
    _lock = run.then((_) {}, onError: (_) {});
    return run;
  }

  void _onAccount(AccountChange change) {
    switch (change) {
      case SignedIn():
        unawaited(sync());
      case SignedOut():
        unawaited(
          _serial(() async {
            await _prefs.remove(_pendingKey);
            await _prefs.remove(_mergedKey);
          }),
        );
    }
  }

  void _onFavourite(FavouriteChange change) {
    _generation++;
    if (!account.isSignedIn) return;
    final item = FavouriteItem(_typeOf(change.kind), change.id);
    unawaited(
      _serial(() async {
        final ops = await _readOps();
        ops
          ..removeWhere((o) => o.item.key == item.key)
          ..add(_Op(item, add: change.added));
        await _writeOps(ops);
      }).then((_) => _push()),
    );
  }

  static String _typeOf(FavouriteKind kind) => switch (kind) {
    FavouriteKind.theme => FavouriteType.theme,
    FavouriteKind.wallpaper => FavouriteType.wallpaper,
  };

  /// Sends queued changes in order; stops at the first one that can't go
  /// out yet. Never throws.
  Future<void> _push() => _serial(() async {
    final ops = await _readOps();
    while (ops.isNotEmpty && account.isSignedIn) {
      final op = ops.first;
      try {
        if (op.add) {
          await account.addFavourite(op.item);
        } else {
          await account.removeFavourite(op.item);
        }
      } on ApiException catch (e) {
        if (e.isTransient || e.status == 401 || e.status == 429) {
          debugPrint('Favourite change kept for later: $e');
          break;
        }
        // 422 (an ID the server refuses): it never will accept it.
        debugPrint('Favourite change dropped: $e');
      } on Object catch (e) {
        debugPrint('Favourite change kept for later: $e');
        break;
      }
      ops.removeAt(0);
      await _writeOps(ops);
    }
  });

  /// One full sync. Only one runs at a time; never throws.
  Future<void> sync() => _syncing ??= _sync().whenComplete(() {
    _syncing = null;
    notifyListeners();
  });

  Future<void> _sync() async {
    if (!account.isSignedIn) return;
    notifyListeners();
    try {
      await user.ready;
      await _push();
      final userId = account.user?.id;
      if (userId == null) return;
      final generation = _generation;
      final server = await account.favourites();
      final merged = await _prefs.getString(_mergedKey) == userId;

      final List<String> themes, wallpapers;
      if (merged) {
        final ops = await _serial(_readOps);
        themes = _applyOps(
          _ids(server, FavouriteType.theme),
          ops,
          FavouriteType.theme,
        );
        wallpapers = _applyOps(
          _ids(server, FavouriteType.wallpaper),
          ops,
          FavouriteType.wallpaper,
        );
      } else {
        themes = _union(
          user.favouriteThemes,
          _ids(server, FavouriteType.theme),
        );
        wallpapers = _union(
          user.favouriteWallpapers,
          _ids(server, FavouriteType.wallpaper),
        );
        await account.replaceFavourites([
          for (final id in themes) FavouriteItem(FavouriteType.theme, id),
          for (final id in wallpapers)
            FavouriteItem(FavouriteType.wallpaper, id),
          for (final i in server)
            if (i.itemType != FavouriteType.theme &&
                i.itemType != FavouriteType.wallpaper)
              i,
        ]);
        await _prefs.setString(_mergedKey, userId);
      }

      if (generation != _generation) {
        // Hearts changed while we were away: they are queued and sent;
        // the next sync shows the server's view of them.
        _lastSyncedAt = DateTime.now();
        return;
      }
      await user.replaceFavourites(themes: themes, wallpapers: wallpapers);
      _lastError = null;
      _lastSyncedAt = DateTime.now();
    } on Object catch (e) {
      _lastError = e;
      debugPrint('Favourites sync failed: $e');
    }
  }

  static List<String> _ids(List<FavouriteItem> items, String type) => [
    for (final i in items)
      if (i.itemType == type) i.itemId,
  ];

  /// [first] in order, then anything only in [second].
  static List<String> _union(List<String> first, List<String> second) => [
    ...first,
    for (final id in second)
      if (!first.contains(id)) id,
  ];

  static List<String> _applyOps(List<String> ids, List<_Op> ops, String type) {
    final out = [...ids];
    for (final op in ops) {
      if (op.item.itemType != type) continue;
      out.remove(op.item.itemId);
      if (op.add) out.insert(0, op.item.itemId);
    }
    return out;
  }

  Future<List<_Op>> _readOps() async {
    final raw = await _prefs.getString(_pendingKey);
    if (raw == null) return [];
    try {
      return [
        for (final o in jsonDecode(raw) as List)
          _Op(
            FavouriteItem(o['itemType'] as String, o['itemId'] as String),
            add: o['add'] as bool,
          ),
      ];
    } on Object catch (e) {
      debugPrint('Ignoring damaged favourite queue: $e');
      return [];
    }
  }

  Future<void> _writeOps(List<_Op> ops) => ops.isEmpty
      ? _prefs.remove(_pendingKey)
      : _prefs.setString(
          _pendingKey,
          jsonEncode([
            for (final o in ops) {...o.item.toJson(), 'add': o.add},
          ]),
        );
}

class _Op {
  const _Op(this.item, {required this.add});

  final FavouriteItem item;
  final bool add;
}
