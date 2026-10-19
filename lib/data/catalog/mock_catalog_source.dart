import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import 'catalog_source.dart';
import 'pretend_network.dart';

export 'pretend_network.dart' show NetworkConditions;

/// Serves the mock catalog under `assets/mock/catalog/v1/` as if it were
/// the CDN, through a pretend network ([conditions]).
///
/// For tests and tools only: the mock catalog isn't in the app's bundle
/// any more, so pass a [bundle] that reads it from disk.
class MockCatalogSource extends PretendNetworkSource {
  MockCatalogSource({
    required AssetBundle bundle,
    super.conditions,
    super.random,
    String root = 'assets/mock/catalog/v1/',
  }) : super(BundleCatalogSource(bundle, root));

  static const chunkSize = PretendNetworkSource.chunkSize;
}

/// Catalog files from an [AssetBundle], all at once.
class BundleCatalogSource extends CatalogSource {
  BundleCatalogSource(this.bundle, this.root);

  final AssetBundle bundle;
  final String root;

  @override
  Stream<List<int>> open(String path) async* {
    CatalogSource.checkPath(path);
    Uint8List bytes;
    try {
      final data = await bundle.load('$root$path');
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Object {
      // The bundle throws FlutterError or a plain Exception, by version.
      throw CatalogFetchException(FetchFailure.notFound, path, 'HTTP 404');
    }
    for (var start = 0; start < bytes.length; start += _chunk) {
      yield bytes.sublist(start, min(start + _chunk, bytes.length));
    }
  }

  static const _chunk = PretendNetworkSource.chunkSize;
}
