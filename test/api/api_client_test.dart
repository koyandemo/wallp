import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallp/data/api/api_client.dart';
import 'package:wallp/data/api/api_exception.dart';

final _base = Uri.parse('https://wallp-api.justym.me/v1/');

http.Response _json(int status, Object body, [Map<String, String>? h]) =>
    http.Response(jsonEncode(body), status, headers: h ?? const {});

http.Response _error(int status, String code) => _json(status, {
  'error': {'code': code, 'message': code},
});

/// Hands out tokens like AuthSession will: `t1`, then `t2` after a refresh.
class _FakeAuth implements ApiAuth {
  _FakeAuth({this.token = 't1', this.next = 't2'});

  String? token;
  final String? next;
  final refreshed = <String>[];

  @override
  Future<String?> accessToken() async => token;

  @override
  Future<String?> refreshAccessToken(String rejected) async {
    refreshed.add(rejected);
    return token = next;
  }
}

Matcher _fails(ApiErrorCode code) =>
    throwsA(isA<ApiException>().having((e) => e.code, 'code', code));

void main() {
  group('ApiClient', () {
    test('sends JSON and decodes JSON', () async {
      late http.Request seen;
      final api = ApiClient(
        base: _base,
        client: MockClient((r) async {
          seen = r;
          return _json(200, {'ok': true});
        }),
      );
      final out = await api.post('auth/login', body: {'email': 'a@b.c'});
      expect(out, {'ok': true});
      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'https://wallp-api.justym.me/v1/auth/login');
      expect(seen.headers['Content-Type'], startsWith('application/json'));
      expect(seen.headers['User-Agent'], startsWith('wallp/'));
      expect(seen.headers.containsKey('Authorization'), isFalse);
      expect(jsonDecode(seen.body), {'email': 'a@b.c'});
    });

    test('empty bodies (202, 204) return null', () async {
      for (final status in [202, 204]) {
        final api = ApiClient(
          base: _base,
          client: MockClient((_) async => http.Response('', status)),
        );
        expect(await api.post('events', body: {}), isNull);
      }
    });

    test('query and extra headers', () async {
      late http.Request seen;
      final api = ApiClient(
        base: _base,
        client: MockClient((r) async {
          seen = r;
          return _json(200, {'sessions': []});
        }),
        auth: _FakeAuth(),
      );
      await api.get(
        'me/sessions',
        auth: true,
        headers: {'X-Refresh-Token': 'r1'},
        query: {'perPage': '50'},
      );
      expect(seen.url.query, 'perPage=50');
      expect(seen.headers['X-Refresh-Token'], 'r1');
      expect(seen.headers['Authorization'], 'Bearer t1');
    });

    test('errors become ApiException', () {
      final api = ApiClient(
        base: _base,
        client: MockClient((_) async => _error(401, 'bad_credentials')),
      );
      expect(
        api.post('auth/login', body: {}),
        _fails(ApiErrorCode.badCredentials),
      );
    });

    test('a 200 that is not JSON is a bad response', () {
      final api = ApiClient(
        base: _base,
        client: MockClient((_) async => http.Response('<html>', 200)),
      );
      expect(api.get('me'), _fails(ApiErrorCode.badResponse));
    });

    test('no connection is offline, no answer is a timeout', () {
      final offline = ApiClient(
        base: _base,
        client: MockClient((_) => throw const SocketException('no route')),
      );
      expect(offline.get('me'), _fails(ApiErrorCode.offline));

      final slow = ApiClient(
        base: _base,
        client: MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 100),
      );
      expect(slow.get('me'), _fails(ApiErrorCode.timeout));
    });

    test('rejects absolute paths', () {
      final api = ApiClient(
        base: _base,
        client: MockClient((_) async => _json(200, {})),
      );
      expect(api.get('/v1/me'), throwsArgumentError);
      expect(api.get('../admin/v1/releases'), throwsArgumentError);
    });
  });

  group('ApiClient with auth', () {
    test('signed out fails without a request', () async {
      var calls = 0;
      final api = ApiClient(
        base: _base,
        client: MockClient((_) async {
          calls++;
          return _json(200, {});
        }),
        auth: _FakeAuth(token: null),
      );
      await expectLater(
        api.get('me', auth: true),
        _fails(ApiErrorCode.unauthorized),
      );
      expect(calls, 0);
    });

    test('token_expired: one refresh, one retry with the new token', () async {
      final sent = <String?>[];
      final auth = _FakeAuth();
      final api = ApiClient(
        base: _base,
        auth: auth,
        client: MockClient((r) async {
          sent.add(r.headers['Authorization']);
          return sent.length == 1
              ? _error(401, 'token_expired')
              : _json(200, {'id': 'u1'});
        }),
      );
      expect(await api.get('me', auth: true), {'id': 'u1'});
      expect(sent, ['Bearer t1', 'Bearer t2']);
      expect(auth.refreshed, ['t1']);
    });

    test('a failed refresh rethrows token_expired', () async {
      final auth = _FakeAuth(next: null);
      var calls = 0;
      final api = ApiClient(
        base: _base,
        auth: auth,
        client: MockClient((_) async {
          calls++;
          return _error(401, 'token_expired');
        }),
      );
      await expectLater(
        api.get('me', auth: true),
        _fails(ApiErrorCode.tokenExpired),
      );
      expect(calls, 1);
    });

    test('never more than one retry', () async {
      final auth = _FakeAuth();
      var calls = 0;
      final api = ApiClient(
        base: _base,
        auth: auth,
        client: MockClient((_) async {
          calls++;
          return _error(401, 'token_expired');
        }),
      );
      await expectLater(
        api.get('me', auth: true),
        _fails(ApiErrorCode.tokenExpired),
      );
      expect(calls, 2);
      expect(auth.refreshed, hasLength(1));
    });

    test('other 401s are not refreshed', () async {
      final auth = _FakeAuth();
      final api = ApiClient(
        base: _base,
        auth: auth,
        client: MockClient((_) async => _error(401, 'unauthorized')),
      );
      await expectLater(
        api.get('me', auth: true),
        _fails(ApiErrorCode.unauthorized),
      );
      expect(auth.refreshed, isEmpty);
    });
  });
}
