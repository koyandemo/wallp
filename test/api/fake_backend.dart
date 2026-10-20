import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallp/data/api/api_client.dart';
import 'package:wallp/data/api/api_config.dart';

/// Just enough of the wallp backend (docs/app-api.md §3, §4) to test the
/// app's side: accounts with rotating refresh tokens and reuse detection,
/// favourites, installs and events.
class FakeBackend {
  static const config = ApiConfig('https://api.test');

  /// Every request fails as if there were no connection.
  bool offline = false;

  /// Answer for `POST /v1/events`, and its `Retry-After`.
  int eventsStatus = 202;
  int? eventsRetryAfter;

  final events = <Map<String, dynamic>>[];
  final requests = <String>[];
  final _users = <String, _User>{};
  final _refresh = <String, _Refresh>{};
  final _access = <String, String>{};
  final favourites = <String, List<Map<String, dynamic>>>{};
  final installs = <String, String>{};
  var _n = 0;

  ApiClient client() => ApiClient(config: config, client: MockClient(_handle));

  int count(String request) => requests.where((r) => r == request).length;

  /// Every access token stops working (as after 15 minutes).
  void expireAccessTokens() => _access.clear();

  void addUser(String email, String password, {String name = 'Ana'}) {
    final id = 'u${++_n}';
    _users[email] = _User(id, email, password, name);
    favourites[id] = [];
  }

  String userId(String email) => _users[email]!.id;

  Future<http.Response> _handle(http.Request request) async {
    if (offline) throw http.ClientException('offline');
    final path = request.url.path;
    requests.add('${request.method} $path');
    final body = request.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    switch ((request.method, path)) {
      case ('POST', '/v1/events'):
        if (eventsStatus != 202) {
          return _error(
            eventsStatus,
            eventsStatus == 429 ? 'rate_limited' : 'internal',
            headers: {
              if (eventsRetryAfter != null) 'retry-after': '$eventsRetryAfter',
            },
          );
        }
        events.addAll((body['events'] as List).cast());
        return http.Response('', 202);
      case ('POST', '/v1/auth/register'):
        final email = body['email'] as String;
        if (_users.containsKey(email)) {
          return _error(422, 'registration_failed');
        }
        if ((body['password'] as String).length < 10) {
          return _error(422, 'validation_failed', field: 'password');
        }
        addUser(email, body['password'] as String, name: body['displayName']);
        return _session(_users[email]!, family: 'f${++_n}', status: 201);
      case ('POST', '/v1/auth/login'):
        final user = _users[body['email']];
        if (user == null || user.password != body['password']) {
          return _error(401, 'bad_credentials');
        }
        return _session(user, family: 'f${++_n}');
      case ('POST', '/v1/auth/refresh'):
        final r = _refresh[body['refreshToken']];
        if (r == null || r.revoked) return _error(401, 'token_expired');
        if (r.used) {
          for (final x in _refresh.values) {
            if (x.family == r.family) x.revoked = true;
          }
          return _error(401, 'token_reused');
        }
        r.used = true;
        return _session(
          _users.values.firstWhere((u) => u.id == r.userId),
          family: r.family,
        );
      case ('POST', '/v1/auth/logout'):
        _refresh[body['refreshToken']]?.revoked = true;
        return http.Response('', 204);
    }

    // Everything else needs a token.
    final auth = request.headers['Authorization'];
    if (auth == null) return _error(401, 'unauthorized');
    final userId = _access[auth.substring('Bearer '.length)];
    if (userId == null) return _error(401, 'token_expired');
    final user = _users.values.firstWhere((u) => u.id == userId);
    final favs = favourites[userId]!;

    switch ((request.method, path)) {
      case ('GET', '/v1/me'):
        return _json(200, user.json);
      case ('PATCH', '/v1/me'):
        if (body['displayName'] case final String name) user.name = name;
        if (body['newPassword'] case final String next) {
          if (body['currentPassword'] != user.password) {
            return _error(422, 'invalid', field: 'currentPassword');
          }
          user.password = next;
          for (final r in _refresh.values) {
            if (r.userId == userId) r.revoked = true;
          }
        }
        return _json(200, user.json);
      case ('DELETE', '/v1/me'):
        if (body['password'] != user.password) {
          return _error(422, 'invalid', field: 'password');
        }
        _users.remove(user.email);
        return http.Response('', 204);
      case ('GET', '/v1/me/favourites'):
        return _json(200, {'items': favs});
      case ('PUT', '/v1/me/favourites'):
        final seen = <String>{};
        favs
          ..clear()
          ..addAll([
            for (final i
                in (body['items'] as List).cast<Map<String, dynamic>>())
              if (seen.add('${i['itemType']}/${i['itemId']}'))
                {...i, 'createdAt': '2026-10-20T00:00:00Z'},
          ]);
        return _json(200, {'items': favs});
      case ('POST', '/v1/me/favourites'):
        if (!favs.any(
          (f) =>
              f['itemType'] == body['itemType'] &&
              f['itemId'] == body['itemId'],
        )) {
          favs.insert(0, {...body, 'createdAt': '2026-10-20T00:00:00Z'});
        }
        return http.Response('', 204);
      case ('POST', '/v1/me/installs'):
        final id = body['installId'] as String;
        if (installs[id] case final owner? when owner != userId) {
          return _error(409, 'install_linked');
        }
        installs[id] = userId;
        return http.Response('', 204);
      case ('GET', '/v1/me/sessions'):
        return _json(200, {'sessions': []});
    }
    if (request.method == 'DELETE' && path.startsWith('/v1/me/favourites/')) {
      final parts = path.split('/');
      favs.removeWhere(
        (f) => f['itemType'] == parts[4] && f['itemId'] == parts[5],
      );
      return http.Response('', 204);
    }
    return _error(404, 'not_found');
  }

  http.Response _session(
    _User user, {
    required String family,
    int status = 200,
  }) {
    final access = 'a${++_n}', refresh = 'r${++_n}';
    _access[access] = user.id;
    _refresh[refresh] = _Refresh(user.id, family);
    return _json(status, {
      'accessToken': access,
      'refreshToken': refresh,
      'expiresAt': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 15))
          .toIso8601String(),
      'user': user.json,
    });
  }

  static http.Response _json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  static http.Response _error(
    int status,
    String code, {
    String? field,
    Map<String, String> headers = const {},
  }) => http.Response(
    jsonEncode({
      'error': {'code': code, 'message': code, 'field': ?field},
    }),
    status,
    headers: {'content-type': 'application/json', ...headers},
  );
}

class _User {
  _User(this.id, this.email, this.password, this.name);

  final String id;
  final String email;
  String password;
  String name;

  Map<String, Object?> get json => {
    'id': id,
    'email': email,
    'displayName': name,
    'createdAt': '2026-10-18T10:00:00Z',
  };
}

class _Refresh {
  _Refresh(this.userId, this.family);

  final String userId;
  final String family;
  bool used = false;
  bool revoked = false;
}
