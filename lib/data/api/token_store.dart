import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'account_models.dart';

/// The sign-in kept between runs: the refresh token, and the user so Me
/// can show who's signed in while offline.
class SavedLogin {
  const SavedLogin(this.refreshToken, this.user);

  final String refreshToken;
  final AccountUser user;
}

/// Where [SavedLogin] lives. Never shared prefs or logs
/// (docs/app-client.md §3); the access token is never saved at all.
abstract interface class TokenStore {
  Future<SavedLogin?> read();
  Future<void> write(SavedLogin login);
  Future<void> clear();
}

/// Keychain on iOS, Keystore-backed storage on Android.
class SecureTokenStore implements TokenStore {
  /// [scope] keeps each server's sign-in apart (env/*.json), so switching
  /// from prod to the local backend doesn't send prod's token there.
  SecureTokenStore({required String scope, FlutterSecureStorage? storage})
    : _key = 'wallp_login_$scope',
      _storage = storage ?? const FlutterSecureStorage();

  final String _key;
  final FlutterSecureStorage _storage;

  @override
  Future<SavedLogin?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return SavedLogin(
      m['refreshToken'] as String,
      AccountUser.fromJson(m['user']),
    );
  }

  @override
  Future<void> write(SavedLogin login) => _storage.write(
    key: _key,
    value: jsonEncode({
      'refreshToken': login.refreshToken,
      'user': login.user.toJson(),
    }),
  );

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// For tests, and the mock env.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this.saved]);

  SavedLogin? saved;

  @override
  Future<SavedLogin?> read() async => saved;

  @override
  Future<void> write(SavedLogin login) async => saved = login;

  @override
  Future<void> clear() async => saved = null;
}
