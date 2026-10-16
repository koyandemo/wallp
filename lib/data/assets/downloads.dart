import '../../catalog/catalog.dart';
import '../../look/applied_look.dart';
import '../catalog/catalog_repository.dart';
import 'asset_cache.dart';

/// A theme whose files are all on the phone (Me › Downloads).
class DownloadedTheme {
  const DownloadedTheme({
    required this.theme,
    required this.files,
    required this.bytes,
    required this.isApplied,
  });

  final ThemeSummary theme;
  final List<AssetRef> files;

  /// Space its files take (some may be shared with other themes).
  final int bytes;

  /// The applied theme can't be deleted: wallp Home needs it.
  final bool isApplied;
}

/// Dashboard themes that are fully downloaded, biggest first. Works offline:
/// only themes whose file was opened before are listed.
Future<List<DownloadedTheme>> downloadedThemes({
  required CatalogRepository catalog,
  required AssetCache cache,
  AppliedLook? applied,
}) async {
  final out = <DownloadedTheme>[];
  for (final summary in catalog.catalog.themes) {
    if (summary.isBuiltIn) continue;
    final detail = await catalog.savedTheme(summary.id);
    if (detail == null) continue;
    final List<AssetRef> files;
    try {
      files = catalog.catalog.assetsFor(detail);
    } on StateError {
      continue;
    }
    if (files.isEmpty || (await cache.missing(files)).isNotEmpty) continue;
    out.add(
      DownloadedTheme(
        theme: summary,
        files: files,
        bytes: files.fold(0, (s, f) => s + f.bytes),
        isApplied: applied?.theme.id == summary.id,
      ),
    );
  }
  return out..sort((a, b) => b.bytes.compareTo(a.bytes));
}

/// Deletes a downloaded theme's files, keeping any the applied look (or a
/// pending apply) still uses. Returns the bytes freed.
Future<int> deleteDownload(DownloadedTheme download, AssetCache cache) =>
    cache.deleteUnpinned(download.files);
