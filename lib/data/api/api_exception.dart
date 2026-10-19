import 'dart:convert';
import 'dart:io';

/// The `code` of a backend error (docs/app-client.md §5), plus the few the
/// app makes up itself when there was no usable answer.
///
/// Branch on these and the status, never on [ApiException.message].
enum ApiErrorCode {
  badRequest('bad_request'),
  unauthorized('unauthorized'),
  tokenExpired('token_expired'),
  tokenReused('token_reused'),
  badCredentials('bad_credentials'),
  notFound('not_found'),
  methodNotAllowed('method_not_allowed'),
  installLinked('install_linked'),
  tooLarge('too_large'),
  registrationFailed('registration_failed'),
  invalid('invalid'),
  validationFailed('validation_failed'),
  rateLimited('rate_limited'),
  internal('internal'),

  // Made up by the app, never sent by the server:

  /// No connection, or no server at all (the mock env).
  offline('offline'),

  /// The server was too slow to answer.
  timeout('timeout'),

  /// A success status with a body that isn't the JSON we expect.
  badResponse('bad_response'),

  /// A code this build doesn't know yet; [ApiException.rawCode] has it.
  unknown('unknown');

  const ApiErrorCode(this.wire);

  /// As the server writes it.
  final String wire;

  static final _byWire = {for (final c in values) c.wire: c};

  static ApiErrorCode parse(String? wire) => _byWire[wire] ?? unknown;

  /// For error bodies that aren't JSON (nginx pages, Go's plain 404).
  static ApiErrorCode forStatus(int status) => switch (status) {
    400 => badRequest,
    401 => unauthorized,
    404 => notFound,
    405 => methodNotAllowed,
    413 => tooLarge,
    429 => rateLimited,
    >= 500 => internal,
    _ => unknown,
  };
}

/// One entry of an error's `details`.
class FieldError {
  const FieldError(this.field, this.message);

  final String field;
  final String message;

  @override
  String toString() => '$field: $message';
}

/// Every way a `/v1` call can fail, as one type:
///
/// ```json
/// { "error": { "code": "validation_failed", "message": "...",
///              "field": "password", "details": [ ... ] } }
/// ```
class ApiException implements Exception {
  const ApiException({
    required this.status,
    required this.code,
    this.rawCode,
    this.message = '',
    this.field,
    this.details = const [],
    this.retryAfter,
  });

  /// No connection, or the mock env with no server.
  const ApiException.offline([String message = 'offline'])
    : this(status: 0, code: ApiErrorCode.offline, message: message);

  const ApiException.timeout()
    : this(status: 0, code: ApiErrorCode.timeout, message: 'timeout');

  /// Reads the error shape; falls back to the status for any other body.
  factory ApiException.fromResponse(
    int status,
    Map<String, String> headers,
    List<int> body,
  ) {
    final retryAfter = parseRetryAfter(headers['retry-after']);
    Map<String, dynamic>? error;
    try {
      final json = jsonDecode(utf8.decode(body));
      // Unknown keys (the server adds "$schema") are ignored.
      if (json is Map<String, dynamic> && json['error'] is Map) {
        error = (json['error'] as Map).cast<String, dynamic>();
      }
    } on FormatException {
      // Not JSON: an nginx error page, Go's plain-text 404.
    }
    if (error == null) {
      return ApiException(
        status: status,
        code: ApiErrorCode.forStatus(status),
        message: 'HTTP $status',
        retryAfter: retryAfter,
      );
    }
    final raw = error['code'] is String ? error['code'] as String : null;
    return ApiException(
      status: status,
      code: raw == null
          ? ApiErrorCode.forStatus(status)
          : ApiErrorCode.parse(raw),
      rawCode: raw,
      message: error['message'] is String ? error['message'] as String : '',
      field: error['field'] is String ? error['field'] as String : null,
      details: [
        if (error['details'] case final List list)
          for (final d in list)
            if (d case {'field': final String f, 'message': final String m})
              FieldError(f, m),
      ],
      retryAfter: retryAfter,
    );
  }

  /// HTTP status; 0 when there was no answer ([offline], [timeout]).
  final int status;
  final ApiErrorCode code;

  /// The server's code as sent, also when it's [ApiErrorCode.unknown].
  final String? rawCode;

  /// For logs only: it may change, and 5xx messages are generic.
  final String message;

  /// The field at fault, when one is. `body` means a required field was
  /// missing; show that as a general error.
  final String? field;
  final List<FieldError> details;

  /// From the `Retry-After` header (events' `429`).
  final Duration? retryAfter;

  /// Worth trying again later, unchanged.
  bool get isTransient =>
      code == ApiErrorCode.offline ||
      code == ApiErrorCode.timeout ||
      code == ApiErrorCode.rateLimited ||
      status >= 500;

  /// The sign-in is gone; clear tokens and continue signed out.
  bool get endsSession =>
      code == ApiErrorCode.tokenExpired ||
      code == ApiErrorCode.tokenReused ||
      code == ApiErrorCode.unauthorized;

  /// What went wrong with [name], from [field] or [details], for showing
  /// under that form field.
  String? messageFor(String name) {
    for (final d in details) {
      if (d.field == name) return d.message;
    }
    return field == name ? message : null;
  }

  /// `Retry-After` in seconds, or as an HTTP date.
  static Duration? parseRetryAfter(String? value, {DateTime? now}) {
    if (value == null || value.trim().isEmpty) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null) return Duration(seconds: seconds < 0 ? 0 : seconds);
    try {
      final at = HttpDate.parse(value);
      final wait = at.difference(now ?? DateTime.now());
      return wait.isNegative ? Duration.zero : wait;
    } on HttpException {
      return null;
    }
  }

  @override
  String toString() =>
      'ApiException($status ${rawCode ?? code.wire}'
      '${field == null ? '' : ', field $field'}): $message';
}
