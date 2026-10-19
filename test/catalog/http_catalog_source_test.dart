import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallp/data/catalog/catalog_repository.dart';
import 'package:wallp/data/catalog/catalog_source.dart';
import 'package:wallp/data/catalog/catalog_store.dart';
import 'package:wallp/data/catalog/http_catalog_source.dart';
import 'package:wallp/data/catalog/pretend_network.dart';

import 'fakes.dart';

final _base = Uri.parse('https://wallp-api.justym.me/catalog/v1/');

/// Serves [mockDir] from disk like the real server.
MockClient _diskServer({List<Uri>? seen}) => MockClient((request) async {
  seen?.add(request.url);
  final path = request.url.path.replaceFirst('/catalog/v1/', '');
  final file = File('$mockDir/$path');
  if (!file.existsSync()) return http.Response('404 page not found', 404);
  return http.Response.bytes(await file.readAsBytes(), 200);
});

HttpCatalogSource _source(http.Client client, {Duration? idle}) =>
    HttpCatalogSource(
      base: _base,
      client: client,
      connectTimeout: const Duration(milliseconds: 200),
      idleTimeout: idle ?? const Duration(milliseconds: 200),
    );

Matcher _fails(FetchFailure f) => throwsA(
  isA<CatalogFetchException>().having((e) => e.failure, 'failure', f),
);

void main() {
  group('HttpCatalogSource', () {
    test('fetches under the catalog base with a User-Agent', () async {
      final seen = <http.BaseRequest>[];
      final source = _source(
        MockClient((r) async {
          seen.add(r);
          return http.Response('{}', 200);
        }),
      );
      final bytes = await source.get('manifest.json', maxBytes: 1024);
      expect(utf8.decode(bytes), '{}');
      expect(
        seen.single.url.toString(),
        'https://wallp-api.justym.me/catalog/v1/manifest.json',
      );
      expect(seen.single.headers['User-Agent'], startsWith('wallp/'));
    });

    test('maps status codes', () async {
      Future<void> check(int status, FetchFailure f) => expectLater(
        _source(MockClient((_) async => http.Response('', status)))
            .get('manifest.json', maxBytes: 1024),
        _fails(f),
      );
      await check(404, FetchFailure.notFound);
      await check(503, FetchFailure.server);
      await check(401, FetchFailure.server);
    });

    test('no connection is offline', () {
      final source = _source(
        MockClient((_) => throw const SocketException('Failed host lookup')),
      );
      expect(
        source.get('manifest.json', maxBytes: 1024),
        _fails(FetchFailure.offline),
      );
    });

    test('no answer is a timeout', () {
      final source = _source(
        MockClient((_) => Completer<http.Response>().future),
      );
      expect(
        source.get('manifest.json', maxBytes: 1024),
        _fails(FetchFailure.timeout),
      );
    });

    test('a body that stops is a timeout', () {
      final source = _source(
        MockClient.streaming((_, _) async {
          final body = StreamController<List<int>>()..add([1, 2, 3]);
          return http.StreamedResponse(body.stream, 200);
        }),
      );
      expect(
        source.get('assets/x.png', maxBytes: 1024),
        _fails(FetchFailure.timeout),
      );
    });

    test('too big is refused', () {
      final source = _source(
        MockClient((_) async => http.Response.bytes(List.filled(2048, 0), 200)),
      );
      expect(
        source.get('manifest.json', maxBytes: 1024),
        _fails(FetchFailure.tooLarge),
      );
    });

    test('bad paths never reach the network', () async {
      final seen = <Uri>[];
      final source = _source(_diskServer(seen: seen));
      for (final path in ['../secret', '/manifest.json', 'themes//x.json']) {
        await expectLater(
          source.get(path, maxBytes: 1024),
          _fails(FetchFailure.notFound),
        );
      }
      expect(seen, isEmpty);
    });

    test('a connection dropped mid-body is a server failure', () {
      final source = _source(
        MockClient.streaming((_, _) async {
          final body = StreamController<List<int>>()
            ..add([1, 2, 3])
            ..addError(const SocketException('Connection reset'));
          return http.StreamedResponse(body.stream, 200);
        }),
      );
      expect(
        source.get('assets/x.png', maxBytes: 1024),
        _fails(FetchFailure.server),
      );
    });
  });

  group('Developer settings over the real server', () {
    test('fast passes straight through', () async {
      final seen = <Uri>[];
      final source = PretendNetworkSource(_source(_diskServer(seen: seen)));
      final bytes = await source.get('manifest.json', maxBytes: 16384);
      expect(bytes, isNotEmpty);
      expect(seen, hasLength(1));
      await expectLater(
        source.get('nope.json', maxBytes: 1024),
        _fails(FetchFailure.notFound),
      );
    });

    test('offline never reaches the server', () async {
      final seen = <Uri>[];
      final source = PretendNetworkSource(
        _source(_diskServer(seen: seen)),
        conditions: () => const NetworkConditions(offline: true),
      );
      await expectLater(
        source.get('manifest.json', maxBytes: 16384),
        _fails(FetchFailure.offline),
      );
      expect(seen, isEmpty);
    });

    test('corrupt flips an asset byte from the server', () async {
      final path = File(
        Directory('$mockDir/assets').listSync().whereType<File>().first.path,
      ).uri.pathSegments.last;
      final real = await File('$mockDir/assets/$path').readAsBytes();
      final source = PretendNetworkSource(
        _source(_diskServer()),
        conditions: () => const NetworkConditions(corrupt: true),
      );
      final got = await source.get('assets/$path', maxBytes: 10 << 20);
      expect(got.length, real.length);
      expect(got.last, isNot(real.last));
    });
  });

  test('CatalogRepository downloads the catalog over HTTP', () async {
    final repo = CatalogRepository(
      source: _source(_diskServer()),
      store: MemoryCatalogStore(),
      bundle: DiskBundle(),
    );
    await repo.start(refresh: false);
    expect(await repo.refresh(), RefreshOutcome.updated);
    expect(repo.origin, CatalogOrigin.network);
    final first = repo.catalog.themes.first;
    expect((await repo.theme(first.id)).id, first.id);
  });
}
