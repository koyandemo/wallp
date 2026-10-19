import 'account_models.dart';
import 'api_client.dart';
import 'auth_session.dart';

/// The `/v1/me` calls (docs/app-client.md §3). Every call needs a
/// sign-in; failures are [ApiException]s.
class AccountService {
  const AccountService(this.api, this.session);

  final ApiClient api;
  final AuthSession session;

  Future<AccountUser> me() async {
    final user = AccountUser.fromJson(await api.get('me', auth: true));
    await session.updateUser(user);
    return user;
  }

  Future<AccountUser> updateDisplayName(String name) async {
    final user = AccountUser.fromJson(
      await api.patch('me', body: {'displayName': name}, auth: true),
    );
    await session.updateUser(user);
    return user;
  }

  /// Changes the password, which signs out every device, then signs this
  /// phone back in with the new one. Returns false if that sign-in failed
  /// (the password did change; the user is now signed out).
  Future<bool> changePassword({
    required String current,
    required String next,
  }) async {
    final email = session.user?.email;
    await api.patch(
      'me',
      body: {'currentPassword': current, 'newPassword': next},
      auth: true,
    );
    if (email != null) {
      try {
        await session.login(email: email, password: next);
        return true;
      } on Object {
        // Fall through: signed out below.
      }
    }
    await session.signOutLocally(SignOutReason.passwordChanged);
    return false;
  }

  /// Deletes the account and its favourites; this phone signs out.
  Future<void> deleteAccount(String password) async {
    await api.delete('me', body: {'password': password}, auth: true);
    await session.signOutLocally(SignOutReason.deleted);
  }

  /// Every device signed in to this account, this phone marked current.
  Future<List<LoginSession>> sessions() async {
    final token = session.refreshToken;
    final json = await api.get(
      'me/sessions',
      auth: true,
      headers: {'X-Refresh-Token': ?token},
    );
    final list = json is Map<String, dynamic> ? json['sessions'] : null;
    return [
      if (list is List)
        for (final s in list) LoginSession.fromJson(s),
    ];
  }

  /// Signs [s] out; signing out this phone's own session also signs out
  /// locally.
  Future<void> revokeSession(LoginSession s) async {
    await api.delete('me/sessions/${Uri.encodeComponent(s.id)}', auth: true);
    if (s.current) await session.signOutLocally(SignOutReason.signedOut);
  }
}
