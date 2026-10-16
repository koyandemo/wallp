import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../catalog/catalog.dart';

/// The catalog shipped inside the app (assets/builtin/catalog): the themes
/// its own painters draw. Works in every engine, with no network and no
/// saved data: first launch, wallp Home after a reboot, the live wallpaper.
///
/// Read from the bundle once per engine and kept: [BuiltInCatalog()] with
/// no bundle is one shared instance. Once loaded, results come back as
/// [SynchronousFuture]s, which finish at once in any zone.
class BuiltInCatalog {
  factory BuiltInCatalog({AssetBundle? bundle}) =>
      bundle == null ? shared : BuiltInCatalog._(bundle);

  BuiltInCatalog._(this._bundle);

  static final shared = BuiltInCatalog._(rootBundle);

  static const dir = 'assets/builtin/catalog';

  final AssetBundle _bundle;
  Catalog? _catalog;
  Future<Catalog>? _loadingCatalog;
  final _themes = <String, ThemeDetail>{};
  final _loadingThemes = <String, Future<ThemeDetail>>{};

  Future<Catalog> catalog() {
    final done = _catalog;
    if (done != null) return SynchronousFuture(done);
    return _loadingCatalog ??= _bundle.loadString('$dir/catalog.json').then((
      s,
    ) {
      return _catalog = Catalog.fromJson(
        JsonReader.of(jsonDecode(s), 'built-in'),
      );
    });
  }

  /// The full built-in theme, or null if [id] isn't built in.
  Future<ThemeDetail?> theme(String id) {
    final done = _themes[id];
    if (done != null) return SynchronousFuture(done);
    return catalog().then((catalog) {
      final summary = catalog.theme(id);
      if (summary == null) return null;
      return _loadingThemes[id] ??= _bundle
          .loadString('$dir/themes/${summary.id}.${summary.rev}.json')
          .then((s) {
            return _themes[id] = ThemeDetail.fromJson(
              JsonReader.of(jsonDecode(s), id),
            );
          });
    });
  }

  /// Reads everything now, so later calls finish without touching the
  /// bundle. Widget tests call this in setUpAll: inside testWidgets' fake
  /// clock, asset reads never finish.
  Future<void> preload() async {
    final catalog = await this.catalog();
    await Future.wait([for (final t in catalog.themes) theme(t.id)]);
  }
}
