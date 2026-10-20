import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../api/api_config.dart';
import 'catalog_source.dart';

/// The real catalog: `GET <base>/catalog/v1/<path>` (docs/app-api.md §2).
///
/// Catalog, theme and asset files never change under the same name, so
/// CatalogRepository and AssetCache keep them for good. Only the manifest
/// changes: it is asked for with `If-None-Match`, and a `304` replays the
/// copy from the last `200`.
class HttpCatalogSource extends CatalogSource {
  HttpCatalogSource({this.config = ApiConfig.current, http.Client? client})
    : _http = client ?? http.Client();

  final ApiConfig config;
  final http.Client _http;

  static const _manifest = 'manifest.json';

  String? _manifestEtag;
  List<int>? _manifestBytes;

  @override
  Stream<List<int>> open(String path) async* {
    CatalogSource.checkPath(path);
    final request = http.Request('GET', config.catalog(path))
      ..headers['User-Agent'] = ApiClient.userAgent;
    final etag = path == _manifest ? _manifestEtag : null;
    if (etag != null) request.headers['If-None-Match'] = etag;

    final http.StreamedResponse response;
    try {
      response = await _http.send(request);
    } on Object catch (e) {
      throw _connectionFailure(e, path);
    }

    switch (response.statusCode) {
      case 200:
        break;
      case 304 when etag != null && _manifestBytes != null:
        await response.stream.drain<void>();
        yield _manifestBytes!;
        return;
      case 404:
        await response.stream.drain<void>();
        throw CatalogFetchException(FetchFailure.notFound, path, 'HTTP 404');
      case final status:
        await response.stream.drain<void>();
        throw CatalogFetchException(FetchFailure.server, path, 'HTTP $status');
    }

    final keep = path == _manifest ? <int>[] : null;
    try {
      await for (final chunk in response.stream) {
        keep?.addAll(chunk);
        yield chunk;
      }
    } on CatalogFetchException {
      rethrow;
    } on Object catch (e) {
      throw _connectionFailure(e, path);
    }
    if (keep != null) {
      _manifestEtag = response.headers['etag'];
      _manifestBytes = _manifestEtag == null ? null : keep;
    }
  }

  static CatalogFetchException _connectionFailure(Object e, String path) =>
      switch (e) {
        SocketException(:final message) => CatalogFetchException(
          FetchFailure.offline,
          path,
          message,
        ),
        http.ClientException(:final message) => CatalogFetchException(
          FetchFailure.offline,
          path,
          message,
        ),
        TimeoutException() => CatalogFetchException(FetchFailure.timeout, path),
        _ => CatalogFetchException(FetchFailure.server, path, '$e'),
      };
}
