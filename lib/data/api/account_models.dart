import 'api_exception.dart';

/// The signed-in person (docs/app-client.md §3).
class AccountUser {
  const AccountUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.createdAt,
  });

  factory AccountUser.fromJson(Object? json) {
    final m = _map(json, 'user');
    return AccountUser(
      id: _string(m, 'id'),
      email: _string(m, 'email'),
      displayName: _string(m, 'displayName'),
      createdAt: _date(m, 'createdAt'),
    );
  }

  final String id;
  final String email;
  final String displayName;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'email': email,
    'displayName': displayName,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

/// What register, login and refresh return.
class SessionTokens {
  const SessionTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  factory SessionTokens.fromJson(Object? json) {
    final m = _map(json, 'session');
    return SessionTokens(
      accessToken: _string(m, 'accessToken'),
      refreshToken: _string(m, 'refreshToken'),
      expiresAt: _date(m, 'expiresAt'),
      user: AccountUser.fromJson(m['user']),
    );
  }

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final AccountUser user;
}

/// One signed-in device, from `GET /v1/me/sessions`.
class LoginSession {
  const LoginSession({
    required this.id,
    required this.userAgent,
    required this.ip,
    required this.createdAt,
    required this.expiresAt,
    required this.current,
  });

  factory LoginSession.fromJson(Object? json) {
    final m = _map(json, 'session');
    return LoginSession(
      id: _string(m, 'id'),
      userAgent: m['userAgent'] is String ? m['userAgent'] as String : '',
      ip: m['ip'] is String ? m['ip'] as String : '',
      createdAt: _date(m, 'createdAt'),
      expiresAt: _date(m, 'expiresAt'),
      current: m['current'] == true,
    );
  }

  /// The login (token family) id.
  final String id;
  final String userAgent;
  final String ip;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// This phone.
  final bool current;
}

Never _bad(String what) => throw ApiException(
  status: 200,
  code: ApiErrorCode.badResponse,
  message: what,
);

Map<String, dynamic> _map(Object? json, String what) =>
    json is Map<String, dynamic> ? json : _bad('$what is not an object');

String _string(Map<String, dynamic> m, String key) =>
    m[key] is String ? m[key] as String : _bad('$key is missing');

DateTime _date(Map<String, dynamic> m, String key) =>
    DateTime.tryParse(_string(m, key)) ?? _bad('$key is not a date');
