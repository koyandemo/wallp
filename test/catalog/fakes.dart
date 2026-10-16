import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:wallp/data/catalog/catalog_source.dart';
import 'package:wallp/data/catalog/mock_catalog_source.dart';

const mockDir = 'assets/mock/catalog/v1';

/// The seed manifest and catalog JSON, as decoded maps.
Map<String, dynamic> seedManifestJson() =>
    jsonDecode(File('$mockDir/manifest.json').readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> seedCatalogJson() => jsonDecode(
  File('$mockDir/${seedManifestJson()['catalog']}').readAsStringSync(),
) as Map<String, dynamic>;

/// The bundled mock catalog behind a pretend network, with any file
/// replaceable: to "publish" a new version, or to serve a damaged file.
class TamperingSource extends CatalogSource {
  TamperingSource({this.conditions = NetworkConditions.fast});

  NetworkConditions conditions;

  late final inner = MockCatalogSource(conditions: () => conditions);

  set offline(bool on) =>
      conditions = on ? NetworkConditions.offlineNow : NetworkConditions.fast;

  /// Served instead of the bundled file.
  final files = <String, Uint8List>{};

  /// Requests per path, including replaced files.
  final requests = <String, int>{};

  @override
  Stream<List<int>> open(String path) async* {
    requests.update(path, (n) => n + 1, ifAbsent: () => 1);
    final replaced = files[path];
    if (replaced == null) {
      yield* inner.open(path);
      return;
    }
    if (conditions.offline) {
      throw CatalogFetchException(FetchFailure.offline, path);
    }
    yield replaced;
  }

  /// Publishes [catalog] as version [version], with a correct manifest.
  void publish(
    Map<String, dynamic> catalog,
    String version, {
    String minAppVersion = '1.0.0',
    int schemaVersion = 1,
  }) {
    catalog['catalogVersion'] = version;
    final bytes = utf8.encode(jsonEncode(catalog));
    final name = 'catalog.$version.json';
    files[name] = Uint8List.fromList(bytes);
    files['manifest.json'] = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schemaVersion': schemaVersion,
          'catalogVersion': version,
          'catalog': name,
          'catalogSha256': sha256.convert(bytes).toString(),
          'minAppVersion': minAppVersion,
          'publishedAt': '2026-10-16T10:00:00Z',
        }),
      ),
    );
  }
}

/// Never answers; for timeout tests.
class HangingSource extends CatalogSource {
  @override
  Stream<List<int>> open(String path) => StreamController<List<int>>().stream;
}
