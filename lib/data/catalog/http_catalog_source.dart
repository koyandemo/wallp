import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';
import 'catalog_source.dart';

/// The real catalog: `GET <base>/catalog/v1/<path>` (docs/app-client.md §2).
///
/// Only fetches and maps failures to [FetchFailure]; size limits, sha256
/// checks and caching stay in CatalogRepository and AssetCache.
class HttpCatalogSource extends CatalogSource {
  HttpCatalogSource({
    required this.base,
    http.Client? client,
    this.connectTimeout = const Duration(seconds: 15),
    this.idleTimeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  /// `.../catalog/v1/`, ending in `/`.
  final Uri base;
  final http.Client _client;

  /// Until the response headers arrive.
  final Duration connectTimeout;

  /// Longest gap between two chunks of the body.
  final Duration idleTimeout;

  @override
  Stream<List<int>> open(String path) async* {
    CatalogSource.checkPath(path);
    final request = http.Request('GET', base.resolve(path))
      ..headers['User-Agent'] = userAgent;

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(connectTimeout);
    } on TimeoutException {
      throw CatalogFetchException(FetchFailure.timeout, path);
    } on SocketException catch (e) {
      throw CatalogFetchException(FetchFailure.offline, path, e.message);
    } on http.ClientException catch (e) {
      throw CatalogFetchException(FetchFailure.server, path, e.message);
    } on HandshakeException catch (e) {
      throw CatalogFetchException(FetchFailure.server, path, e.message);
    }

    final status = response.statusCode;
    if (status != 200) {
      // Drain so the connection can be reused.
      unawaited(response.stream.drain<void>().catchError((_) {}));
      throw CatalogFetchException(
        status == 404 ? FetchFailure.notFound : FetchFailure.server,
        path,
        'HTTP $status',
      );
    }

    // `await for`, not `yield*`: errors from a yield* stream skip this catch.
    try {
      await for (final chunk in response.stream.timeout(idleTimeout)) {
        yield chunk;
      }
    } on TimeoutException {
      throw CatalogFetchException(FetchFailure.timeout, path, 'stalled');
    } on SocketException catch (e) {
      throw CatalogFetchException(FetchFailure.server, path, e.message);
    } on http.ClientException catch (e) {
      throw CatalogFetchException(FetchFailure.server, path, e.message);
    }
  }

  void close() => _client.close();
}
