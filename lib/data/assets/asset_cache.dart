import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../catalog/catalog.dart';
import '../../core/clock.dart';

/// Downloaded catalog files (scene images, icon pictures, fonts) on the
/// phone, named by their sha256 like on the CDN (docs/theme-api.md §7.2).
///
/// * A file is only stored after its size and hash check out, and is
///   written to a temp file first, so a crash never leaves half a file.
/// * **Pinned** files are never deleted: the applied look's (owner
///   `applied`) and a pending apply's (`pending`). wallp Home and the live
///   wallpaper need them with no network, e.g. after a reboot.
/// * Unpinned files are kept up to [limitBytes]; past that, the least
///   recently used go first.
///
/// Only the theme store writes; the other engines just read files.
class AssetCache {
  AssetCache(Directory root, {this.limitBytes = defaultLimit, Clock? clock})
    : _root = Future.value(root),
      _clock = clock ?? const SystemClock();

  /// `<app support>/assets/v1`, found on first use. Not the OS cache
  /// directory, which Android may empty while pinned files are needed.
  AssetCache.appSupport({this.limitBytes = defaultLimit, Clock? clock})
    : _root =
          getApplicationSupportDirectory().then(
              (base) => Directory('${base.path}/assets/v1'),
            )
            // No storage (or no plugin, in tests) must not crash the app as an
            // uncaught error; whoever awaits the folder still gets the error.
            ..ignore(),
      _clock = clock ?? const SystemClock();

  /// One cache per engine: the theme store, wallp Home and the live
  /// wallpaper each read the same folder through their own instance.
  static final shared = AssetCache.appSupport();

  static const defaultLimit = 50 * 1024 * 1024;

  /// Pins held by the applied look and by a pending apply.
  static const appliedOwner = 'applied';
  static const pendingOwner = 'pending';

  /// Held while a look's files download, so a clean-up can't remove them
  /// between finishing the download and applying the look.
  static const incomingOwner = 'incoming';

  final Future<Directory> _root;
  final Clock _clock;
  final int limitBytes;

  _Index? _index;
  Future<void> _writes = Future.value();

  Future<Directory> get directory => _root;

  String _name(AssetRef ref) => '${ref.sha256}.${ref.format.name}';

  /// Where [ref] is (or would be) stored.
  Future<File> fileFor(AssetRef ref) async =>
      File('${(await _root).path}/${_name(ref)}');

  /// Whether [ref] is on disk.
  Future<bool> has(AssetRef ref) async {
    final index = await _load();
    if (!index.files.containsKey(ref.sha256)) return false;
    if (await (await fileFor(ref)).exists()) return true;
    // Deleted behind our back (storage cleared): forget it.
    index.files.remove(ref.sha256);
    return false;
  }

  /// The refs from [refs] that aren't on disk yet.
  Future<List<AssetRef>> missing(Iterable<AssetRef> refs) async => [
    for (final ref in refs.toSet())
      if (!await has(ref)) ref,
  ];

  /// Bytes still to download for [refs]: "Apply · 0.8 MB", or 0.
  Future<int> missingBytes(Iterable<AssetRef> refs) async =>
      (await missing(refs)).fold<int>(0, (sum, r) => sum + r.bytes);

  /// Opens a temp file for [ref]'s bytes. Call [IncomingFile.commit] once
  /// they're all written; it checks size and hash before keeping the file.
  Future<IncomingFile> incoming(AssetRef ref) async {
    final root = await _root;
    await root.create(recursive: true);
    final temp = File(
      '${root.path}/${_name(ref)}.${_clock.now().microsecondsSinceEpoch}.part',
    );
    return IncomingFile._(this, ref, temp, temp.openWrite());
  }

  /// Stores [bytes] as [ref] (for small files and tests).
  Future<void> put(AssetRef ref, List<int> bytes) async {
    final file = await incoming(ref);
    file.add(bytes);
    await file.commit();
  }

  Future<void> _commit(AssetRef ref, File temp) async {
    final target = await fileFor(ref);
    await temp.rename(target.path);
    await _update((index) {
      index.files[ref.sha256] = _Entry(
        ref.bytes,
        ref.format.name,
        _clock.now(),
      );
    });
  }

  /// Marks [refs] as used now, so eviction keeps them longer.
  Future<void> touch(Iterable<AssetRef> refs) => _update((index) {
    final now = _clock.now();
    for (final ref in refs) {
      index.files[ref.sha256]?.usedAt = now;
    }
  });

  /// Makes [refs] the files [owner] keeps, replacing what it kept before.
  /// Files it no longer needs become ordinary cache, evicted when old.
  Future<void> pin(String owner, Iterable<AssetRef> refs) async {
    await _update((index) {
      final shas = {for (final r in refs) r.sha256};
      if (shas.isEmpty) {
        index.pins.remove(owner);
      } else {
        index.pins[owner] = shas;
      }
    });
    await evict();
  }

  Future<Set<String>> pinned() async => (await _load()).pinned;

  /// Bytes on disk: all files, and those no pin protects.
  Future<({int total, int unpinned})> usage() async {
    final index = await _load();
    final pinned = index.pinned;
    var total = 0, unpinned = 0;
    index.files.forEach((sha, e) {
      total += e.bytes;
      if (!pinned.contains(sha)) unpinned += e.bytes;
    });
    return (total: total, unpinned: unpinned);
  }

  /// Deletes every file no pin protects (Developer settings).
  Future<void> clearUnpinned() => evict(limit: 0);

  /// Deletes unpinned files, oldest first, until they fit [limitBytes]
  /// (or [limit]). [keep] protects files a running download just fetched.
  Future<void> evict({Set<String> keep = const {}, int? limit}) async {
    final max = limit ?? limitBytes;
    final root = await _root;
    await _update((index) async {
      final pinned = index.pinned;
      final candidates = [
        for (final MapEntry(key: sha, value: e) in index.files.entries)
          if (!pinned.contains(sha) && !keep.contains(sha)) (sha, e),
      ]..sort((a, b) => a.$2.usedAt.compareTo(b.$2.usedAt));
      var unpinned = candidates.fold<int>(0, (s, c) => s + c.$2.bytes);
      for (final (sha, e) in candidates) {
        if (unpinned <= max) break;
        await _deleteFile(root, sha, e.format);
        index.files.remove(sha);
        unpinned -= e.bytes;
      }
    });
  }

  /// Deletes [refs] unless pinned (the Me tab's Downloads › Delete).
  /// Returns the bytes freed.
  Future<int> deleteUnpinned(Iterable<AssetRef> refs) async {
    final root = await _root;
    var freed = 0;
    await _update((index) async {
      final pinned = index.pinned;
      for (final ref in refs.toSet()) {
        if (pinned.contains(ref.sha256)) continue;
        final e = index.files.remove(ref.sha256);
        if (e == null) continue;
        await _deleteFile(root, ref.sha256, e.format);
        freed += e.bytes;
      }
    });
    return freed;
  }

  Future<void> _deleteFile(Directory root, String sha, String format) async {
    try {
      await File('${root.path}/$sha.$format').delete();
    } on PathNotFoundException {
      // Already gone.
    }
  }

  // --- index.json: what's stored, when it was last used, and the pins ---

  Future<File> _indexFile() async => File('${(await _root).path}/index.json');

  Future<_Index> _load() async {
    final loaded = _index;
    if (loaded != null) return loaded;
    _Index index;
    try {
      final file = await _indexFile();
      index = await file.exists()
          ? _Index.fromJson(jsonDecode(await file.readAsString()))
          : _Index();
    } on Object catch (e) {
      // A damaged index: rebuild what we can from the files themselves.
      debugPrint('Asset cache index damaged, rebuilding: $e');
      index = await _rebuild();
    }
    return _index ??= index;
  }

  /// Every complete file is known by its name; pins are lost, and the look
  /// controller pins its files again on the next apply or launch.
  Future<_Index> _rebuild() async {
    final index = _Index();
    final root = await _root;
    if (!await root.exists()) return index;
    final name = RegExp(r'^([0-9a-f]{64})\.(\w+)$');
    await for (final f in root.list()) {
      final m = f is File ? name.firstMatch(f.uri.pathSegments.last) : null;
      if (m == null) continue;
      index.files[m[1]!] = _Entry(
        await (f as File).length(),
        m[2]!,
        _clock.now(),
      );
    }
    return index;
  }

  /// Runs [change] on the index and saves it, one change at a time.
  Future<void> _update(FutureOr<void> Function(_Index index) change) {
    final run = _writes.then((_) async {
      final index = await _load();
      await change(index);
      final file = await _indexFile();
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.part');
      await temp.writeAsString(jsonEncode(index.toJson()), flush: true);
      await temp.rename(file.path);
    });
    // Keep the chain going even if one change fails.
    _writes = run.catchError((Object _) {});
    return run;
  }

  /// Every file on disk with the right size and hash; drops the rest.
  /// Slow (reads everything): for repair, not every launch.
  Future<int> verify() async {
    final root = await _root;
    var dropped = 0;
    await _update((index) async {
      for (final MapEntry(key: sha, value: e) in index.files.entries.toList()) {
        final file = File('${root.path}/$sha.${e.format}');
        final ok =
            await file.exists() &&
            await file.length() == e.bytes &&
            (await sha256.bind(file.openRead()).first).toString() == sha;
        if (!ok) {
          await _deleteFile(root, sha, e.format);
          index.files.remove(sha);
          dropped++;
        }
      }
    });
    return dropped;
  }
}

/// A download in progress, written to a temp file next to the cache.
class IncomingFile {
  IncomingFile._(this._cache, this.ref, this._temp, this._sink);

  final AssetCache _cache;
  final AssetRef ref;
  final File _temp;
  final IOSink _sink;
  final _hash = _HashSink();
  late final _digest = sha256.startChunkedConversion(_hash);
  int _received = 0;

  int get received => _received;

  /// Adds the next chunk. Throws [AssetCheckException] as soon as the file
  /// is bigger than the catalog says.
  void add(List<int> chunk) {
    _received += chunk.length;
    if (_received > ref.bytes) {
      throw AssetCheckException(ref, 'more than ${ref.bytes} bytes');
    }
    _sink.add(chunk);
    _digest.add(chunk);
  }

  /// Keeps the file if its size and sha256 match; otherwise deletes it and
  /// throws [AssetCheckException].
  Future<void> commit() async {
    await _sink.close();
    _digest.close();
    if (_received != ref.bytes) {
      await discard();
      throw AssetCheckException(ref, 'got $_received of ${ref.bytes} bytes');
    }
    if (_hash.value.toString() != ref.sha256) {
      await discard();
      throw AssetCheckException(ref, 'sha256 does not match');
    }
    await _cache._commit(ref, _temp);
  }

  /// Throws the partial file away (failure or cancel).
  Future<void> discard() async {
    try {
      await _sink.close();
    } on Object {
      // Already closed.
    }
    try {
      await _temp.delete();
    } on PathNotFoundException {
      // Never written.
    }
  }
}

class _HashSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// A downloaded file isn't what the catalog says: wrong size or hash.
class AssetCheckException implements Exception {
  const AssetCheckException(this.ref, this.reason);

  final AssetRef ref;
  final String reason;

  @override
  String toString() => 'AssetCheckException: ${ref.url}: $reason';
}

class _Entry {
  _Entry(this.bytes, this.format, this.usedAt);

  final int bytes;
  final String format;
  DateTime usedAt;
}

class _Index {
  final files = <String, _Entry>{};
  final pins = <String, Set<String>>{};

  Set<String> get pinned => {for (final p in pins.values) ...p};

  static _Index fromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    final index = _Index();
    (map['files'] as Map<String, dynamic>).forEach((sha, e) {
      final m = e as Map<String, dynamic>;
      index.files[sha] = _Entry(
        m['bytes'] as int,
        m['format'] as String,
        DateTime.parse(m['usedAt'] as String),
      );
    });
    (map['pins'] as Map<String, dynamic>).forEach((owner, shas) {
      index.pins[owner] = {...(shas as List).cast<String>()};
    });
    return index;
  }

  Map<String, Object?> toJson() => {
    'v': 1,
    'files': {
      for (final MapEntry(key: sha, value: e) in files.entries)
        sha: {
          'bytes': e.bytes,
          'format': e.format,
          'usedAt': e.usedAt.toUtc().toIso8601String(),
        },
    },
    'pins': {
      for (final MapEntry(key: owner, value: shas) in pins.entries)
        owner: shas.toList()..sort(),
    },
  };
}
