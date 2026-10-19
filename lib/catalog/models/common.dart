import '../json.dart';

/// Text people read, per language: `{"en": "Water Festival", "my": "သင်္ကြန်"}`.
class LocalizedText {
  LocalizedText(Map<String, String> values)
    : values = Map.unmodifiable(values) {
    if (values.isEmpty) {
      throw ArgumentError.value(
        values,
        'values',
        'needs at least one language',
      );
    }
  }

  LocalizedText.en(String text) : this({'en': text});

  factory LocalizedText.fromJson(Object? json, String path) {
    if (json is! Map || json.isEmpty) {
      throw CatalogFormatException(path, 'expected {"en": "…"}');
    }
    final values = <String, String>{};
    json.forEach((lang, text) {
      if (lang is! String || text is! String || text.isEmpty) {
        throw CatalogFormatException('$path.$lang', 'expected non-empty text');
      }
      values[lang] = text;
    });
    if (!values.containsKey('en')) {
      throw CatalogFormatException(path, 'English ("en") is required');
    }
    return LocalizedText(values);
  }

  final Map<String, String> values;

  /// [lang] if present, else English.
  String resolve([String lang = 'en']) => values[lang] ?? values['en']!;

  String get en => values['en']!;

  Map<String, String> toJson() => values;

  @override
  bool operator ==(Object other) =>
      other is LocalizedText &&
      other.values.length == values.length &&
      other.values.entries.every((e) => values[e.key] == e.value);

  @override
  int get hashCode => Object.hashAllUnordered(
    values.entries.map((e) => Object.hash(e.key, e.value)),
  );

  @override
  String toString() => en;
}

extension LocalizedRead on JsonReader {
  LocalizedText text(String key) {
    if (!has(key)) fail(key, 'is required');
    return LocalizedText.fromJson(json[key], at(key));
  }

  LocalizedText? optText(String key) => has(key) ? text(key) : null;
}

/// A downloadable file on the CDN, named by its content hash.
///
/// `url` is relative to the catalog base URL (`assets/<sha256>.<ext>`), so
/// the same catalog works from the mock bundle and the real CDN.
class AssetRef {
  const AssetRef({
    required this.url,
    required this.sha256,
    required this.bytes,
    required this.format,
  });

  factory AssetRef.fromJson(JsonReader r) {
    final sha = r.string('sha256');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      r.fail('sha256', 'expected 64 lowercase hex characters');
    }
    final bytes = r.integer('bytes');
    if (bytes <= 0 || bytes > maxBytes) {
      r.fail('bytes', 'must be between 1 and $maxBytes');
    }
    final format = r.enumValue('format', AssetFormat.values);
    final url = r.string('url');
    if (url != 'assets/$sha.${format.name}') {
      r.fail('url', 'expected "assets/$sha.${format.name}", got "$url"');
    }
    return AssetRef(url: url, sha256: sha, bytes: bytes, format: format);
  }

  /// The app refuses single files over 10 MB (theme-api.md §8).
  static const maxBytes = 10 * 1024 * 1024;

  final String url;
  final String sha256;
  final int bytes;
  final AssetFormat format;

  bool get isImage => switch (format) {
    AssetFormat.png || AssetFormat.jpg || AssetFormat.webp => true,
    _ => false,
  };

  Map<String, Object?> toJson() => {
    'url': url,
    'sha256': sha256,
    'bytes': bytes,
    'format': format.name,
  };

  @override
  bool operator ==(Object other) => other is AssetRef && other.sha256 == sha256;

  @override
  int get hashCode => sha256.hashCode;
}

enum AssetFormat { png, webp, jpg, ttf, otf, woff2, json }

/// An accent: one colour, or a gradient of 2–3 stops.
class Accent {
  const Accent({
    required this.id,
    required this.name,
    required this.colors,
    this.angle = 90,
  });

  factory Accent.fromJson(JsonReader r) {
    final type = r.enumValue('type', AccentType.values);
    final colors = r.colors('colors');
    final expected = switch (type) {
      AccentType.solid => colors.length == 1,
      AccentType.gradient => colors.length >= 2 && colors.length <= 3,
    };
    if (!expected) {
      r.fail(
        'colors',
        type == AccentType.solid
            ? 'a solid accent has 1 colour'
            : 'a gradient has 2–3 colours',
      );
    }
    final angle = r.integer('angle', orElse: 90);
    if (angle < 0 || angle >= 360) r.fail('angle', 'must be 0–359');
    return Accent(
      id: r.id('id'),
      name: r.text('name'),
      colors: colors,
      angle: angle,
    );
  }

  final String id;
  final LocalizedText name;
  final List<HexColor> colors;

  /// CSS-style degrees: 90 = left to right, 180 = top to bottom.
  final int angle;

  AccentType get type =>
      colors.length == 1 ? AccentType.solid : AccentType.gradient;

  /// The colour to use where a gradient can't be drawn (scene painters).
  HexColor get primary => colors.first;

  Map<String, Object?> toJson() => compact({
    'id': id,
    'name': name.toJson(),
    'type': type.name,
    'colors': [for (final c in colors) c.hex],
    'angle': type == AccentType.gradient ? angle : null,
  });
}

enum AccentType { solid, gradient }
