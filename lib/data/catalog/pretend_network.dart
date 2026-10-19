import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'catalog_source.dart';

/// How the pretend network behaves. Developer settings switch between the
/// presets; tests build their own.
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

  /// Download speed; null = as fast as the real source.
  final int? bytesPerSecond;
  final bool offline;

  /// Chance (0–1) that any one request fails with a server error.
  final double failureRate;

  /// Flip a byte in every downloaded asset, so its hash check fails.
  final bool corrupt;

  /// Cut the connection after this share (0–1) of a file has arrived, to
  /// test downloads that fail half way.
  final double? dropAfter;

  /// Nothing changed: the real source as it is.
  bool get isReal =>
      latency == Duration.zero &&
      bytesPerSecond == null &&
      !offline &&
      failureRate == 0 &&
      !corrupt &&
      dropAfter == null;

  static const fast = NetworkConditions();

  /// Phone on a weak mobile signal: 600 ms to start, 64 KB/s.
  static const slow = NetworkConditions(
    latency: Duration(milliseconds: 600),
    bytesPerSecond: 64 * 1024,
  );

  static const offlineNow = NetworkConditions(
    latency: Duration(milliseconds: 150),
    offline: true,
  );

  /// One request in three fails.
  static const flaky = NetworkConditions(
    latency: Duration(milliseconds: 300),
    bytesPerSecond: 256 * 1024,
    failureRate: 1 / 3,
  );

  static const presets = {
    'fast': fast,
    'slow': slow,
    'offline': offlineNow,
    'flaky': flaky,
  };
}

/// Puts [inner] behind a pretend network ([conditions]): Developer
/// settings' "Pretend network" over the real server, and the tests' mock
/// CDN. With [NetworkConditions.fast] it passes [inner] straight through.
class PretendNetworkSource extends CatalogSource {
  PretendNetworkSource(
    this.inner, {
    NetworkConditions Function()? conditions,
    Random? random,
  }) : _conditions = conditions ?? (() => NetworkConditions.fast),
       _random = random ?? Random();

  final CatalogSource inner;
  final NetworkConditions Function() _conditions;
  final Random _random;

  static const chunkSize = 16 * 1024;

  /// Biggest file read whole to slow, cut or corrupt it (theme-api.md §8).
  static const _maxBytes = 10 * 1024 * 1024;

  /// How many times each path was requested; tests use it to check caching.
  final requests = <String, int>{};

  @override
  Stream<List<int>> open(String path) async* {
    CatalogSource.checkPath(path);
    requests.update(path, (n) => n + 1, ifAbsent: () => 1);
    final c = _conditions();
    if (c.isReal) {
      yield* inner.open(path);
      return;
    }
    if (c.latency > Duration.zero) await Future<void>.delayed(c.latency);
    if (c.offline) {
      throw CatalogFetchException(FetchFailure.offline, path);
    }
    if (c.failureRate > 0 && _random.nextDouble() < c.failureRate) {
      throw CatalogFetchException(FetchFailure.server, path, 'HTTP 503');
    }

    var bytes = await inner.get(path, maxBytes: _maxBytes);
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
