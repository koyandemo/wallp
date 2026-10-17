import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// The phone's copy of catalog JSON files, so the store opens instantly and
/// works offline. Keys are catalog paths: `manifest.json`,
/// `catalog.json`, `themes/spider-night.3.json`.
///
/// Downloaded assets (images, fonts) get their own cache in Phase 5; this
/// only holds the small JSON files.
abstract class CatalogStore {
  Future<Uint8List?> read(String path);

  /// Replaces the file in one step: readers see the old or the new file,
  /// never half of one.
  Future<void> write(String path, List<int> bytes);

  Future<void> delete(String path);

  /// Every stored path under [prefix], e.g. `themes/`.
  Future<List<String>> list(String prefix);
}

class FileCatalogStore implements CatalogStore {
  FileCatalogStore(Directory root) : _root = Future.value(root);

  /// `<app support>/catalog/v1`, found on first use. Not the cache
  /// directory: Android may clear that at any time, and wallp Home needs
  /// these files after a reboot.
  FileCatalogStore.appSupport()
    : _root =
          getApplicationSupportDirectory().then(
              (base) => Directory('${base.path}/catalog/v1'),
            )
            // See AssetCache.appSupport: report to callers, not as uncaught.
            ..ignore();

  final Future<Directory> _root;

  Future<File> _file(String path) async {
    if (path.split('/').any((s) => s == '..' || s.isEmpty)) {
      throw ArgumentError.value(path, 'path');
    }
    return File('${(await _root).path}/$path');
  }

  @override
  Future<Uint8List?> read(String path) async {
    final file = await _file(path);
    try {
      return await file.readAsBytes();
    } on PathNotFoundException {
      return null;
    }
  }

  @override
  Future<void> write(String path, List<int> bytes) async {
    final file = await _file(path);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.part');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<void> delete(String path) async {
    try {
      await (await _file(path)).delete();
    } on PathNotFoundException {
      // Already gone.
    }
  }

  @override
  Future<List<String>> list(String prefix) async {
    final dir = Directory('${(await _root).path}/$prefix');
    if (!await dir.exists()) return const [];
    return [
      await for (final e in dir.list())
        if (e is File && !e.path.endsWith('.part'))
          '$prefix${e.uri.pathSegments.last}',
    ];
  }
}

class MemoryCatalogStore implements CatalogStore {
  final files = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String path) async => files[path];

  @override
  Future<void> write(String path, List<int> bytes) async =>
      files[path] = Uint8List.fromList(bytes);

  @override
  Future<void> delete(String path) async => files.remove(path);

  @override
  Future<List<String>> list(String prefix) async => [
    for (final p in files.keys)
      if (p.startsWith(prefix)) p,
  ];
}
