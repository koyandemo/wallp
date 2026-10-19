import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/data/api/api_exception.dart';

ApiException _parse(int status, String body, [Map<String, String>? headers]) =>
    ApiException.fromResponse(status, headers ?? const {}, utf8.encode(body));

void main() {
  group('ApiException.fromResponse', () {
    test('reads the error shape and ignores \$schema', () {
      // As the live server sent it (docs/api-binding-plan.md §7).
      final e = _parse(
        422,
        '{"\$schema":"https://wallp-api.justym.me/Error.json","error":{'
        '"code":"validation_failed","message":"expected string to be RFC 4122 uuid",'
        '"field":"installId","details":[{"field":"installId",'
        '"message":"expected string to be RFC 4122 uuid"}]}}',
      );
      expect(e.status, 422);
      expect(e.code, ApiErrorCode.validationFailed);
      expect(e.field, 'installId');
      expect(e.details.single.field, 'installId');
      expect(e.messageFor('installId'), startsWith('expected string'));
      expect(e.messageFor('password'), isNull);
    });

    test('missing fields come as field "body"', () {
      final e = _parse(
        422,
        '{"error":{"code":"validation_failed","message":"m","field":"body",'
        '"details":[{"field":"body","message":"email required"},'
        '{"field":"body","message":"password required"}]}}',
      );
      expect(e.details, hasLength(2));
      expect(e.messageFor('email'), isNull);
    });

    test('every documented code parses', () {
      for (final c in ApiErrorCode.values) {
        expect(ApiErrorCode.parse(c.wire), c);
      }
    });

    test('an unknown code keeps the raw value', () {
      final e = _parse(409, '{"error":{"code":"brand_new","message":"x"}}');
      expect(e.code, ApiErrorCode.unknown);
      expect(e.rawCode, 'brand_new');
    });

    test('non-JSON bodies fall back to the status', () {
      expect(
        _parse(502, '<html>Bad Gateway</html>').code,
        ApiErrorCode.internal,
      );
      expect(_parse(404, '404 page not found').code, ApiErrorCode.notFound);
      expect(_parse(418, '').code, ApiErrorCode.unknown);
    });

    test('Retry-After', () {
      final e = _parse(
        429,
        '{"error":{"code":"rate_limited","message":"slow down"}}',
        {'retry-after': '120'},
      );
      expect(e.code, ApiErrorCode.rateLimited);
      expect(e.retryAfter, const Duration(seconds: 120));
      expect(e.isTransient, isTrue);

      final now = DateTime.utc(2026, 10, 18, 9);
      expect(
        ApiException.parseRetryAfter('Sun, 18 Oct 2026 09:01:00 GMT', now: now),
        const Duration(minutes: 1),
      );
      expect(ApiException.parseRetryAfter('soon'), isNull);
    });

    test('which errors end the session', () {
      for (final code in ['token_expired', 'token_reused', 'unauthorized']) {
        expect(
          _parse(401, '{"error":{"code":"$code","message":""}}').endsSession,
          isTrue,
        );
      }
      expect(
        _parse(
          401,
          '{"error":{"code":"bad_credentials","message":""}}',
        ).endsSession,
        isFalse,
      );
    });
  });
}
