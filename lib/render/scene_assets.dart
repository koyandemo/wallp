import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../catalog/catalog.dart';
import '../data/assets/asset_cache.dart';

/// Downloaded pictures and files for drawing: scene images and icon-pack
/// pictures, read from the [AssetCache] and decoded once.
///
/// Never throws: a missing or broken file is null, and whatever needed it
/// draws without it (a scene without its hills, an app with its own icon).
class SceneAssets {
  SceneAssets(this._cache);

  /// Reads [AssetCache.shared]: what every engine uses.
  static final shared = SceneAssets(AssetCache.shared);

  /// The [SceneAssets] for [context]: a [SceneAssetsScope]'s, else [shared].
  static SceneAssets of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SceneAssetsScope>()?.assets ??
      shared;

  final AssetCache _cache;
  final _images = <String, Future<ui.Image?>>{};

  /// How many decoded pictures to keep.
  static const _keep = 64;

  /// The file's bytes, or null if it isn't on the phone.
  Future<Uint8List?> bytes(AssetRef ref) async {
    try {
      final file = await _cache.fileFor(ref);
      return await file.exists() ? await file.readAsBytes() : null;
    } on Object catch (e) {
      debugPrint('Scene asset ${ref.url}: $e');
      return null;
    }
  }

  /// The decoded picture, or null if it isn't on the phone or can't be
  /// decoded.
  Future<ui.Image?> image(AssetRef ref) {
    final cached = _images.remove(ref.sha256);
    if (cached != null) {
      _images[ref.sha256] = cached; // Most recently used last.
      return cached;
    }
    final loading = _decode(ref);
    _images[ref.sha256] = loading;
    if (_images.length > _keep) _images.remove(_images.keys.first);
    // A failed load isn't kept: the file may arrive later.
    loading.then((img) {
      if (img == null) _images.remove(ref.sha256);
    });
    return loading;
  }

  /// Every picture in [refs] that's available, by sha256.
  Future<Map<String, ui.Image>> images(Iterable<AssetRef> refs) async {
    final out = <String, ui.Image>{};
    for (final ref in refs) {
      final img = await image(ref);
      if (img != null) out[ref.sha256] = img;
    }
    return out;
  }

  Future<ui.Image?> _decode(AssetRef ref) async {
    final data = await bytes(ref);
    if (data == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(data);
      return (await codec.getNextFrame()).image;
    } on Object catch (e) {
      debugPrint('Scene asset ${ref.url} could not be decoded: $e');
      return null;
    }
  }
}

/// Gives a subtree its own [SceneAssets] (tests, previews of other caches).
class SceneAssetsScope extends InheritedWidget {
  const SceneAssetsScope({
    super.key,
    required this.assets,
    required super.child,
  });

  final SceneAssets assets;

  @override
  bool updateShouldNotify(SceneAssetsScope oldWidget) =>
      assets != oldWidget.assets;
}
