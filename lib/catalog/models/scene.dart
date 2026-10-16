import '../json.dart';
import 'common.dart';

/// Engine IDs this format knows. The app decides separately which of them
/// its build can draw (see [Engines]).
abstract final class EngineIds {
  static const halloween = 'halloween';
  static const christmas = 'christmas';
  static const thingyan = 'thingyan';

  /// Draws a scene from JSON layers; used by every dashboard-made theme.
  static const layers = 'layers';

  static const builtIn = {halloween, christmas, thingyan};
}

/// Which painter draws a wallpaper, and its settings.
class SceneSpec {
  const SceneSpec({required this.engine, this.params = const {}, this.layers});

  factory SceneSpec.fromJson(JsonReader r) {
    final engine = r.id('engine');
    final params = r.optObject('params');
    return SceneSpec(
      engine: engine,
      params: params?.json ?? const {},
      // Parsed eagerly so a broken layer fails at load, not mid-draw.
      layers: engine == EngineIds.layers
          ? (params ?? r.fail('params', 'the layers engine needs params'))
                .objects('layers', Layer.fromJson, required: true)
          : null,
    );
  }

  SceneSpec.layers(List<Layer> this.layers)
    : engine = EngineIds.layers,
      params = const {};

  final String engine;

  /// Engine-specific settings, as written.
  final Map<String, dynamic> params;

  /// Typed [params] for the `layers` engine, back to front.
  final List<Layer>? layers;

  bool get isLive => layers?.any((l) => l.isAnimated) ?? true;

  /// Whether any layer uses a palette token like `@accent`.
  bool get usesTokens =>
      layers?.any(
        (l) => switch (l) {
          GradientLayer(:final colors) => colors.any((c) => c.isToken),
          ShapeLayer(:final color) ||
          ParticlesLayer(:final color) => color.isToken,
          ImageLayer() => false,
        },
      ) ??
      false;

  /// Files this scene needs on disk before it can be drawn.
  Iterable<AssetRef> get assets sync* {
    for (final layer in layers ?? const <Layer>[]) {
      if (layer is ImageLayer) yield layer.image;
    }
  }

  Map<String, Object?> toJson() => {
    'engine': engine,
    'params': layers == null
        ? params
        : {
            'layers': [for (final l in layers!) l.toJson()],
          },
  };
}

/// A layer colour: a literal `#RRGGBB` or a palette token like `@accent`.
///
/// Tokens let one scene follow the theme's variants and the user's accent.
extension type const SceneColor(String value) {
  static const tokens = {
    '@background',
    '@deep',
    '@surface',
    '@text',
    '@accent',
    '@motif',
  };

  static SceneColor parse(JsonReader r, String key) {
    if (!r.has(key)) r.fail(key, 'is required');
    return parseValue(r.json[key], r.at(key));
  }

  static SceneColor parseValue(Object? value, String path) {
    if (value is! String ||
        (!HexColor.isValid(value) && !tokens.contains(value))) {
      throw CatalogFormatException(
        path,
        'expected "#RRGGBB" or one of ${tokens.join(', ')}',
      );
    }
    return SceneColor(value);
  }

  bool get isToken => value.startsWith('@');
}

/// One layer of a `layers` scene. Positions and sizes are fractions of the
/// screen (0–1), so a scene fits any phone.
sealed class Layer {
  const Layer({this.opacity = 1});

  factory Layer.fromJson(JsonReader r) {
    final layer = switch (r.string('type')) {
      'gradient' => GradientLayer._fromJson(r),
      'image' => ImageLayer._fromJson(r),
      'shape' => ShapeLayer._fromJson(r),
      'particles' => ParticlesLayer._fromJson(r),
      final other => r.fail('type', 'unknown layer type "$other"'),
    };
    if (layer.opacity < 0 || layer.opacity > 1) {
      r.fail('opacity', 'must be 0–1');
    }
    return layer;
  }

  final double opacity;

  bool get isAnimated;

  String get type;

  Map<String, Object?> toJson() => compact({
    'type': type,
    ..._fields(),
    'opacity': opacity == 1 ? null : opacity,
  });

  Map<String, Object?> _fields();
}

/// Fills the screen with a linear gradient.
class GradientLayer extends Layer {
  const GradientLayer({required this.colors, this.angle = 180, super.opacity});

  factory GradientLayer._fromJson(JsonReader r) {
    final raw = r.json['colors'];
    if (raw is! List || raw.length < 2) {
      r.fail('colors', 'needs at least 2 colours');
    }
    final colors = [
      for (final (i, c) in raw.indexed)
        SceneColor.parseValue(c, '${r.at('colors')}[$i]'),
    ];
    return GradientLayer(
      colors: colors,
      angle: r.integer('angle', orElse: 180),
      opacity: r.number('opacity', orElse: 1),
    );
  }

  final List<SceneColor> colors;
  final int angle;

  @override
  String get type => 'gradient';

  @override
  bool get isAnimated => false;

  @override
  Map<String, Object?> _fields() => {
    'colors': [for (final c in colors) c.value],
    'angle': angle,
  };
}

/// A downloaded picture, e.g. hills or a cabin drawn in the dashboard.
class ImageLayer extends Layer {
  const ImageLayer({
    required this.image,
    this.fit = ImageFit.width,
    this.anchor = ImageAnchor.bottom,
    super.opacity,
  });

  factory ImageLayer._fromJson(JsonReader r) => ImageLayer(
    image: AssetRef.fromJson(r.object('image')),
    fit: r.enumValue('fit', ImageFit.values, orElse: ImageFit.width),
    anchor: r.enumValue(
      'anchor',
      ImageAnchor.values,
      orElse: ImageAnchor.bottom,
    ),
    opacity: r.number('opacity', orElse: 1),
  );

  final AssetRef image;
  final ImageFit fit;
  final ImageAnchor anchor;

  @override
  String get type => 'image';

  @override
  bool get isAnimated => false;

  @override
  Map<String, Object?> _fields() => {
    'image': image.toJson(),
    'fit': fit.name,
    'anchor': anchor.name,
  };
}

enum ImageFit { cover, width, contain }

enum ImageAnchor { top, center, bottom }

/// A simple shape: moon, tree, cabin, ground, lantern.
class ShapeLayer extends Layer {
  const ShapeLayer({
    required this.shape,
    required this.x,
    required this.y,
    required this.width,
    required this.color,
    this.aspect = 1,
    this.points = const [],
    this.glow = false,
    this.motion = ShapeMotion.none,
    super.opacity,
  });

  factory ShapeLayer._fromJson(JsonReader r) {
    final shape = r.enumValue('shape', ShapeKind.values);
    final points = [
      for (final (i, p) in (r.json['points'] as List? ?? const []).indexed)
        if (p is List &&
            p.length == 2 &&
            p.every((n) => n is num && n >= 0 && n <= 1))
          (x: (p[0] as num).toDouble(), y: (p[1] as num).toDouble())
        else
          throw CatalogFormatException(
            '${r.at('points')}[$i]',
            'expected [x, y] in 0–1',
          ),
    ];
    if (shape == ShapeKind.polygon && points.length < 3) {
      r.fail('points', 'a polygon needs at least 3 points');
    }
    final layer = ShapeLayer(
      shape: shape,
      x: r.number('x'),
      y: r.number('y'),
      width: r.number('width'),
      aspect: r.number('aspect', orElse: 1),
      color: SceneColor.parse(r, 'color'),
      points: points,
      glow: r.boolean('glow', orElse: false),
      motion: r.enumValue(
        'motion',
        ShapeMotion.values,
        orElse: ShapeMotion.none,
      ),
      opacity: r.number('opacity', orElse: 1),
    );
    for (final (key, v) in [('x', layer.x), ('y', layer.y)]) {
      if (v < -0.5 || v > 1.5) r.fail(key, 'must be -0.5–1.5');
    }
    if (layer.width <= 0 || layer.width > 3) r.fail('width', 'must be 0–3');
    if (layer.aspect <= 0 || layer.aspect > 10) {
      r.fail('aspect', 'must be 0–10');
    }
    return layer;
  }

  final ShapeKind shape;

  /// Centre, as fractions of the screen width and height.
  final double x;
  final double y;

  /// Width as a fraction of the screen width; height = width × [aspect].
  final double width;
  final double aspect;
  final SceneColor color;

  /// For polygons: corners inside the shape's box, 0–1.
  final List<({double x, double y})> points;
  final bool glow;
  final ShapeMotion motion;

  @override
  String get type => 'shape';

  @override
  bool get isAnimated => motion != ShapeMotion.none;

  @override
  Map<String, Object?> _fields() => compact({
    'shape': shape.name,
    'x': x,
    'y': y,
    'width': width,
    'aspect': aspect == 1 ? null : aspect,
    'color': color.value,
    'points': points.isEmpty
        ? null
        : [
            for (final p in points) [p.x, p.y],
          ],
    'glow': glow ? true : null,
    'motion': motion == ShapeMotion.none ? null : motion.name,
  });
}

enum ShapeKind { circle, ellipse, rect, polygon }

enum ShapeMotion { none, float, pulse, sway }

/// Falling or drifting things: snow, bats, lanterns, petals.
class ParticlesLayer extends Layer {
  const ParticlesLayer({
    required this.effect,
    required this.count,
    required this.color,
    this.speed = 0.5,
    this.size = 0.5,
    super.opacity,
  });

  factory ParticlesLayer._fromJson(JsonReader r) {
    final layer = ParticlesLayer(
      effect: r.enumValue('effect', ParticleEffect.values),
      count: r.integer('count'),
      color: SceneColor.parse(r, 'color'),
      speed: r.number('speed', orElse: 0.5),
      size: r.number('size', orElse: 0.5),
      opacity: r.number('opacity', orElse: 1),
    );
    // Live wallpapers run for hours; keep the per-frame work bounded.
    if (layer.count < 1 || layer.count > maxCount) {
      r.fail('count', 'must be 1–$maxCount');
    }
    if (layer.speed < 0 || layer.speed > 1) r.fail('speed', 'must be 0–1');
    if (layer.size <= 0 || layer.size > 1) r.fail('size', 'must be 0–1');
    return layer;
  }

  static const maxCount = 150;

  final ParticleEffect effect;
  final int count;
  final SceneColor color;

  /// 0 = still, 1 = fastest the engine allows.
  final double speed;

  /// 0–1 of the engine's largest particle.
  final double size;

  @override
  String get type => 'particles';

  @override
  bool get isAnimated => speed > 0;

  @override
  Map<String, Object?> _fields() => {
    'effect': effect.name,
    'count': count,
    'color': color.value,
    'speed': speed,
    'size': size,
  };
}

enum ParticleEffect {
  snow,
  rain,
  drops,
  bats,
  lanterns,
  petals,
  sparkles,
  stars,
}

/// Every engine the format defines, and the app version that added it.
class Engines {
  const Engines(this.engines);

  factory Engines.fromJson(JsonReader r) =>
      Engines(r.objects('engines', EngineInfo.fromJson, required: true));

  final List<EngineInfo> engines;

  Map<String, Object?> toJson() => {
    'engines': [for (final e in engines) e.toJson()],
  };
}

class EngineInfo {
  const EngineInfo({
    required this.id,
    required this.sinceApp,
    this.params = const [],
  });

  factory EngineInfo.fromJson(JsonReader r) => EngineInfo(
    id: r.id('id'),
    sinceApp: r.string('sinceApp'),
    params: r.strings('params'),
  );

  final String id;
  final String sinceApp;
  final List<String> params;

  Map<String, Object?> toJson() => {
    'id': id,
    'sinceApp': sinceApp,
    'params': params,
  };
}
