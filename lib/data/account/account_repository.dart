import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../api/api_client.dart';
import 'account_models.dart';
import 'token_store.dart';

/// Why the app went back to signed-out.
enum SignOutReason {
  /// The user tapped Sign out.
  user,

  /// The refresh token expired or was revoked (another device signed this
  /// one out, or the password changed).
  expired,

  /// The refresh token was used twice; the server signed out every session
  /// of this login.
  reused,

  /// The account was deleted.
  deleted,
}

/// A sign-in or sign-out, for listeners that sync (FavouritesSync).
sealed class AccountChange {
  const AccountChange();
}

class SignedIn extends AccountChange {
  const SignedIn(this.user, {required this.fresh});

  final AppUser user;

  /// True right after register or login; false when a saved login came
  /// back on app start.
  final bool fresh;
}

class SignedOut extends AccountChange {
  const SignedOut(this.reason);

  final SignOutReason reason;
}

/// The optional account (docs/app-api.md §3). Signing in only adds
/// cross-device favourites; everything else works signed out, and nothing
/// here may block the UI.
///
/// Tokens: the access token lives in memory only; the refresh token in
/// [TokenStore]. Refreshes are single-flight: every caller that finds the
/// access token stale waits for the same refresh, because a second
/// refresh with the same (rotated) token would sign out every session.
class AccountRepository extends ChangeNotifier {
  AccountRepository({
    required this.client,
    TokenStore? tokens,
    this.clock = const SystemClock(),
  }) : _tokens = tokens ?? SecureTokenStore();

  final ApiClient client;
  final TokenStore _tokens;
  final Clock clock;

  /// Refresh this long before the access token's `expiresAt`.
  static const refreshEarly = Duration(seconds: 30);

  AppUser? _user;
  String? _refreshToken;
  String? _accessToken;
  DateTime? _accessExpiresAt;
  Future<String>? _refreshing;
  bool _restored = false;
  final _changes = StreamController<AccountChange>.broadcast();

  /// Null when signed out.
  AppUser? get user => _user;
  bool get isSignedIn => _user != null;

  /// Sign-ins and sign-outs as they happen.
  Stream<AccountChange> get changes => _changes.stream;

  @override
  void dispose() {
    _changes.close();
    super.dispose();
  }

  // --- start-up ---

  /// Brings back a saved login (docs/app-api.md §6 step 3): shows it as
  /// signed in at once, then refreshes. A `401` signs out; being offline
  /// keeps the login for later. Runs once.
  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    final saved = await _tokens.read();
    if (saved == null) return;
    _user = saved.user;
    _refreshToken = saved.refreshToken;
    notifyListeners();
    try {
      await _refresh();
    } on Object catch (e) {
      if (!isSignedIn) return;
      debugPrint('Login kept for later: $e');
    }
    if (isSignedIn) _changes.add(SignedIn(_user!, fresh: false));
  }

  // --- sign in and out ---

  /// Errors: `422 registration_failed`, `422 validation_failed`,
  /// `429 rate_limited`.
  Future<AppUser> register({
    required String email,
    required String password,
    required String displayName,
  }) => _signIn('auth/register', {
    'email': email.trim(),
    'password': password,
    'displayName': displayName.trim(),
  });

  /// Errors: `401 bad_credentials`, `429 rate_limited`.
  Future<AppUser> login({required String email, required String password}) =>
      _signIn('auth/login', {'email': email.trim(), 'password': password});

  Future<AppUser> _signIn(String path, Map<String, Object?> body) async {
    final response = await client.post(path, body: body);
    final session = AuthSession.fromJson(response.object);
    await _keep(session);
    _changes.add(SignedIn(session.user, fresh: true));
    return session.user;
  }

  /// Signs out this phone. Local tokens go even if the server can't be
  /// reached.
  Future<void> logout() async {
    final token = _refreshToken;
    await _signOutLocally(SignOutReason.user);
    if (token == null) return;
    try {
      await client.post('auth/logout', body: {'refreshToken': token});
    } on ApiException catch (e) {
      debugPrint('Logout not sent: $e');
    }
  }

  Future<void> _keep(AuthSession session) async {
    // Saved first: the old refresh token stopped working the moment the
    // server answered.
    await _tokens.write(StoredLogin(session.refreshToken, session.user));
    _refreshToken = session.refreshToken;
    _accessToken = session.accessToken;
    _accessExpiresAt = session.expiresAt;
    _user = session.user;
    notifyListeners();
  }

  Future<void> _signOutLocally(SignOutReason reason) async {
    final was = isSignedIn;
    _user = null;
    _refreshToken = null;
    _accessToken = null;
    _accessExpiresAt = null;
    await _tokens.clear();
    notifyListeners();
    if (was) _changes.add(SignedOut(reason));
  }

  // --- tokens ---

  /// A current access token, refreshing first if it's (nearly) expired.
  Future<String> _access() async {
    final token = _accessToken, expires = _accessExpiresAt;
    if (token != null &&
        expires != null &&
        clock.now().isBefore(expires.subtract(refreshEarly))) {
      return token;
    }
    return _refresh();
  }

  Future<String> _refresh() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<String> _doRefresh() async {
    final token = _refreshToken;
    if (token == null) throw _notSignedIn;
    try {
      final response = await client.post(
        'auth/refresh',
        body: {'refreshToken': token},
      );
      final session = AuthSession.fromJson(response.object);
      await _keep(session);
      return session.accessToken;
    } on ApiException catch (e) {
      if (e.status == 401) {
        await _signOutLocally(
          e.code == 'token_reused'
              ? SignOutReason.reused
              : SignOutReason.expired,
        );
      }
      rethrow;
    }
  }

  static const _notSignedIn = ApiException(
    401,
    'unauthorized',
    message: 'Not signed in',
  );

  /// Calls `/v1/<path>` as the user. On `401 token_expired` it refreshes
  /// once and tries again.
  Future<ApiResponse> authed(
    String method,
    String path, {
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    if (!isSignedIn) throw _notSignedIn;
    final token = await _access();
    try {
      return await client.send(
        method,
        path,
        body: body,
        token: token,
        headers: headers,
      );
    } on ApiException catch (e) {
      if (e.status != 401 || e.code != 'token_expired') rethrow;
      // Another call may have refreshed already; only refresh if not.
      final fresh = _accessToken != token && _accessToken != null
          ? _accessToken!
          : await _refresh();
      return client.send(
        method,
        path,
        body: body,
        token: fresh,
        headers: headers,
      );
    }
  }

  // --- me ---

  Future<AppUser> reloadMe() async {
    final user = AppUser.fromJson((await authed('GET', 'me')).object);
    await _updateUser(user);
    return user;
  }

  Future<AppUser> updateDisplayName(String displayName) async {
    final user = AppUser.fromJson(
      (await authed(
        'PATCH',
        'me',
        body: {'displayName': displayName.trim()},
      )).object,
    );
    await _updateUser(user);
    return user;
  }

  /// The server signs out every session after a password change, so this
  /// logs straight back in with the new password.
  ///
  /// Errors: `422 invalid` with field `currentPassword` or `newPassword`.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final email = _user?.email;
    await authed(
      'PATCH',
      'me',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
    if (email == null) return;
    final session = AuthSession.fromJson(
      (await client.post(
        'auth/login',
        body: {'email': email, 'password': newPassword},
      )).object,
    );
    await _keep(session);
  }

  /// Deletes the account and its favourites. Favourites on this phone
  /// stay. Errors: `422 invalid` (field `password`).
  Future<void> deleteAccount(String password) async {
    await authed('DELETE', 'me', body: {'password': password});
    await _signOutLocally(SignOutReason.deleted);
  }

  Future<void> _updateUser(AppUser user) async {
    final token = _refreshToken;
    if (token == null) return;
    _user = user;
    await _tokens.write(StoredLogin(token, user));
    notifyListeners();
  }

  // --- sessions ---

  Future<List<DeviceSession>> sessions() async {
    final token = _refreshToken;
    final response = await authed(
      'GET',
      'me/sessions',
      headers: {'X-Refresh-Token': ?token},
    );
    return [
      for (final s in response.object['sessions'] as List? ?? const [])
        DeviceSession.fromJson(s as Map<String, dynamic>),
    ];
  }

  Future<void> revokeSession(String id) =>
      authed('DELETE', 'me/sessions/${Uri.encodeComponent(id)}');

  // --- favourites ---

  /// Newest first.
  Future<List<FavouriteItem>> favourites() async {
    final response = await authed('GET', 'me/favourites');
    return _items(response);
  }

  /// Replaces every favourite; returns the server's new list.
  Future<List<FavouriteItem>> replaceFavourites(
    List<FavouriteItem> items,
  ) async => _items(
    await authed(
      'PUT',
      'me/favourites',
      body: {
        'items': [for (final i in items) i.toJson()],
      },
    ),
  );

  Future<void> addFavourite(FavouriteItem item) =>
      authed('POST', 'me/favourites', body: item.toJson());

  Future<void> removeFavourite(FavouriteItem item) => authed(
    'DELETE',
    'me/favourites/${Uri.encodeComponent(item.itemType)}/'
        '${Uri.encodeComponent(item.itemId)}',
  );

  static List<FavouriteItem> _items(ApiResponse response) => [
    for (final i in response.object['items'] as List? ?? const [])
      FavouriteItem.fromJson(i as Map<String, dynamic>),
  ];

  // --- installs ---

  /// Ties this phone's install ID to the account. `409 install_linked`
  /// (another account has it) only affects stats, so it counts as done.
  Future<void> linkInstall(String installId, String appVersion) async {
    try {
      await authed(
        'POST',
        'me/installs',
        body: {'installId': installId, 'appVersion': appVersion},
      );
    } on ApiException catch (e) {
      if (e.status != 409) rethrow;
    }
  }
}
