import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallp/data/api/api_client.dart';

/// The accounts part of the backend, in memory, with its rules
/// (docs/app-client.md §3): refresh tokens rotate, a reused one signs out
/// the whole login, a password change signs out everything.
class FakeBackend {
  final users = <String, _User>{}; // by email

  /// Every events batch received.
  final eventBatches = <List<Map<String, dynamic>>>[];

  /// Answer events with 429 and this Retry-After.
  Duration? rateLimitFor;

  /// installId -> email.
  final installs = <String, String>{};

  /// Each user's favourites as "type/id", newest first.
  final favourites = <String, List<String>>{};
  final _refresh = <String, _Refresh>{};
  final _access = <String, String>{}; // token -> email
  var _n = 0;

  /// Pretend the network is down.
  bool offline = false;

  /// Hold every refresh until this completes (to test concurrent calls).
  Completer<void>? holdRefresh;

  /// Every request, as "METHOD path".
  final log = <String>[];
  int get refreshCalls => log.where((l) => l == 'POST /v1/auth/refresh').length;

  DateTime expiresAt = DateTime.utc(2100);

  late final ApiClient api = newApi();

  /// Another app install on the same server (each AuthSession owns its
  /// client's `auth`).
  ApiClient newApi() =>
      ApiClient(base: Uri.parse('https://wallp-api.test/v1/'), client: client);

  late final http.Client client = MockClient(_handle);

  /// Makes every access token handed out so far stop working.
  void expireAccessTokens() => _access.clear();

  void addUser(String email, String password, [String name = 'Ana']) =>
      users[email] = _User('u${++_n}', email, password, name);

  /// A refresh token for [email], as if signed in earlier.
  String issueRefresh(String email) {
    final t = 'r${++_n}';
    _refresh[t] = _Refresh(email, 'f$_n');
    return t;
  }

  Future<http.Response> _handle(http.Request r) async {
    log.add('${r.method} ${r.url.path}');
    if (offline) throw const SocketException('offline');
    final body = r.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(r.body) as Map<String, dynamic>;
    final path = r.url.path.replaceFirst('/v1/', '');
    switch ((r.method, path)) {
      case ('POST', 'auth/register'):
        final email = body['email'] as String;
        if (users.containsKey(email)) {
          return _error(422, 'registration_failed');
        }
        if ((body['password'] as String).length < 10) {
          return _error(422, 'validation_failed', field: 'password');
        }
        addUser(
          email,
          body['password'] as String,
          body['displayName'] as String,
        );
        return _session(email, 'f${++_n}', 201);
      case ('POST', 'auth/login'):
        final u = users[body['email']];
        if (u == null || u.password != body['password']) {
          return _error(401, 'bad_credentials');
        }
        return _session(u.email, 'f${++_n}');
      case ('POST', 'auth/refresh'):
        await holdRefresh?.future;
        final t = body['refreshToken'] as String;
        final rt = _refresh[t];
        if (rt == null) return _error(401, 'token_expired');
        if (rt.used) {
          _refresh.removeWhere((_, v) => v.family == rt.family);
          return _error(401, 'token_reused');
        }
        rt.used = true;
        return _session(rt.email, rt.family);
      case ('POST', 'events'):
        if (rateLimitFor != null) {
          return http.Response(
            jsonEncode({
              'error': {'code': 'rate_limited', 'message': 'slow down'},
            }),
            429,
            headers: {'retry-after': '${rateLimitFor!.inSeconds}'},
          );
        }
        if (r.headers.containsKey('Authorization')) {
          return _error(401, 'token_expired');
        }
        if (!_uuid.hasMatch('${body['installId']}')) {
          return _error(422, 'validation_failed', field: 'installId');
        }
        final events = body['events'] as List;
        if (events.length > 100) return _error(422, 'validation_failed');
        eventBatches.add(events.cast<Map<String, dynamic>>());
        return http.Response('', 202);
      case ('POST', 'auth/logout'):
        final rt = _refresh[body['refreshToken']];
        if (rt != null) _refresh.removeWhere((_, v) => v.family == rt.family);
        return http.Response('', 204);
    }

    final email =
        _access[r.headers['Authorization']?.replaceFirst('Bearer ', '')];
    if (r.headers['Authorization'] == null) return _error(401, 'unauthorized');
    if (email == null) return _error(401, 'token_expired');
    final u = users[email]!;
    switch ((r.method, path)) {
      case ('GET', 'me'):
        return _json(200, u.json);
      case ('PATCH', 'me'):
        if (body['displayName'] case final String name) u.name = name;
        if (body['newPassword'] case final String next) {
          if (body['currentPassword'] != u.password) {
            return _error(422, 'invalid', field: 'currentPassword');
          }
          u.password = next;
          _refresh.removeWhere((_, v) => v.email == email);
          _access.removeWhere((_, v) => v == email);
        }
        return _json(200, u.json);
      case ('DELETE', 'me'):
        if (body['password'] != u.password) {
          return _error(422, 'invalid', field: 'password');
        }
        users.remove(email);
        return http.Response('', 204);
      case ('GET', 'me/sessions'):
        final mine = r.headers['X-Refresh-Token'];
        final families = <String, bool>{};
        _refresh.forEach((t, v) {
          if (v.email == email && !v.used) {
            families[v.family] = (families[v.family] ?? false) || t == mine;
          }
        });
        return _json(200, {
          'sessions': [
            for (final MapEntry(key: f, value: current) in families.entries)
              {
                'id': f,
                'userAgent': 'wallp/1.0.0 (android)',
                'ip': '10.0.0.1',
                'createdAt': '2026-10-18T10:00:00Z',
                'expiresAt': '2026-11-17T10:00:00Z',
                'current': current,
              },
          ],
        });
    }
    if ((r.method, path) == ('POST', 'me/installs')) {
      final id = body['installId'] as String;
      final owner = installs[id];
      if (owner != null && owner != email) return _error(409, 'install_linked');
      installs[id] = email;
      return http.Response('', 204);
    }
    final favs = favourites.putIfAbsent(email, () => []);
    switch ((r.method, path)) {
      case ('GET', 'me/favourites'):
        return _json(200, {
          'items': [
            for (final f in favs)
              {
                'itemType': f.split('/').first,
                'itemId': f.split('/').last,
                'createdAt': '2026-10-18T10:00:00Z',
              },
          ],
        });
      case ('PUT', 'me/favourites'):
        final items = body['items'] as List;
        if (items.length > 1000) return _error(422, 'validation_failed');
        final next = <String>[];
        for (final i in items.cast<Map<String, dynamic>>()) {
          final k = _favKey(i['itemType'], i['itemId']);
          if (k == null) {
            return _error(422, 'validation_failed', field: 'items');
          }
          if (!next.contains(k)) next.add(k);
        }
        favs
          ..clear()
          ..addAll(next);
        return _handle(http.Request('GET', r.url)..headers.addAll(r.headers));
      case ('POST', 'me/favourites'):
        final k = _favKey(body['itemType'], body['itemId']);
        if (k == null) return _error(422, 'validation_failed');
        if (!favs.contains(k)) favs.insert(0, k);
        return http.Response('', 204);
    }
    if (r.method == 'DELETE' && path.startsWith('me/favourites/')) {
      favs.remove(path.substring('me/favourites/'.length));
      return http.Response('', 204);
    }
    if (r.method == 'DELETE' && path.startsWith('me/sessions/')) {
      final f = path.substring('me/sessions/'.length);
      final had = _refresh.values.any((v) => v.family == f && v.email == email);
      if (!had) return _error(404, 'not_found');
      _refresh.removeWhere((_, v) => v.family == f);
      return http.Response('', 204);
    }
    return _error(404, 'not_found');
  }

  http.Response _session(String email, String family, [int status = 200]) {
    final access = 'a${++_n}';
    final refresh = 'r${++_n}';
    _access[access] = email;
    _refresh[refresh] = _Refresh(email, family);
    return _json(status, {
      'accessToken': access,
      'refreshToken': refresh,
      'expiresAt': expiresAt.toIso8601String(),
      'user': users[email]!.json,
    });
  }

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  static final _validId = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
  static const _types = {'theme', 'wallpaper', 'font', 'icon-pack'};

  static String? _favKey(Object? type, Object? id) =>
      _types.contains(type) &&
          id is String &&
          id.length <= 100 &&
          _validId.hasMatch(id)
      ? '$type/$id'
      : null;

  static http.Response _json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  static http.Response _error(int status, String code, {String? field}) =>
      _json(status, {
        '\$schema': 'https://wallp-api.test/Error.json',
        'error': {'code': code, 'message': code, 'field': ?field},
      });
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
  _Refresh(this.email, this.family);

  final String email;
  final String family;
  bool used = false;
}
