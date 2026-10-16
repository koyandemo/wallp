/// The theme catalog format from docs/theme-api.md, as Dart models.
///
/// Pure Dart: no Flutter imports, so `tool/seed/` can build the mock catalog
/// with the same code the app reads it with.
library;

export 'json.dart' show CatalogFormatException, HexColor, JsonReader;
export 'models/catalog.dart';
export 'models/common.dart';
export 'models/content.dart';
export 'models/festival.dart';
export 'models/scene.dart';
export 'models/theme.dart';
