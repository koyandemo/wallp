import 'dart:convert';
import 'dart:io';

import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/look/applied_look.dart';
import 'package:wallp/look/look_store.dart';
import 'package:wallp/look/resolved_look.dart';
import 'package:wallp/models/phone_theme.dart';

const _dir = 'assets/mock/catalog/v1';

Object? _read(String path) =>
    jsonDecode(File('$_dir/$path').readAsStringSync());

/// The mock catalog, read straight from disk.
Catalog mockCatalog() {
  final manifest = _read('manifest.json')! as Map<String, dynamic>;
  return Catalog.fromJson(
    JsonReader.of(_read(manifest['catalog'] as String), 'catalog'),
  );
}

/// A full theme file from the mock catalog.
ThemeDetail mockTheme(String id) {
  final rev = mockCatalog().theme(id)!.rev;
  return ThemeDetail.fromJson(JsonReader.of(_read('themes/$id.$rev.json'), id));
}

/// 15 Oct 2026, the design's date: Halloween is 16 nights away.
final designDay = DateTime(2026, 10, 15, 19, 47);

/// A built-in theme as today's renderers see it (scene, icons, colours).
PhoneTheme builtInTheme(String id) => ResolvedLook.of(
  AppliedLook.wholeTheme(mockCatalog(), mockTheme(id), at: designDay),
  designDay,
).wallpaperTheme;

const builtInIds = ['halloween-night', 'christmas-eve', 'thingyan-water'];

List<PhoneTheme> builtInThemes() => [
  for (final id in builtInIds) builtInTheme(id),
];

/// Applies a built-in theme the way the store does, with its [accent]th
/// accent (0 = its default).
Future<void> applyBuiltIn(String id, {int accent = 0}) {
  final theme = mockTheme(id);
  return LookStore().save(
    AppliedLook.wholeTheme(
      mockCatalog(),
      theme,
      at: DateTime.now(),
      accent: theme.accents[accent],
    ),
  );
}
