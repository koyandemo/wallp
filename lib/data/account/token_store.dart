import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'account_models.dart';

/// What survives a restart while signed in: the refresh token and who it
/// belongs to. The access token is never saved (docs/app-api.md §3).
class StoredLogin {
  const StoredLogin(this.refreshToken, this.user);

  final String refreshToken;
  final AppUser user;
}

abstract class TokenStore {
  Future<StoredLogin?> read();
  Future<void> write(StoredLogin login);
  Future<void> clear();
}

/// Keychain on iOS, Keystore-backed storage on Android. Never shared
/// preferences, never logs.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'refresh_token';
  static const _userKey = 'account_user';

  @override
  Future<StoredLogin?> read() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      final user = await _storage.read(key: _userKey);
      if (token == null || user == null) return null;
      return StoredLogin(
        token,
        AppUser.fromJson(jsonDecode(user) as Map<String, dynamic>),
      );
    } on Object catch (e) {
      // Keystore reset (e.g. restored backup): start signed out.
      debugPrint('Saved login unreadable: ${e.runtimeType}');
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(StoredLogin login) async {
    await _storage.write(key: _tokenKey, value: login.refreshToken);
    await _storage.write(key: _userKey, value: jsonEncode(login.user.toJson()));
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userKey);
    } on Object catch (e) {
      debugPrint('Could not clear saved login: ${e.runtimeType}');
    }
  }
}

class MemoryTokenStore implements TokenStore {
  StoredLogin? login;

  @override
  Future<StoredLogin?> read() async => login;

  @override
  Future<void> write(StoredLogin login) async => this.login = login;

  @override
  Future<void> clear() async => login = null;
}
