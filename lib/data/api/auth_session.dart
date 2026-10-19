import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import 'account_models.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'token_store.dart';

/// Why the app is signed out, for a one-line note in Me.
enum SignOutReason {
  /// The user tapped Sign out.
  signedOut,

  /// The refresh token expired or was revoked (signed out elsewhere).
  expired,

  /// The refresh token was used twice; the server signed out every device
  /// of that login.
  reused,

  /// The password changed and signing in again with it failed.
  passwordChanged,

  /// The account was deleted.
  deleted,
}

/// The optional sign-in (docs/app-client.md §3).
///
/// * The refresh token (and the user) are saved in [TokenStore]; the
///   access token stays in memory.
/// * One refresh at a time: every caller waits for the same one. The server
///   rotates refresh tokens and treats a second use as theft.
/// * A dead refresh token signs out locally. No connection keeps it, and
///   the app stays signed in, offline.
///
/// Nothing in the app waits for this: signed out is a normal state.
class AuthSession extends ChangeNotifier implements ApiAuth {
  AuthSession({
    required this.api,
    required this._store,
    this.clock = const SystemClock(),
    this.refreshEarly = const Duration(minutes: 1),
  }) {
    api.auth = this;
  }

  final ApiClient api;
  final TokenStore _store;

  /// The real time: token expiry must not follow Developer settings'
  /// pretend date.
  final Clock clock;

  /// Refresh this long before the access token ends.
  final Duration refreshEarly;

  String? _refreshToken;
  String? _accessToken;
  DateTime? _expiresAt;
  AccountUser? _user;
  SignOutReason? _lastSignOut;
  Future<String?>? _inFlight;
  bool _started = false;

  bool get isSignedIn => _refreshToken != null;

  /// Who's signed in; from the saved copy until the first refresh.
  AccountUser? get user => _user;

  /// Why the last sign-out happened, until the next sign-in.
  SignOutReason? get lastSignOut => _lastSignOut;

  /// For `X-Refresh-Token` on `GET /v1/me/sessions`.
  String? get refreshToken => _refreshToken;

  /// Loads the saved sign-in, then refreshes in the background
  /// (docs/app-client.md §6 step 3). Safe to call more than once.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    SavedLogin? saved;
    try {
      saved = await _store.read();
    } on Object catch (e) {
      // Unreadable (e.g. restored from a backup to a new phone): start over.
      debugPrint('Ignoring saved sign-in: $e');
      await _safeClear();
    }
    if (saved == null || _refreshToken != null) return;
    _refreshToken = saved.refreshToken;
    _user = saved.user;
    notifyListeners();
    unawaited(
      _refresh().then<void>(
        (_) {},
        onError: (Object e) => debugPrint('Sign-in refresh failed: $e'),
      ),
    );
  }

  Future<AccountUser> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final json = await api.post(
      'auth/register',
      body: {'email': email, 'password': password, 'displayName': displayName},
    );
    return _adopt(SessionTokens.fromJson(json));
  }

  Future<AccountUser> login({
    required String email,
    required String password,
  }) async {
    final json = await api.post(
      'auth/login',
      body: {'email': email, 'password': password},
    );
    return _adopt(SessionTokens.fromJson(json));
  }

  /// Signs out at once, then tells the server if it can.
  Future<void> logout() async {
    final token = _refreshToken;
    await signOutLocally(SignOutReason.signedOut);
    if (token == null) return;
    try {
      await api.post('auth/logout', body: {'refreshToken': token});
    } on ApiException catch (e) {
      // The token dies on its own in 30 days; nothing to do.
      debugPrint('Logout call failed: $e');
    }
  }

  /// Forgets the sign-in on this phone without calling the server.
  Future<void> signOutLocally(SignOutReason reason) async {
    _refreshToken = null;
    _accessToken = null;
    _expiresAt = null;
    _user = null;
    _lastSignOut = reason;
    await _safeClear();
    notifyListeners();
  }

  /// After `GET`/`PATCH /v1/me`.
  Future<void> updateUser(AccountUser user) async {
    final token = _refreshToken;
    if (token == null) return;
    _user = user;
    notifyListeners();
    await _save(SavedLogin(token, user));
  }

  // --- ApiAuth ---

  @override
  Future<String?> accessToken() async {
    if (_refreshToken == null) return null;
    if (_accessToken != null && !_expiringSoon) return _accessToken;
    return _refresh();
  }

  @override
  Future<String?> refreshAccessToken(String rejected) async {
    if (_refreshToken == null) return null;
    // Another call already refreshed past the rejected token.
    if (_accessToken != null && _accessToken != rejected && !_expiringSoon) {
      return _accessToken;
    }
    return _refresh();
  }

  bool get _expiringSoon {
    final at = _expiresAt;
    return at == null || !clock.now().add(refreshEarly).isBefore(at);
  }

  /// The new access token, or null when the sign-in is gone. Throws
  /// [ApiException] when the server can't be reached (still signed in).
  Future<String?> _refresh() =>
      _inFlight ??= _doRefresh().whenComplete(() => _inFlight = null);

  Future<String?> _doRefresh() async {
    final token = _refreshToken;
    if (token == null) return null;
    final Object? json;
    try {
      json = await api.post('auth/refresh', body: {'refreshToken': token});
    } on ApiException catch (e) {
      if (e.isTransient) rethrow;
      // Unknown, expired, revoked or reused: this sign-in is over. Unless
      // the user already signed out or in again meanwhile.
      if (_refreshToken == token) {
        await signOutLocally(
          e.code == ApiErrorCode.tokenReused
              ? SignOutReason.reused
              : SignOutReason.expired,
        );
      }
      return null;
    }
    if (_refreshToken != token) return _accessToken;
    await _adopt(SessionTokens.fromJson(json));
    return _accessToken;
  }

  Future<AccountUser> _adopt(SessionTokens s) async {
    _refreshToken = s.refreshToken;
    _accessToken = s.accessToken;
    _expiresAt = s.expiresAt;
    _user = s.user;
    _lastSignOut = null;
    notifyListeners();
    // At once: the old refresh token stopped working on the server.
    await _save(SavedLogin(s.refreshToken, s.user));
    return s.user;
  }

  Future<void> _save(SavedLogin login) async {
    try {
      await _store.write(login);
    } on Object catch (e) {
      // Still signed in for this run.
      debugPrint('Saving sign-in failed: $e');
    }
  }

  Future<void> _safeClear() async {
    try {
      await _store.clear();
    } on Object catch (e) {
      debugPrint('Clearing sign-in failed: $e');
    }
  }
}
