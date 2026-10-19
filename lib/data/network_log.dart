import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One HTTP call, for Developer settings' network list.
class NetworkCall {
  const NetworkCall({
    required this.method,
    required this.url,
    required this.at,
    required this.duration,
    this.status,
    this.bytes,
    this.error,
  });

  final String method;
  final Uri url;
  final DateTime at;

  /// Until the response headers arrived (bodies stream after).
  final Duration duration;

  /// Null when there was no answer ([error]).
  final int? status;

  /// From `Content-Length`, when the server sent one.
  final int? bytes;
  final String? error;

  bool get failed => error != null || (status ?? 0) >= 400;

  /// `200 GET /catalog/v1/manifest.json · 120 ms · 258 B`
  @override
  String toString() =>
      '${status ?? 'ERR'} $method ${url.path}'
      '${url.hasQuery ? '?${url.query}' : ''}'
      ' · ${duration.inMilliseconds} ms'
      '${bytes == null ? '' : ' · ${sizeText(bytes!)}'}'
      '${error == null ? '' : ' · $error'}';

  static String sizeText(int b) => b < 1024
      ? '$b B'
      : b < 1024 * 1024
      ? '${(b / 1024).toStringAsFixed(1)} KB'
      : '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// The last [max] HTTP calls, newest first. Debug builds only: release
/// builds never wrap their client in [LoggingClient].
class NetworkLog extends ChangeNotifier {
  NetworkLog({this.max = 100});

  static final shared = NetworkLog();

  final int max;
  final _calls = <NetworkCall>[];

  List<NetworkCall> get calls => List.unmodifiable(_calls);

  void add(NetworkCall call) {
    _calls.insert(0, call);
    if (_calls.length > max) _calls.removeRange(max, _calls.length);
    notifyListeners();
  }

  void clear() {
    _calls.clear();
    notifyListeners();
  }
}

/// Wraps a client to log every call: one line in the console and an entry
/// in [log]. Only method, URL, status, time and size: never headers or
/// bodies, which hold tokens and passwords.
class LoggingClient extends http.BaseClient {
  LoggingClient(this._inner, {NetworkLog? log, this.printCalls = true})
    : log = log ?? NetworkLog.shared;

  final http.Client _inner;
  final NetworkLog log;
  final bool printCalls;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final at = DateTime.now();
    final watch = Stopwatch()..start();
    try {
      final response = await _inner.send(request);
      _record(
        NetworkCall(
          method: request.method,
          url: request.url,
          at: at,
          duration: watch.elapsed,
          status: response.statusCode,
          bytes: response.contentLength,
        ),
      );
      return response;
    } on Object catch (e) {
      _record(
        NetworkCall(
          method: request.method,
          url: request.url,
          at: at,
          duration: watch.elapsed,
          error: e.runtimeType.toString(),
        ),
      );
      rethrow;
    }
  }

  void _record(NetworkCall call) {
    log.add(call);
    if (printCalls) debugPrint('[net] $call');
  }

  @override
  void close() => _inner.close();
}

/// The HTTP client for the app: logged in debug builds, plain in release.
http.Client appHttpClient() =>
    kDebugMode ? LoggingClient(http.Client()) : http.Client();
