import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../catalog/catalog.dart';
import 'scene_assets.dart';

/// Loads downloaded catalog fonts (`.ttf`) into this engine with
/// [FontLoader], so the clock and labels draw in them with no network
/// (docs/theme-api.md §7.4).
///
/// Each engine (store, wallp Home, live wallpaper) has its own fonts, so
/// each calls [ensureAll] for the look it draws.
class FontRegistry extends ChangeNotifier {
  FontRegistry({this._assets});

  static final shared = FontRegistry();

  final SceneAssets? _assets;
  SceneAssets get _files => _assets ?? SceneAssets.shared;

  /// Catalog family name ("Creepster") → loaded family ("wallp-creepster").
  final _loaded = <String, String>{};

  /// Catalog family name → loaded families for other scripts (Padauk for
  /// Burmese on fonts without Myanmar letters).
  final _fallbacks = <String, List<String>>{};
  final _loading = <String, Future<bool>>{};

  static String familyFor(CatalogFont font) => 'wallp-${font.id}';

  /// The loaded family for a catalog family name, or null.
  String? loadedFamily(String family) => _loaded[family];

  /// Loads every font in [fonts] whose files are on the phone. Fonts with
  /// a missing file are skipped (drawn in the system font until they
  /// download). Never throws.
  Future<void> ensureAll(Iterable<CatalogFont> fonts) async {
    final list = fonts.toList();
    await Future.wait([for (final f in list) ensure(f)]);
    // Fallbacks once everything that could load has.
    final byId = {for (final f in list) f.id: f};
    for (final font in list) {
      final fallbacks = [
        for (final id in font.fallbackFor.values)
          if (byId[id] case final f? when _loaded.containsKey(f.family))
            familyFor(f),
      ];
      if (fallbacks.isNotEmpty) _fallbacks[font.family] = fallbacks;
    }
  }

  /// Loads [font] if all its files are on the phone. True when loaded.
  Future<bool> ensure(CatalogFont font) {
    if (_loaded.containsKey(font.family)) return SynchronousFuture(true);
    return _loading[font.id] ??= _load(font).whenComplete(() {
      _loading.remove(font.id);
    });
  }

  Future<bool> _load(CatalogFont font) async {
    try {
      final files = [for (final f in font.files) await _files.bytes(f.asset)];
      if (files.any((b) => b == null)) return false;
      return await load(font, [for (final b in files) b!]);
    } on Object catch (e) {
      debugPrint('Font ${font.id} could not be loaded: $e');
      return false;
    }
  }

  /// Loads [font] from its files' bytes, already in hand. For tests, which
  /// have no asset cache on disk.
  @visibleForTesting
  Future<bool> load(CatalogFont font, List<Uint8List> files) async {
    final loader = FontLoader(familyFor(font));
    for (final bytes in files) {
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
    _loaded[font.family] = familyFor(font);
    // Text drawn before this loaded can redraw in it now.
    notifyListeners();
    return true;
  }

  /// [base] in [family]: the font downloaded from the catalog if loaded,
  /// else the system font. Fonts only ever come from the catalog API.
  /// For PhoneTheme's displayStyle / bodyStyle.
  TextStyle style(String family, [TextStyle? base]) {
    final loaded = _loaded[family];
    if (loaded == null) return base ?? const TextStyle();
    return (base ?? const TextStyle()).copyWith(
      fontFamily: loaded,
      fontFamilyFallback: _fallbacks[family],
    );
  }
}
