import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';
import 'api_exception.dart';

/// Where [ApiClient] gets Bearer tokens. AuthSession implements it.
abstract interface class ApiAuth {
  /// The current access token, refreshed first if it's about to expire.
  /// Null when signed out.
  Future<String?> accessToken();

  /// The server said `401 token_expired` to [rejected]. Returns a fresh
  /// token, or null when the sign-in is gone.
  ///
  /// Several calls can fail at once: implementations must run one refresh
  /// at a time and hand the same result to every caller (and return the
  /// current token straight away if it is already newer than [rejected]).
  Future<String?> refreshAccessToken(String rejected);
}

/// JSON calls to `/v1` (docs/app-client.md §3, §4).
///
/// Paths are relative to [base]: `auth/login`, `me/favourites`. Every
/// failure is an [ApiException]; success returns the decoded JSON, or null
/// for an empty body (`202`, `204`).
class ApiClient {
  ApiClient({
    required this.base,
    http.Client? client,
    this.auth,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  /// For [config]'s server.
  factory ApiClient.forConfig(
    ApiConfig config, {
    http.Client? client,
    ApiAuth? auth,
  }) => ApiClient(base: config.apiBase, client: client, auth: auth);

  /// `.../v1/`.
  final Uri base;
  final http.Client _client;

  /// Set once accounts exist; calls with `auth: true` need it.
  ApiAuth? auth;

  /// For the whole call: connect, send and read the answer.
  final Duration timeout;

  Future<Object?> get(
    String path, {
    bool auth = false,
    Map<String, String>? headers,
    Map<String, String>? query,
  }) => send('GET', path, auth: auth, headers: headers, query: query);

  Future<Object?> post(
    String path, {
    Object? body,
    bool auth = false,
    Map<String, String>? headers,
  }) => send('POST', path, body: body, auth: auth, headers: headers);

  Future<Object?> put(
    String path, {
    Object? body,
    bool auth = false,
    Map<String, String>? headers,
  }) => send('PUT', path, body: body, auth: auth, headers: headers);

  Future<Object?> patch(
    String path, {
    Object? body,
    bool auth = false,
    Map<String, String>? headers,
  }) => send('PATCH', path, body: body, auth: auth, headers: headers);

  Future<Object?> delete(
    String path, {
    Object? body,
    bool auth = false,
    Map<String, String>? headers,
  }) => send('DELETE', path, body: body, auth: auth, headers: headers);

  /// With `auth: true`: sends the Bearer token, and on `401 token_expired`
  /// refreshes once and tries once more.
  Future<Object?> send(
    String method,
    String path, {
    Object? body,
    bool auth = false,
    Map<String, String>? headers,
    Map<String, String>? query,
  }) async {
    if (path.startsWith('/') || path.contains('..')) {
      throw ArgumentError.value(path, 'path', 'must be relative to /v1/');
    }
    var url = base.resolve(path);
    if (query != null && query.isNotEmpty) {
      url = url.replace(queryParameters: {...url.queryParameters, ...query});
    }
    final encoded = body == null ? null : utf8.encode(jsonEncode(body));

    String? token;
    if (auth) {
      token = await _requireAuth().accessToken();
      if (token == null) throw _signedOut;
    }
    try {
      return await _once(method, url, encoded, headers, token);
    } on ApiException catch (e) {
      if (token == null || e.code != ApiErrorCode.tokenExpired) rethrow;
      final fresh = await _requireAuth().refreshAccessToken(token);
      if (fresh == null) rethrow;
      return _once(method, url, encoded, headers, fresh);
    }
  }

  static const _signedOut = ApiException(
    status: 401,
    code: ApiErrorCode.unauthorized,
    message: 'signed out',
  );

  ApiAuth _requireAuth() =>
      auth ?? (throw StateError('ApiClient.auth is not set'));

  Future<Object?> _once(
    String method,
    Uri url,
    List<int>? body,
    Map<String, String>? headers,
    String? token,
  ) async {
    final request = http.Request(method, url)
      ..headers.addAll({
        'Accept': 'application/json',
        'User-Agent': userAgent,
        if (body != null) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        ...?headers,
      });
    if (body != null) request.bodyBytes = body;

    final http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException {
      throw const ApiException.timeout();
    } on SocketException catch (e) {
      throw ApiException.offline(e.message);
    } on HandshakeException catch (e) {
      throw ApiException(
        status: 0,
        code: ApiErrorCode.offline,
        message: 'TLS: ${e.message}',
      );
    } on http.ClientException catch (e) {
      throw ApiException.offline(e.message);
    }

    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      throw ApiException.fromResponse(
        status,
        response.headers,
        response.bodyBytes,
      );
    }
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (e) {
      throw ApiException(
        status: status,
        code: ApiErrorCode.badResponse,
        message: 'not JSON: ${e.message}',
      );
    }
  }

  void close() => _client.close();
}
