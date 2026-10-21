import 'dart:async';

import '../../data/assets/asset_cache.dart';
import '../../data/assets/download_manager.dart';
import '../../data/catalog/catalog_repository.dart';
import '../../render/font_registry.dart';

/// Every font the catalog lists, downloaded from the API and loaded, so
/// store previews draw in them before anything is applied. Fonts come
/// only from the catalog: nothing from google_fonts or the app bundle.
///
/// Runs whenever the catalog on screen changes. The files are pinned, so
/// clean-ups don't delete them; a new catalog replaces the pin.
class CatalogFonts {
  CatalogFonts({
    required this.catalog,
    required this.downloads,
    required this.cache,
    FontRegistry? registry,
  }) : registry = registry ?? FontRegistry.shared {
    catalog.addListener(_sync);
    _sync();
  }

  static const pinOwner = 'catalog-fonts';

  final CatalogRepository catalog;
  final DownloadManager downloads;
  final AssetCache cache;
  final FontRegistry registry;

  /// The font files last synced, so unrelated catalog changes are free.
  Set<String>? _synced;
  Future<void>? _running;

  /// Done once the current catalog's fonts are on the phone and loaded
  /// (or failed: the next catalog change tries again).
  Future<void> get idle => _running ?? Future.value();

  void _sync() {
    if (!catalog.isReady) return;
    final fonts = catalog.catalog.fonts;
    final files = [
      for (final f in fonts)
        for (final file in f.files) file.asset,
    ];
    final key = {for (final r in files) r.sha256};
    if (_synced != null &&
        _synced!.length == key.length &&
        _synced!.containsAll(key)) {
      return;
    }
    _synced = key;
    final previous = _running ?? Future.value();
    _running = previous.then((_) async {
      final ok = await downloads.prefetch(files);
      // Forget this set if something's missing, so it's tried again.
      if (!ok) _synced = null;
      await cache.pin(pinOwner, files);
      await registry.ensureAll(fonts);
    });
  }

  void dispose() => catalog.removeListener(_sync);
}
