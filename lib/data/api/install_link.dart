import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_version.dart' as build;
import 'api_client.dart';
import 'api_exception.dart';
import 'auth_session.dart';
import 'install_id.dart';

/// Ties this install to the signed-in account, once per account
/// (`POST /v1/me/installs`, docs/app-client.md §3). Only for stats:
/// failures are retried on the next sign-in change or launch, and
/// `409 install_linked` (another account has it) is accepted quietly.
class InstallLink {
  InstallLink({
    required this.api,
    required this.session,
    required this.installId,
    this.appVersion = build.appVersion,
    SharedPreferencesAsync? prefs,
  }) : _prefs = prefs ?? SharedPreferencesAsync() {
    session.addListener(_check);
    _check();
  }

  final ApiClient api;
  final AuthSession session;
  final InstallId installId;
  final String appVersion;
  final SharedPreferencesAsync _prefs;

  static const _key = 'install_linked_account';

  Future<void>? _inFlight;

  /// Completes when the current attempt does. For tests.
  Future<void> get idle => _inFlight ?? Future.value();

  void dispose() => session.removeListener(_check);

  void _check() {
    final account = session.user?.id;
    if (!session.isSignedIn || account == null || _inFlight != null) return;
    _inFlight = _link(account).whenComplete(() => _inFlight = null);
  }

  Future<void> _link(String account) async {
    try {
      if (await _prefs.getString(_key) == account) return;
      await api.post(
        'me/installs',
        body: {'installId': await installId.get(), 'appVersion': appVersion},
        auth: true,
      );
    } on ApiException catch (e) {
      if (e.code != ApiErrorCode.installLinked) {
        debugPrint('Linking this install failed: $e');
        return;
      }
    }
    await _prefs.setString(_key, account);
  }
}
