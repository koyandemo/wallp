/// Typed reads from decoded catalog JSON.
///
/// Pure Dart (no Flutter) so the seed generator in `tool/seed/` can use the
/// same models the app does. Every error names the field that broke, e.g.
/// `themes[3].palette.background: expected "#RRGGBB", got "red"`.
library;

/// A catalog file or object that doesn't match the format in
/// docs/theme-api.md.
class CatalogFormatException implements Exception {
  const CatalogFormatException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => 'CatalogFormatException: $path: $message';
}

/// A `#RRGGBB` colour, as every catalog colour is written.
extension type const HexColor(String hex) {
  static final _pattern = RegExp(r'^#[0-9A-Fa-f]{6}$');

  static bool isValid(String value) => _pattern.hasMatch(value);

  /// Opaque ARGB, ready for Flutter's `Color(argb)`.
  int get argb => 0xFF000000 | int.parse(hex.substring(1), radix: 16);
}

/// Wraps one JSON object and remembers where it sits in the file.
class JsonReader {
  JsonReader(this.json, [this.path = r'$']);

  /// Reads [value] as an object, or throws naming [path].
  factory JsonReader.of(Object? value, String path) {
    if (value is Map<String, dynamic>) return JsonReader(value, path);
    if (value is Map) return JsonReader(value.cast<String, dynamic>(), path);
    throw CatalogFormatException(path, 'expected an object');
  }

  final Map<String, dynamic> json;
  final String path;

  String at(String key) => '$path.$key';

  bool has(String key) => json[key] != null;

  Never fail(String key, String message) =>
      throw CatalogFormatException(at(key), message);

  T _req<T>(String key) {
    final value = json[key];
    if (value == null) fail(key, 'is required');
    if (value is! T) fail(key, 'expected $T, got ${value.runtimeType}');
    return value;
  }

  T? _opt<T>(String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! T) fail(key, 'expected $T, got ${value.runtimeType}');
    return value;
  }

  String string(String key) => _req<String>(key);
  String? optString(String key) => _opt<String>(key);

  bool boolean(String key, {bool? orElse}) =>
      orElse == null ? _req<bool>(key) : (_opt<bool>(key) ?? orElse);

  int integer(String key, {int? orElse}) {
    final value = orElse == null ? _req<num>(key) : (_opt<num>(key) ?? orElse);
    if (value is! int && value != value.roundToDouble()) {
      fail(key, 'expected a whole number, got $value');
    }
    return value.toInt();
  }

  int? optInteger(String key) => has(key) ? integer(key) : null;

  double number(String key, {double? orElse}) =>
      (orElse == null ? _req<num>(key) : (_opt<num>(key) ?? orElse)).toDouble();

  /// A lowercase kebab-case ID, the only ID form the catalog allows.
  String id(String key) {
    final value = string(key);
    if (!isId(value)) fail(key, 'expected a kebab-case ID, got "$value"');
    return value;
  }

  String? optId(String key) => has(key) ? id(key) : null;

  static final _idPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
  static bool isId(String value) => _idPattern.hasMatch(value);

  HexColor color(String key) {
    final value = string(key);
    if (!HexColor.isValid(value)) {
      fail(key, 'expected "#RRGGBB", got "$value"');
    }
    return HexColor(value);
  }

  HexColor? optColor(String key) => has(key) ? color(key) : null;

  /// A `YYYY-MM-DD` calendar date, as a local midnight [DateTime].
  DateTime date(String key) => parseDate(string(key), at(key));

  static DateTime parseDate(String value, String path) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    final date = match == null
        ? null
        : DateTime(
            int.parse(match[1]!),
            int.parse(match[2]!),
            int.parse(match[3]!),
          );
    // DateTime rolls 2027-02-31 over to March; reject that instead.
    if (date == null ||
        date.month != int.parse(match![2]!) ||
        date.day != int.parse(match[3]!)) {
      throw CatalogFormatException(path, 'expected YYYY-MM-DD, got "$value"');
    }
    return date;
  }

  /// An ISO 8601 UTC time, e.g. `2026-10-15T14:00:00Z`.
  DateTime time(String key) {
    final value = string(key);
    final parsed = DateTime.tryParse(value);
    if (parsed == null || !parsed.isUtc) {
      fail(key, 'expected an ISO 8601 UTC time, got "$value"');
    }
    return parsed;
  }

  DateTime? optTime(String key) => has(key) ? time(key) : null;

  JsonReader object(String key) => JsonReader.of(_req<Object>(key), at(key));

  JsonReader? optObject(String key) =>
      has(key) ? JsonReader.of(json[key], at(key)) : null;

  List<Object?> _list(String key, bool required) {
    final value = required ? _req<List>(key) : _opt<List>(key);
    return value ?? const [];
  }

  List<String> strings(String key, {bool required = false}) => [
    for (final (i, v) in _list(key, required).indexed)
      if (v is String)
        v
      else
        throw CatalogFormatException('${at(key)}[$i]', 'expected a string'),
  ];

  List<HexColor> colors(String key, {bool required = true}) => [
    for (final (i, v) in _list(key, required).indexed)
      if (v is String && HexColor.isValid(v))
        HexColor(v)
      else
        throw CatalogFormatException('${at(key)}[$i]', 'expected "#RRGGBB"'),
  ];

  /// Parses every item; one bad item fails the whole list.
  List<T> objects<T>(
    String key,
    T Function(JsonReader) parse, {
    bool required = false,
  }) => [
    for (final (i, v) in _list(key, required).indexed)
      parse(JsonReader.of(v, '${at(key)}[$i]')),
  ];

  /// Parses every item, skipping (and reporting) the ones that fail, so one
  /// broken theme can't take down the whole catalog.
  List<T> objectsLenient<T>(
    String key,
    T Function(JsonReader) parse,
    List<CatalogFormatException> issues,
  ) {
    final out = <T>[];
    for (final (i, v) in _list(key, false).indexed) {
      try {
        out.add(parse(JsonReader.of(v, '${at(key)}[$i]')));
      } on CatalogFormatException catch (e) {
        issues.add(e);
      }
    }
    return out;
  }

  /// One of [values] by its JSON name.
  T enumValue<T extends Enum>(String key, List<T> values, {T? orElse}) {
    final raw = orElse == null ? string(key) : optString(key);
    if (raw == null) return orElse!;
    for (final v in values) {
      if (jsonName(v) == raw) return v;
    }
    if (orElse != null) return orElse;
    fail(key, 'expected one of ${values.map(jsonName).join(', ')}, got "$raw"');
  }
}

/// `myanmarCalendar` → `myanmar-calendar`; the enum name as written in JSON.
String jsonName(Enum value) => value.name.replaceAllMapped(
  RegExp('[A-Z]'),
  (m) => '-${m[0]!.toLowerCase()}',
);

/// Formats a date as `YYYY-MM-DD`.
String formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Drops null values so written JSON stays small and matches the docs.
Map<String, Object?> compact(Map<String, Object?> json) => {
  for (final MapEntry(:key, :value) in json.entries) key: ?value,
};
