import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/api/api_client.dart';
import '../../data/api/api_exception.dart';
import '../../data/api/auth_session.dart';
import 'user_store.dart';

/// One favourite as the server stores it: `theme/spider-night`.
typedef FavouriteKey = ({String type, String id});

/// Keeps [UserStore]'s favourites in step with the account
/// (docs/app-client.md §3 Favourites). The phone's list stays the truth;
/// the server is a copy that other phones merge from.
///
/// * **Full sync** on sign-in, on start while signed in, and on resume
///   after a failed one: a three-way merge of the phone, the server, and
///   the last list both agreed on ("base"), so an un-heart on another
///   phone removes it here instead of coming back. Then `PUT`.
/// * **Each heart** afterwards: `POST` or `DELETE`, one at a time, in
///   order. A failure needs nothing: the next full sync sees the
///   difference from base.
/// * Signed out, nothing is sent and nothing local changes.
class FavouritesSync {
  FavouritesSync({
    required this.api,
    required this.session,
    required this.user,
    SharedPreferencesAsync? prefs,
  }) : _prefs = prefs ?? SharedPreferencesAsync() {
    session.addListener(_onSession);
    user.addListener(_onUser);
    _onUser();
    _onSession();
  }

  final ApiClient api;
  final AuthSession session;
  final UserStore user;
  final SharedPreferencesAsync _prefs;

  static const themeType = 'theme';
  static const wallpaperType = 'wallpaper';
  static const maxItems = 1000;
  static final _validId = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

  /// The favourites last seen in [user], to tell what a change was.
  List<FavouriteKey>? _known;

  /// The account the last full sync was for; null when it hasn't run or
  /// failed.
  String? _syncedFor;
  String? _syncingFor;

  /// Calls go out one at a time, in order: a PUT must not overtake a
  /// later POST.
  Future<void> _queue = Future.value();

  /// The last full sync's error, or null.
  Object? get lastError => _lastError;
  Object? _lastError;

  /// Completes when every call so far has finished. For tests.
  Future<void> get idle => _queue;

  void dispose() {
    session.removeListener(_onSession);
    user.removeListener(_onUser);
  }

  /// Runs a full sync if signed in and the last one didn't finish.
  Future<void> syncIfNeeded() {
    final id = session.user?.id;
    if (!session.isSignedIn || id == null) return Future.value();
    if (_syncedFor == id || _syncingFor == id) return _queue;
    return _fullSync(id);
  }

  /// Who was signed in last, to forget their base when the account goes.
  String? _account;

  void _onSession() {
    if (!session.isSignedIn) {
      final gone = _account;
      _syncedFor = null;
      _account = null;
      if (gone != null && session.lastSignOut == SignOutReason.deleted) {
        unawaited(forget(gone));
      }
      return;
    }
    _account = session.user?.id;
    unawaited(syncIfNeeded());
  }

  void _onUser() {
    if (!user.isLoaded) return;
    final now = _local();
    final before = _known;
    _known = now;
    // The first load, or not signed in: nothing to send.
    if (before == null || !session.isSignedIn || _syncedFor == null) return;
    final was = before.toSet(), isNow = now.toSet();
    for (final k in now.where((k) => !was.contains(k)).toList().reversed) {
      _send('POST', k);
    }
    for (final k in before.where((k) => !isNow.contains(k))) {
      _send('DELETE', k);
    }
  }

  List<FavouriteKey> _local() => [
    for (final id in user.favouriteThemes) (type: themeType, id: id),
    for (final id in user.favouriteWallpapers) (type: wallpaperType, id: id),
  ];

  void _send(String method, FavouriteKey k) {
    if (!_validId.hasMatch(k.id)) return;
    final account = _syncedFor;
    _enqueue(() async {
      if (account == null || session.user?.id != account) return;
      try {
        if (method == 'POST') {
          await api.post(
            'me/favourites',
            body: {'itemType': k.type, 'itemId': k.id},
            auth: true,
          );
        } else {
          await api.delete(
            'me/favourites/${k.type}/${Uri.encodeComponent(k.id)}',
            auth: true,
          );
        }
        // The server agrees now; keep base in step, so a later change on
        // another phone isn't mistaken for this phone's.
        final base = await _readBase(account);
        if (base != null) {
          await _writeBase(
            account,
            method == 'POST'
                ? [k, ...base.where((b) => b != k)]
                : [
                    for (final b in base)
                      if (b != k) b,
                  ],
          );
        }
      } on ApiException catch (e) {
        // The next full sync fixes it.
        debugPrint('Favourite $method ${k.type}/${k.id} failed: $e');
        if (e.code == ApiErrorCode.offline || e.code == ApiErrorCode.timeout) {
          _syncedFor = null;
        }
      }
    });
  }

  Future<void> _fullSync(String account) {
    _syncingFor = account;
    return _enqueue(() async {
      try {
        await _merge(account);
        _syncedFor = account;
        _lastError = null;
      } on Object catch (e) {
        _syncedFor = null;
        _lastError = e;
        debugPrint('Favourites sync failed: $e');
      } finally {
        _syncingFor = null;
      }
    });
  }

  Future<void> _merge(String account) async {
    final remoteAll = _parse(await api.get('me/favourites', auth: true));
    if (session.user?.id != account) return;
    if (!user.isLoaded) await user.load();

    // Types this app has no favourites for (font, icon-pack) ride along
    // untouched: PUT replaces the whole list.
    bool ours(FavouriteKey k) => k.type == themeType || k.type == wallpaperType;
    final remote = remoteAll.where(ours).toList();
    final others = remoteAll.where((k) => !ours(k)).toList();
    final base = (await _readBase(account))?.toSet() ?? const {};
    final local = _local();
    final localSet = local.toSet(), remoteSet = remote.toSet();

    // Added on another phone since base: new here too, newest first.
    final addedThere = [
      for (final k in remote)
        if (!base.contains(k) && !localSet.contains(k)) k,
    ];
    // Removed on another phone since base, and still here.
    final removedThere = {
      for (final k in base)
        if (!remoteSet.contains(k)) k,
    };
    final merged = [
      ...addedThere,
      for (final k in local)
        // Kept unless the other phone removed it and this one hasn't
        // touched it since (it was in base).
        if (!removedThere.contains(k)) k,
    ];

    // Local first, so the screen updates even if the PUT fails.
    _known = merged;
    await user.replaceFavourites(
      themes: [
        for (final k in merged)
          if (k.type == themeType) k.id,
      ],
      wallpapers: [
        for (final k in merged)
          if (k.type == wallpaperType) k.id,
      ],
    );

    final upload = [
      for (final k in [...merged, ...others])
        if (_validId.hasMatch(k.id) && k.id.length <= 100) k,
    ].take(maxItems).toList();
    await api.put(
      'me/favourites',
      body: {
        'items': [
          for (final k in upload) {'itemType': k.type, 'itemId': k.id},
        ],
      },
      auth: true,
    );
    await _writeBase(account, merged);
  }

  Future<void> _enqueue(Future<void> Function() run) =>
      _queue = _queue.then((_) => run());

  static List<FavouriteKey> _parse(Object? json) {
    final items = json is Map<String, dynamic> ? json['items'] : null;
    return [
      if (items is List)
        for (final i in items)
          if (i case {'itemType': final String t, 'itemId': final String id})
            (type: t, id: id),
    ];
  }

  // --- base: the last list the phone and the server agreed on ---

  static String _baseKey(String account) => 'fav_sync_base_$account';

  Future<List<FavouriteKey>?> _readBase(String account) async {
    try {
      final raw = await _prefs.getString(_baseKey(account));
      if (raw == null) return null;
      return [
        for (final s in (jsonDecode(raw) as List).cast<String>())
          if (s.split('/') case [final t, final id]) (type: t, id: id),
      ];
    } on Object catch (e) {
      debugPrint('Ignoring damaged favourites sync base: $e');
      return null;
    }
  }

  Future<void> _writeBase(String account, List<FavouriteKey> keys) =>
      _prefs.setString(
        _baseKey(account),
        jsonEncode([for (final k in keys) '${k.type}/${k.id}']),
      );

  /// Forgets [account]'s base, e.g. after deleting it.
  Future<void> forget(String account) => _prefs.remove(_baseKey(account));
}
