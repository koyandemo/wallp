/// Where the wallp backend lives (docs/app-api.md §1). One server serves
/// both the public catalog (`/catalog/v1/`) and the app API (`/v1/`).
///
/// Set at build time from an env file:
///
/// ```sh
/// flutter run --dart-define-from-file=env/prod.json    # production
/// flutter run --dart-define-from-file=env/local.json   # make run, emulator
/// ```
///
/// Without one, builds talk to production.
class ApiConfig {
  const ApiConfig(this.baseUrl);

  static const production = 'https://wallp-api.justym.me';

  /// From `API_BASE_URL` in the env file.
  static const current = ApiConfig(
    String.fromEnvironment('API_BASE_URL', defaultValue: production),
  );

  /// e.g. `https://wallp-api.justym.me`, with or without a trailing slash.
  final String baseUrl;

  Uri _join(String path) {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(base).resolve(path);
  }

  /// `<base>/catalog/v1/<path>`.
  Uri catalog(String path) => _join('catalog/v1/$path');

  /// `<base>/v1/<path>`.
  Uri api(String path) => _join('v1/$path');

  @override
  String toString() => baseUrl;
}
