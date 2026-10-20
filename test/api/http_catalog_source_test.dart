import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallp/data/catalog/catalog_source.dart';
import 'package:wallp/data/catalog/http_catalog_source.dart';

import 'fake_backend.dart';

void main() {
  final seen = <http.BaseRequest>[];
  late http.Response Function(http.Request) answer;

  HttpCatalogSource source() => HttpCatalogSource(
    config: FakeBackend.config,
    client: MockClient((r) async {
      seen.add(r);
      return answer(r);
    }),
  );

  setUp(seen.clear);

  test('reads files from <base>/catalog/v1/', () async {
    answer = (_) => http.Response('{"a":1}', 200);
    final bytes = await source().get(
      'themes/spider-night.3.json',
      maxBytes: 100,
    );
    expect(utf8.decode(bytes), '{"a":1}');
    expect(
      seen.single.url.toString(),
      'https://api.test/catalog/v1/themes/spider-night.3.json',
    );
  });

  test('asks for the manifest with If-None-Match and replays a 304', () async {
    final s = source();
    answer = (_) => http.Response('{"v":1}', 200, headers: {'etag': '"abc"'});
    expect(utf8.decode(await s.get('manifest.json', maxBytes: 100)), '{"v":1}');
    expect(seen.last.headers['If-None-Match'], isNull);

    answer = (r) => r.headers['If-None-Match'] == '"abc"'
        ? http.Response('', 304)
        : http.Response('wrong', 200);
    expect(utf8.decode(await s.get('manifest.json', maxBytes: 100)), '{"v":1}');
    expect(seen.last.headers['If-None-Match'], '"abc"');
  });

  test('maps HTTP failures to FetchFailure', () async {
    Future<FetchFailure> failure() async {
      try {
        await source().get('manifest.json', maxBytes: 100);
      } on CatalogFetchException catch (e) {
        return e.failure;
      }
      fail('no exception');
    }

    answer = (_) => http.Response('', 404);
    expect(await failure(), FetchFailure.notFound);
    answer = (_) => http.Response('', 503);
    expect(await failure(), FetchFailure.server);
    answer = (_) => throw http.ClientException('no route');
    expect(await failure(), FetchFailure.offline);
  });

  test('refuses files over the size limit', () async {
    answer = (_) => http.Response('x' * 200, 200);
    expect(
      source().get('catalog.1.json', maxBytes: 100),
      throwsA(
        isA<CatalogFetchException>().having(
          (e) => e.failure,
          'failure',
          FetchFailure.tooLarge,
        ),
      ),
    );
  });
}
