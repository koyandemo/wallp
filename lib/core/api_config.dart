/// Which backend this build talks to, from the env files under `env/`:
///
/// ```sh
/// flutter run --dart-define-from-file=env/prod.json   # wallp-api.justym.me
/// flutter run --dart-define-from-file=env/local.json  # backend on this Mac
/// ```
///
/// With no env file the build uses production.
library;

import 'dart:io';

import 'app_version.dart';

/// Sent on every request: `wallp/1.0.0 (android)`.
final userAgent = 'wallp/$appVersion (${Platform.operatingSystem})';

enum ApiEnv {
  /// The real server.
  prod,

  /// `make run` in `backend/` (docs/app-client.md §7).
  local,
}

class ApiConfig {
  ApiConfig({required this.env, required String baseUrl})
    : base = _parseBase(baseUrl);

  static const defaultBase = 'https://wallp-api.justym.me';

  /// This build's config, from `--dart-define`s.
  static final current = ApiConfig.fromValues(
    env: const String.fromEnvironment('WALLP_ENV'),
    baseUrl: const String.fromEnvironment('WALLP_API_BASE'),
  );

  /// Empty values mean "not set": production, [defaultBase].
  factory ApiConfig.fromValues({required String env, required String baseUrl}) {
    final parsed = env.isEmpty
        ? ApiEnv.prod
        : ApiEnv.values.asNameMap()[env] ??
              (throw ArgumentError.value(
                env,
                'WALLP_ENV',
                'not one of '
                    '${ApiEnv.values.map((e) => e.name).join(', ')}',
              ));
    return ApiConfig(
      env: parsed,
      baseUrl: baseUrl.isEmpty ? defaultBase : baseUrl,
    );
  }

  final ApiEnv env;

  /// The server root, always ending in `/`.
  final Uri base;

  /// The public catalog files (docs/app-client.md §2).
  Uri get catalogBase => base.resolve('catalog/v1/');

  /// Events and accounts (docs/app-client.md §3, §4).
  Uri get apiBase => base.resolve('v1/');

  /// For Developer settings: "prod · https://wallp-api.justym.me".
  String get label =>
      '${env.name} · ${base.toString().replaceAll(RegExp(r'/$'), '')}';

  static Uri _parseBase(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      throw ArgumentError.value(url, 'WALLP_API_BASE', 'not an http(s) URL');
    }
    return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
  }
}
