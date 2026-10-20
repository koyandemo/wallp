import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../catalog/catalog.dart';
import '../../core/app_version.dart' as build;
import '../../core/clock.dart';
import 'built_in_catalog.dart';
import 'catalog_source.dart';
import 'catalog_store.dart';

/// Where the catalog on screen came from.
enum CatalogOrigin {
  /// Shipped in the app: first launch with no internet.
  builtIn,

  /// Saved on the phone from an earlier refresh.
  cache,

  /// Downloaded during this run.
  network,
}

enum RefreshOutcome {
  /// A new catalog version was downloaded and is now on screen.
  updated,

  /// The server has the same version we already show.
  upToDate,

  /// The server's catalog uses a newer format; we keep ours.
  unsupported,

  /// Something failed ([CatalogRepository.lastError]); we keep ours.
  failed,
}

/// The theme catalog for the whole app (docs/theme-api.md §7.2):
///
/// 1. [start] shows the saved catalog at once, or the built-in one on a
///    first launch, then refreshes in the background.
/// 2. [refresh] reads `manifest.json` and downloads the catalog only when
///    its version changed, checking size and sha256 before trusting it.
///    Any failure keeps the catalog already on screen.
/// 3. [theme] loads a theme's full file when its detail page opens, from
///    memory, the phone, the network, or the built-in copy, in that order.
///
/// Themes this build can't draw, or that need a newer app, are hidden.
class CatalogRepository extends ChangeNotifier {
  CatalogRepository({
    required this._source,
    required CatalogStore store,
    AssetBundle? bundle,
    this.engines = supportedEngines,
    this.appVersion = build.appVersion,
    this.clock = const SystemClock(),
    this.timeout = const Duration(seconds: 20),
  }) : _store = _ForgivingStore(store),
       _builtIn = BuiltInCatalog(bundle: bundle);

  /// Scene engines this build draws.
  static const supportedEngines = {...EngineIds.builtIn, EngineIds.layers};

  // Size limits from theme-api.md §8.
  static const maxManifestBytes = 16 * 1024;
  static const maxCatalogBytes = 2 * 1024 * 1024;
  static const maxThemeBytes = 512 * 1024;

  static const builtInDir = BuiltInCatalog.dir;

  // Saved under fixed names; the manifest says which version they are.
  static const _manifestKey = 'manifest.json';
  static const _catalogKey = 'catalog.json';

  final CatalogSource _source;
  final CatalogStore _store;
  final BuiltInCatalog _builtIn;
  final Set<String> engines;
  final String appVersion;
  final Clock clock;

  /// Per request. The pretend "slow" network still fits comfortably.
  final Duration timeout;

  Catalog? _raw;
  Catalog? _visible;
  Catalog? _shipped;
  Manifest? _manifest;
  CatalogOrigin? _origin;

  bool _refreshing = false;
  Future<RefreshOutcome>? _inFlight;
  Object? _lastError;
  DateTime? _lastCheckedAt;
  bool _updateRecommended = false;
  bool _schemaTooNew = false;
  int _hiddenForUpdate = 0;

  final _details = <String, ThemeDetail>{};
  final _detailLoads = <String, Future<ThemeDetail>>{};

  bool get isReady => _visible != null;

  /// What the store shows. Call [start] first.
  Catalog get catalog =>
      _visible ?? (throw StateError('CatalogRepository.start() not called'));

  CatalogOrigin? get origin => _origin;

  /// The catalog shipped inside the app, once read: what gets the APP
  /// badge. Null until then, or if the bundle has none.
  Catalog? get shipped => _shipped;

  /// Version on screen; `built-in` before the first successful refresh.
  String? get catalogVersion => _raw?.catalogVersion;

  bool get isRefreshing => _refreshing;

  /// Why the last refresh failed, or null if it worked.
  Object? get lastError => _lastError;
  DateTime? get lastCheckedAt => _lastCheckedAt;

  /// The server asks for a newer app: show "Update wallp to get new
  /// themes", but keep working.
  bool get updateRecommended => _updateRecommended || _schemaTooNew;

  /// Themes hidden because they need a newer app.
  int get hiddenForUpdate => _hiddenForUpdate;

  /// Shows the saved or built-in catalog, then (unless [refresh] is false)
  /// starts a background refresh. Returns once something is on screen.
  Future<void> start({bool refresh = true}) async {
    unawaited(_loadShipped());
    if (!isReady) await _loadLocal();
    if (refresh) unawaited(this.refresh());
  }

  /// Deletes every saved catalog file and goes back to the built-in
  /// catalog, as on a fresh install. For Developer settings and tests.
  Future<void> forgetSaved() async {
    await _inFlight;
    for (final path in [
      _manifestKey,
      _catalogKey,
      ...await _store.list('themes/'),
    ]) {
      await _store.delete(path);
    }
    _details.clear();
    _lastError = null;
    _lastCheckedAt = null;
    _schemaTooNew = false;
    _show(await _loadBuiltIn(), null, CatalogOrigin.builtIn);
    notifyListeners();
  }

  Future<RefreshOutcome> refresh() =>
      _inFlight ??= _refresh().whenComplete(() => _inFlight = null);

  Future<void> _loadLocal() async {
    final saved = await _readSaved();
    if (saved != null) {
      _show(saved.$2, saved.$1, CatalogOrigin.cache);
    } else {
      _show(await _loadBuiltIn(), null, CatalogOrigin.builtIn);
    }
  }

  /// The saved catalog, if it's intact and still readable by this build.
  Future<(Manifest, Catalog)?> _readSaved() async {
    try {
      final manifestBytes = await _store.read(_manifestKey);
      final catalogBytes = await _store.read(_catalogKey);
      if (manifestBytes == null || catalogBytes == null) return null;
      final manifest = Manifest.fromJson(
        JsonReader.of(jsonDecode(utf8.decode(manifestBytes)), 'manifest'),
      );
      if (sha256.convert(catalogBytes).toString() != manifest.catalogSha256) {
        throw const FormatException('saved catalog is damaged');
      }
      return (manifest, _parseCatalog(catalogBytes, manifest));
    } on Object catch (e) {
      // Damaged or from a newer format: forget it and start over.
      debugPrint('Ignoring saved catalog: $e');
      await _store.delete(_manifestKey);
      await _store.delete(_catalogKey);
      return null;
    }
  }

  Future<Catalog> _loadBuiltIn() async => _shipped = await _builtIn.catalog();

  /// Not awaited by [start]: the badges can wait, the store can't.
  Future<void> _loadShipped() async {
    if (_shipped != null) return;
    try {
      _shipped = await _builtIn.catalog();
      notifyListeners();
    } on Object catch (e) {
      debugPrint('No built-in catalog for APP badges: $e');
    }
  }

  Catalog _parseCatalog(Uint8List bytes, Manifest manifest) {
    final catalog = Catalog.fromJson(
      JsonReader.of(jsonDecode(utf8.decode(bytes)), 'catalog'),
    );
    if (catalog.catalogVersion != manifest.catalogVersion) {
      throw CatalogFormatException(
        'catalog.catalogVersion',
        'is ${catalog.catalogVersion}, manifest says ${manifest.catalogVersion}',
      );
    }
    return catalog;
  }

  void _show(Catalog raw, Manifest? manifest, CatalogOrigin origin) {
    _raw = raw;
    _manifest = manifest;
    _origin = origin;
    _updateRecommended =
        manifest != null &&
        !build.meetsVersion(manifest.minAppVersion, appVersion);
    final supported = raw.supportedBy(engines);
    final visible = supported.filtered(
      theme: (t) => build.meetsVersion(t.minAppVersion, appVersion),
      wallpaper: (w) => build.meetsVersion(w.minAppVersion, appVersion),
    );
    _hiddenForUpdate = supported.themes.length - visible.themes.length;
    _visible = visible;
    for (final issue in raw.issues) {
      debugPrint('Catalog ${raw.catalogVersion}: skipped $issue');
    }
  }

  Future<RefreshOutcome> _refresh() async {
    _refreshing = true;
    notifyListeners();
    try {
      final manifestBytes = await _fetch(_manifestKey, maxManifestBytes);
      final Manifest manifest;
      try {
        manifest = Manifest.fromJson(
          JsonReader.of(jsonDecode(utf8.decode(manifestBytes)), 'manifest'),
        );
      } on UnsupportedSchemaException catch (e) {
        _schemaTooNew = true;
        _lastError = e;
        return RefreshOutcome.unsupported;
      }
      _schemaTooNew = false;
      _lastError = null;

      if (manifest.catalogVersion == _manifest?.catalogVersion) {
        _updateRecommended = !build.meetsVersion(
          manifest.minAppVersion,
          appVersion,
        );
        return RefreshOutcome.upToDate;
      }

      final bytes = await _fetch(manifest.catalog, maxCatalogBytes);
      if (sha256.convert(bytes).toString() != manifest.catalogSha256) {
        throw CatalogFetchException(
          FetchFailure.integrity,
          manifest.catalog,
          'sha256 does not match manifest',
        );
      }
      final catalog = _parseCatalog(bytes, manifest);

      // Catalog first, manifest last, like publishing: a crash in between
      // leaves a mismatch that _readSaved() detects and discards.
      await _store.write(_catalogKey, bytes);
      await _store.write(_manifestKey, manifestBytes);
      _show(catalog, manifest, CatalogOrigin.network);
      unawaited(_pruneThemes(catalog));
      return RefreshOutcome.updated;
    } on Object catch (e) {
      _lastError = e;
      debugPrint('Catalog refresh failed: $e');
      return RefreshOutcome.failed;
    } finally {
      _refreshing = false;
      _lastCheckedAt = clock.now();
      notifyListeners();
    }
  }

  Future<Uint8List> _fetch(String path, int maxBytes) => _source
      .get(path, maxBytes: maxBytes)
      .timeout(
        timeout,
        onTimeout: () =>
            throw CatalogFetchException(FetchFailure.timeout, path),
      );

  /// Saved theme files the new catalog no longer lists (removed, or an
  /// older rev). The applied theme survives separately as a snapshot.
  Future<void> _pruneThemes(Catalog catalog) async {
    final keep = {for (final t in catalog.themes) _themeKey(t.id, t.rev)};
    for (final path in await _store.list('themes/')) {
      if (!keep.contains(path)) await _store.delete(path);
    }
    _details.removeWhere((key, _) => !keep.contains(key));
  }

  static String _themeKey(String id, int rev) => 'themes/$id.$rev.json';

  /// The full theme, already loaded, or null.
  ThemeDetail? cachedTheme(String id) {
    final t = _visible?.theme(id);
    return t == null ? null : _details[_themeKey(t.id, t.rev)];
  }

  /// The full theme if it's in memory or saved on the phone; never
  /// downloads. For lists that must work offline (Downloads in Me).
  Future<ThemeDetail?> savedTheme(String id) async {
    final summary = _visible?.theme(id);
    if (summary == null) return null;
    final key = _themeKey(summary.id, summary.rev);
    final done = _details[key];
    if (done != null) return done;
    final saved = await _store.read(key);
    if (saved == null) return _builtIn.theme(id);
    try {
      return _details[key] = _parseTheme(saved, summary);
    } on Object {
      return null;
    }
  }

  /// The full theme for [id]'s detail page. Throws [ThemeUnavailableException]
  /// when it isn't listed, or can't be loaded from anywhere.
  Future<ThemeDetail> theme(String id) {
    final summary = _visible?.theme(id);
    if (summary == null) {
      return Future.error(ThemeUnavailableException(id, notListed: true));
    }
    final key = _themeKey(summary.id, summary.rev);
    final done = _details[key];
    if (done != null) return SynchronousFuture(done);
    return _detailLoads[key] ??= _loadTheme(summary, key)
        .then((t) {
          _details[key] = t;
          return t;
        })
        // A block body: `=> remove(key)` would return this very future,
        // and whenComplete would wait for it forever.
        .whenComplete(() {
          _detailLoads.remove(key);
        });
  }

  Future<ThemeDetail> _loadTheme(ThemeSummary summary, String key) async {
    final saved = await _store.read(key);
    if (saved != null) {
      try {
        return _parseTheme(saved, summary);
      } on Object catch (e) {
        debugPrint('Ignoring saved $key: $e');
        await _store.delete(key);
      }
    }
    Object? cause;
    try {
      final bytes = await _fetch(key, maxThemeBytes);
      final theme = _parseTheme(bytes, summary);
      await _store.write(key, bytes);
      return theme;
    } on Object catch (e) {
      cause = e;
    }
    // Offline: a built-in theme still opens, even if a newer rev exists.
    final builtIn = await _builtIn.theme(summary.id);
    if (builtIn != null) return builtIn;
    throw ThemeUnavailableException(summary.id, cause: cause);
  }

  ThemeDetail _parseTheme(Uint8List bytes, ThemeSummary summary) {
    final theme = ThemeDetail.fromJson(
      JsonReader.of(jsonDecode(utf8.decode(bytes)), summary.id),
    );
    if (theme.id != summary.id || theme.rev != summary.rev) {
      throw CatalogFormatException(
        summary.id,
        'file is ${theme.id} rev ${theme.rev}, catalog lists rev ${summary.rev}',
      );
    }
    return theme;
  }
}

class ThemeUnavailableException implements Exception {
  const ThemeUnavailableException(
    this.id, {
    this.cause,
    this.notListed = false,
  });

  final String id;

  /// What went wrong loading it, usually a [CatalogFetchException].
  final Object? cause;

  /// The catalog on screen doesn't list it (removed, or hidden here).
  final bool notListed;

  bool get isOffline =>
      cause is CatalogFetchException &&
      (cause! as CatalogFetchException).failure == FetchFailure.offline;

  @override
  String toString() =>
      'ThemeUnavailableException: $id${notListed ? ' (not listed)' : ''}'
      '${cause == null ? '' : ': $cause'}';
}

/// Saving is only a speed-up: a full disk or missing storage must never
/// stop the store from opening. Failed reads count as "nothing saved",
/// failed writes are logged and skipped.
class _ForgivingStore implements CatalogStore {
  _ForgivingStore(this._inner);

  final CatalogStore _inner;

  Future<T> _try<T>(String what, Future<T> Function() run, T orElse) async {
    try {
      return await run();
    } on Object catch (e) {
      debugPrint('Catalog store: $what failed: $e');
      return orElse;
    }
  }

  @override
  Future<Uint8List?> read(String path) =>
      _try('read $path', () => _inner.read(path), null);

  @override
  Future<void> write(String path, List<int> bytes) =>
      _try('write $path', () => _inner.write(path, bytes), null);

  @override
  Future<void> delete(String path) =>
      _try('delete $path', () => _inner.delete(path), null);

  @override
  Future<List<String>> list(String prefix) =>
      _try('list $prefix', () => _inner.list(prefix), const <String>[]);
}
