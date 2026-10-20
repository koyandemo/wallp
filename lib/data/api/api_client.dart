import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/app_version.dart';
import 'api_config.dart';

/// One failed call to the app API (docs/app-api.md §1, §5).
///
/// Branch on [status] and [code], never on [message]: the server may
/// reword it.
class ApiException implements Exception {
  const ApiException(
    this.status,
    this.code, {
    this.message,
    this.field,
    this.details = const [],
    this.retryAfter,
  });

  /// No answer at all: offline, timeout, TLS or DNS failure.
  const ApiException.network([String? message])
    : this(0, networkCode, message: message);

  /// [code] when there was no response.
  static const networkCode = 'network';

  /// 0 when there was no response.
  final int status;

  /// `validation_failed`, `token_expired`, `rate_limited`, …
  final String code;
  final String? message;

  /// The request field the error is about, e.g. `password`.
  final String? field;
  final List<ApiFieldError> details;

  /// From the `Retry-After` header (events rate limit).
  final Duration? retryAfter;

  bool get isNetwork => status == 0;

  /// Worth trying again later without changing anything.
  bool get isTransient => isNetwork || status >= 500;

  /// The message for [field], or the first detail's, or [message].
  String? messageFor(String field) {
    for (final d in details) {
      if (d.field == field) return d.message;
    }
    return this.field == field ? message : null;
  }

  @override
  String toString() =>
      'ApiException($status $code'
      '${field == null ? '' : ' $field'}'
      '${message == null ? '' : ': $message'})';
}

class ApiFieldError {
  const ApiFieldError(this.field, this.message);

  final String? field;
  final String message;
}

/// A successful (2xx) answer. [json] is null for empty bodies (204, 202).
class ApiResponse {
  const ApiResponse(this.status, this.json);

  final int status;
  final Object? json;

  Map<String, dynamic> get object => json is Map<String, dynamic>
      ? json! as Map<String, dynamic>
      : throw const ApiException(200, 'bad_response', message: 'not an object');
}

/// JSON over HTTP to `<base>/v1/…`. Every failure comes out as an
/// [ApiException], so callers have one thing to catch.
class ApiClient {
  ApiClient({
    this.config = ApiConfig.current,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _http = client ?? http.Client();

  final ApiConfig config;
  final http.Client _http;
  final Duration timeout;

  static final userAgent = 'wallp/$appVersion (${Platform.operatingSystem})';

  /// Sends [body] (encoded as JSON) to `/v1/<path>`. A [token] adds
  /// `Authorization: Bearer`.
  Future<ApiResponse> send(
    String method,
    String path, {
    Object? body,
    String? token,
    Map<String, String> headers = const {},
  }) async {
    final request = http.Request(method, config.api(path))
      ..headers.addAll({
        'Accept': 'application/json',
        'User-Agent': userAgent,
        'Authorization': ?(token == null ? null : 'Bearer $token'),
        ...headers,
      });
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw const ApiException.network('timed out');
    } on SocketException catch (e) {
      throw ApiException.network(e.message);
    } on TlsException catch (e) {
      throw ApiException.network(e.message);
    } on http.ClientException catch (e) {
      throw ApiException.network(e.message);
    }

    final status = response.statusCode;
    Object? json;
    if (response.bodyBytes.isNotEmpty) {
      try {
        json = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        // A proxy's HTML error page: judged by status alone below.
      }
    }
    if (status >= 200 && status < 300) return ApiResponse(status, json);
    throw _error(status, json, response.headers['retry-after']);
  }

  Future<ApiResponse> get(String path, {String? token}) =>
      send('GET', path, token: token);

  Future<ApiResponse> post(String path, {Object? body, String? token}) =>
      send('POST', path, body: body, token: token);

  static ApiException _error(int status, Object? json, String? retryAfter) {
    final retry = int.tryParse(retryAfter ?? '');
    final error = json is Map ? json['error'] : null;
    if (error is! Map) {
      return ApiException(
        status,
        status >= 500 ? 'internal' : 'http_$status',
        retryAfter: retry == null ? null : Duration(seconds: retry),
      );
    }
    final details = error['details'];
    return ApiException(
      status,
      error['code'] as String? ?? 'http_$status',
      message: error['message'] as String?,
      field: error['field'] as String?,
      details: [
        if (details is List)
          for (final d in details)
            if (d is Map && d['message'] is String)
              ApiFieldError(d['field'] as String?, d['message'] as String),
      ],
      retryAfter: retry == null ? null : Duration(seconds: retry),
    );
  }

  void close() => _http.close();
}
