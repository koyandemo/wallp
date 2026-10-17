import 'dart:async';
import 'dart:typed_data';

/// Where catalog files come from: the CDN later, the bundled mock now.
///
/// Paths are relative to the catalog base (`/catalog/v1/`), exactly as the
/// catalog writes them: `manifest.json`, `themes/spider-night.3.json`,
/// `assets/<sha256>.png`. Swapping the source is all it takes to move from
/// mock data to the real API; caching, checks and fallbacks live in
/// CatalogRepository and don't change.
abstract class CatalogSource {
  const CatalogSource();

  /// Streams a file in chunks, so downloads can report progress.
  /// Throws [CatalogFetchException] (also from inside the stream).
  Stream<List<int>> open(String path);

  /// The whole file, refusing anything over [maxBytes].
  Future<Uint8List> get(String path, {required int maxBytes}) async {
    final out = BytesBuilder(copy: false);
    await for (final chunk in open(path)) {
      out.add(chunk);
      if (out.length > maxBytes) {
        throw CatalogFetchException(
          FetchFailure.tooLarge,
          path,
          'over ${maxBytes ~/ 1024} KB',
        );
      }
    }
    return out.takeBytes();
  }

  /// Rejects paths that could escape the catalog folder.
  static void checkPath(String path) {
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains('\\') ||
        path.split('/').any((s) => s == '..' || s.isEmpty)) {
      throw CatalogFetchException(FetchFailure.notFound, path, 'bad path');
    }
  }
}

enum FetchFailure {
  /// No connection at all.
  offline,

  /// The server or connection was too slow.
  timeout,

  /// 404: the file isn't on the server.
  notFound,

  /// 5xx or a dropped connection.
  server,

  /// Bigger than the app accepts (theme-api.md §8).
  tooLarge,

  /// The bytes don't match the expected sha256.
  integrity,
}

class CatalogFetchException implements Exception {
  const CatalogFetchException(this.failure, this.path, [this.detail]);

  final FetchFailure failure;
  final String path;
  final String? detail;

  /// Worth retrying later without any change on the server.
  bool get isTransient =>
      failure == FetchFailure.offline ||
      failure == FetchFailure.timeout ||
      failure == FetchFailure.server;

  @override
  String toString() =>
      'CatalogFetchException(${failure.name}): $path'
      '${detail == null ? '' : ' ($detail)'}';
}
