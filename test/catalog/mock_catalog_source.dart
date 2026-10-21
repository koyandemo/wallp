import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import 'package:wallp/data/catalog/catalog_source.dart';

/// How the pretend network behaves in tests.
class NetworkConditions {
  const NetworkConditions({
    this.latency = Duration.zero,
    this.bytesPerSecond,
    this.offline = false,
    this.failureRate = 0,
    this.corrupt = false,
    this.dropAfter,
  }) : assert(failureRate >= 0 && failureRate <= 1);

  /// Wait before the first byte.
  final Duration latency;

  /// Download speed; null = as fast as the bundle reads.
  final int? bytesPerSecond;
  final bool offline;

  /// Chance (0–1) that any one request fails with a server error.
  final double failureRate;

  /// Flip a byte in every downloaded asset, so its hash check fails.
  final bool corrupt;

  /// Cut the connection after this share (0–1) of a file has arrived, to
  /// test downloads that fail half way.
  final double? dropAfter;

  static const fast = NetworkConditions();

  static const offlineNow = NetworkConditions(
    latency: Duration(milliseconds: 150),
    offline: true,
  );
}

/// Serves the test catalog under `assets/mock/catalog/v1/` as if it were
/// the CDN, through a pretend network ([conditions]). Tests only: the app
/// always reads the API.
class MockCatalogSource extends CatalogSource {
  MockCatalogSource({
    AssetBundle? bundle,
    NetworkConditions Function()? conditions,
    Random? random,
    this.root = 'assets/mock/catalog/v1/',
  }) : _bundle = bundle ?? rootBundle,
       _conditions = conditions ?? (() => NetworkConditions.fast),
       _random = random ?? Random();

  final AssetBundle _bundle;
  final NetworkConditions Function() _conditions;
  final Random _random;
  final String root;

  static const chunkSize = 16 * 1024;

  /// How many times each path was requested; tests use it to check caching.
  final requests = <String, int>{};

  @override
  Stream<List<int>> open(String path) async* {
    CatalogSource.checkPath(path);
    requests.update(path, (n) => n + 1, ifAbsent: () => 1);
    final c = _conditions();
    if (c.latency > Duration.zero) await Future<void>.delayed(c.latency);
    if (c.offline) {
      throw CatalogFetchException(FetchFailure.offline, path);
    }
    if (c.failureRate > 0 && _random.nextDouble() < c.failureRate) {
      throw CatalogFetchException(FetchFailure.server, path, 'HTTP 503');
    }

    Uint8List bytes;
    try {
      final data = await _bundle.load('$root$path');
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Object {
      // The bundle throws FlutterError or a plain Exception, by version.
      throw CatalogFetchException(FetchFailure.notFound, path, 'HTTP 404');
    }
    if (c.corrupt && path.startsWith('assets/') && bytes.isNotEmpty) {
      bytes = Uint8List.fromList(bytes)..[bytes.length - 1] ^= 0xFF;
    }

    final dropAt = c.dropAfter == null
        ? null
        : (bytes.length * c.dropAfter!).floor();
    for (var start = 0; start < bytes.length; start += chunkSize) {
      final end = min(start + chunkSize, bytes.length);
      if (dropAt != null && end > dropAt) {
        if (dropAt > start) yield bytes.sublist(start, dropAt);
        throw CatalogFetchException(
          FetchFailure.server,
          path,
          'connection dropped',
        );
      }
      final speed = c.bytesPerSecond;
      if (speed != null) {
        await Future<void>.delayed(
          Duration(microseconds: (end - start) * 1000000 ~/ speed),
        );
      }
      yield bytes.sublist(start, end);
    }
  }
}
