import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallp/data/network_log.dart';

void main() {
  test('logs method, address, status and size; never the token', () async {
    final log = NetworkLog();
    final printed = <String>[];
    final client = LoggingClient(
      MockClient((_) async => http.Response('{"ok":true}', 200)),
      log: log,
    );
    await runZonedPrint(
      () => client.get(
        Uri.parse('https://wallp-api.justym.me/v1/me'),
        headers: {'Authorization': 'Bearer secret-token'},
      ),
      printed,
    );
    final call = log.calls.single;
    expect(call.status, 200);
    expect(call.method, 'GET');
    expect(call.url.path, '/v1/me');
    expect(call.bytes, 11);
    expect(call.failed, isFalse);
    expect(printed.single, startsWith('[net] 200 GET /v1/me'));
    expect(printed.join(), isNot(contains('secret-token')));
  });

  test('failures are logged and still thrown', () async {
    final log = NetworkLog();
    final client = LoggingClient(
      MockClient((_) => throw const SocketException('no route')),
      log: log,
      printCalls: false,
    );
    await expectLater(
      client.get(
        Uri.parse('https://wallp-api.justym.me/catalog/v1/manifest.json'),
      ),
      throwsA(isA<SocketException>()),
    );
    expect(log.calls.single.failed, isTrue);
    expect(log.calls.single.status, isNull);
  });

  test('keeps the newest calls only', () {
    final log = NetworkLog(max: 3);
    for (var i = 0; i < 5; i++) {
      log.add(
        NetworkCall(
          method: 'GET',
          url: Uri.parse('https://x/$i'),
          at: DateTime(2026),
          duration: Duration.zero,
          status: 200,
        ),
      );
    }
    expect([for (final c in log.calls) c.url.path], ['/4', '/3', '/2']);
  });
}

/// Runs [body], collecting debugPrint output.
Future<void> runZonedPrint(
  Future<void> Function() body,
  List<String> into,
) async {
  final original = debugPrint;
  debugPrint = (String? m, {int? wrapWidth}) => into.add(m ?? '');
  try {
    await body();
  } finally {
    debugPrint = original;
  }
}
