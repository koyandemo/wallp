import '../json.dart';
import 'common.dart';
import 'scene.dart';

/// A wallpaper on its own, outside a theme.
class Wallpaper {
  const Wallpaper({
    required this.id,
    required this.festivalId,
    required this.name,
    required this.publishedAt,
    this.scene,
    this.image,
    this.tags = const [],
    this.popularity = 0,
    this.minAppVersion = '1.0.0',
  }) : assert((scene == null) != (image == null));

  factory Wallpaper.fromJson(JsonReader r) {
    final kind = r.enumValue('kind', WallpaperKind.values);
    final scene = r.optObject('scene');
    final image = r.optObject('image');
    if (kind == WallpaperKind.scene && scene == null) {
      r.fail('scene', 'a scene wallpaper needs a scene');
    }
    if (kind == WallpaperKind.image && image == null) {
      r.fail('image', 'an image wallpaper needs an image');
    }
    final spec = kind == WallpaperKind.scene
        ? SceneSpec.fromJson(scene!)
        : null;
    // A wallpaper has no palette for @tokens to come from.
    if (spec != null && spec.usesTokens) {
      r.fail('scene', 'wallpaper scenes use "#RRGGBB" colours, not @tokens');
    }
    return Wallpaper(
      id: r.id('id'),
      festivalId: r.id('festivalId'),
      name: r.text('name'),
      publishedAt: r.time('publishedAt'),
      scene: spec,
      image: kind == WallpaperKind.image
          ? WallpaperImage.fromJson(image!)
          : null,
      tags: r.strings('tags'),
      popularity: r.integer('popularity', orElse: 0),
      minAppVersion: r.optString('minAppVersion') ?? '1.0.0',
    );
  }

  final String id;
  final String festivalId;
  final LocalizedText name;
  final DateTime publishedAt;
  final SceneSpec? scene;
  final WallpaperImage? image;
  final List<String> tags;
  final int popularity;
  final String minAppVersion;

  WallpaperKind get kind =>
      scene != null ? WallpaperKind.scene : WallpaperKind.image;

  /// Only scenes can animate.
  bool get isLive => scene?.isLive ?? false;

  bool isNew(DateTime now) {
    final age = now.difference(publishedAt);
    return !age.isNegative && age < const Duration(days: 14);
  }

  Map<String, Object?> toJson() => compact({
    'id': id,
    'festivalId': festivalId,
    'name': name.toJson(),
    'kind': kind.name,
    'scene': scene?.toJson(),
    'image': image?.toJson(),
    'isLive': isLive,
    'tags': tags,
    'publishedAt': publishedAt.toIso8601String(),
    'popularity': popularity,
    'minAppVersion': minAppVersion,
  });
}

enum WallpaperKind { scene, image }

/// A still picture in several sizes; the app picks the smallest one that is
/// at least the screen's width.
class WallpaperImage {
  const WallpaperImage({
    required this.sizes,
    required this.dominant,
    this.blurhash,
  });

  factory WallpaperImage.fromJson(JsonReader r) {
    final sizes = r.objects('sizes', ImageSize.fromJson, required: true);
    if (sizes.isEmpty) r.fail('sizes', 'needs at least one size');
    return WallpaperImage(
      sizes: sizes..sort((a, b) => a.width.compareTo(b.width)),
      dominant: r.color('dominant'),
      blurhash: r.optString('blurhash'),
    );
  }

  /// Narrowest first.
  final List<ImageSize> sizes;
  final HexColor dominant;
  final String? blurhash;

  Map<String, Object?> toJson() => compact({
    'sizes': [for (final s in sizes) s.toJson()],
    'blurhash': blurhash,
    'dominant': dominant.hex,
  });
}

class ImageSize {
  const ImageSize({
    required this.width,
    required this.height,
    required this.asset,
  });

  factory ImageSize.fromJson(JsonReader r) => ImageSize(
    width: r.integer('width'),
    height: r.integer('height'),
    asset: AssetRef.fromJson(r.object('asset')),
  );

  final int width;
  final int height;
  final AssetRef asset;

  Map<String, Object?> toJson() => {
    'width': width,
    'height': height,
    'asset': asset.toJson(),
  };
}

enum FontCategory { display, handwritten, clean, myanmar }

/// A font the app downloads and registers with `FontLoader('font-<id>')`.
class CatalogFont {
  const CatalogFont({
    required this.id,
    required this.family,
    required this.category,
    required this.license,
    required this.files,
    this.scripts = const ['latin'],
    this.tags = const [],
    this.fallbackFor = const {},
    this.sampleText,
    this.listed = true,
  });

  factory CatalogFont.fromJson(JsonReader r) {
    final files = r.objects('files', FontFile.fromJson, required: true);
    if (files.isEmpty) r.fail('files', 'needs at least one file');
    for (final (i, f) in files.indexed) {
      if (f.asset.format != AssetFormat.ttf &&
          f.asset.format != AssetFormat.otf) {
        throw CatalogFormatException(
          '${r.at('files')}[$i].asset.format',
          'the app can only load ttf or otf',
        );
      }
    }
    final license = r.string('license');
    if (!allowedLicenses.contains(license)) {
      r.fail(
        'license',
        'must allow redistribution: ${allowedLicenses.join(', ')}',
      );
    }
    final fallback = r.optObject('fallbackFor');
    return CatalogFont(
      id: r.id('id'),
      family: r.string('family'),
      category: r.enumValue('category', FontCategory.values),
      license: license,
      files: files,
      scripts: r.strings('scripts', required: true),
      tags: r.strings('tags'),
      fallbackFor: {
        for (final key in fallback?.json.keys ?? const <String>[])
          key: fallback!.id(key),
      },
      sampleText: r.optText('sampleText'),
      listed: r.boolean('listed', orElse: true),
    );
  }

  static const allowedLicenses = {'OFL-1.1', 'Apache-2.0'};

  final String id;
  final String family;
  final FontCategory category;
  final String license;
  final List<FontFile> files;

  /// Scripts the font has letters for: `latin`, `myanmar`.
  final List<String> scripts;
  final List<String> tags;

  /// Font IDs that draw text in scripts this font lacks: `{"my": "padauk"}`.
  final Map<String, String> fallbackFor;

  /// Preview text; the app's default is "Welcome".
  final LocalizedText? sampleText;

  /// False hides the font from the store (Fonts tab, search, "clock font"
  /// links) while themes that use it keep drawing with it.
  final bool listed;

  int get bytes => files.fold(0, (sum, f) => sum + f.asset.bytes);

  Map<String, Object?> toJson() => compact({
    'id': id,
    'family': family,
    'category': category.name,
    'scripts': scripts,
    'tags': tags,
    'license': license,
    'files': [for (final f in files) f.toJson()],
    'fallbackFor': fallbackFor.isEmpty ? null : fallbackFor,
    'sampleText': sampleText?.toJson(),
    'listed': listed ? null : false,
  });
}

class FontFile {
  const FontFile({
    required this.asset,
    this.weight = 400,
    this.maxWeight,
    this.style = 'normal',
  });

  factory FontFile.fromJson(JsonReader r) {
    final file = FontFile(
      asset: AssetRef.fromJson(r.object('asset')),
      weight: r.integer('weight', orElse: 400),
      maxWeight: r.optInteger('maxWeight'),
      style: r.optString('style') ?? 'normal',
    );
    if (file.weight < 100 || file.weight > 900) {
      r.fail('weight', 'must be 100–900');
    }
    if (file.maxWeight != null && file.maxWeight! < file.weight) {
      r.fail('maxWeight', 'must be at least weight');
    }
    if (file.style != 'normal' && file.style != 'italic') {
      r.fail('style', 'must be normal or italic');
    }
    return file;
  }

  final AssetRef asset;

  /// The file's weight, or the lowest weight of a variable font.
  final int weight;

  /// Set for variable fonts: the highest weight the file covers.
  final int? maxWeight;
  final String style;

  Map<String, Object?> toJson() => compact({
    'weight': weight,
    'maxWeight': maxWeight,
    'style': style,
    'asset': asset.toJson(),
  });
}

/// A store home carousel slide.
class Banner {
  const Banner({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.cta,
    required this.action,
    required this.look,
    required this.sort,
    this.startsAt,
    this.endsAt,
  });

  factory Banner.fromJson(JsonReader r) {
    final banner = Banner(
      id: r.id('id'),
      title: r.text('title'),
      subtitle: r.text('subtitle'),
      tag: r.text('tag'),
      cta: r.text('cta'),
      action: BannerAction.fromJson(r.object('action')),
      look: BannerLook.fromJson(r.object('look')),
      sort: r.integer('sort'),
      startsAt: r.optTime('startsAt'),
      endsAt: r.optTime('endsAt'),
    );
    if (banner.startsAt != null &&
        banner.endsAt != null &&
        !banner.endsAt!.isAfter(banner.startsAt!)) {
      r.fail('endsAt', 'must be after startsAt');
    }
    return banner;
  }

  final String id;
  final LocalizedText title;
  final LocalizedText subtitle;
  final LocalizedText tag;
  final LocalizedText cta;
  final BannerAction action;
  final BannerLook look;
  final int sort;
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// Banners outside their window are hidden, so they can be scheduled.
  bool isShowing(DateTime now) =>
      (startsAt == null || !now.isBefore(startsAt!)) &&
      (endsAt == null || now.isBefore(endsAt!));

  Map<String, Object?> toJson() => compact({
    'id': id,
    'title': title.toJson(),
    'subtitle': subtitle.toJson(),
    'tag': tag.toJson(),
    'cta': cta.toJson(),
    'action': action.toJson(),
    'look': look.toJson(),
    'startsAt': startsAt?.toIso8601String(),
    'endsAt': endsAt?.toIso8601String(),
    'sort': sort,
  });
}

enum BannerActionType { festival, theme, wallpapers, fonts, iconPacks, url }

/// Where a banner's button goes.
class BannerAction {
  const BannerAction({required this.type, this.id, this.url});

  factory BannerAction.fromJson(JsonReader r) {
    final type = r.enumValue('type', BannerActionType.values);
    return switch (type) {
      BannerActionType.festival ||
      BannerActionType.theme => BannerAction(type: type, id: r.id('id')),
      BannerActionType.url => BannerAction(type: type, url: _https(r)),
      // List screens, optionally pre-filtered by festival.
      _ => BannerAction(type: type, id: r.optId('id')),
    };
  }

  static String _https(JsonReader r) {
    final url = r.string('url');
    if (Uri.tryParse(url)?.scheme != 'https') r.fail('url', 'must be https');
    return url;
  }

  final BannerActionType type;
  final String? id;
  final String? url;

  Map<String, Object?> toJson() =>
      compact({'type': jsonName(type), 'id': id, 'url': url});
}

class BannerLook {
  const BannerLook({
    required this.background,
    required this.accent,
    required this.titleColor,
    required this.font,
    this.artThemeId,
  });

  factory BannerLook.fromJson(JsonReader r) => BannerLook(
    background: r.color('background'),
    accent: r.color('accent'),
    titleColor: r.color('titleColor'),
    font: r.id('font'),
    artThemeId: r.optId('artThemeId'),
  );

  final HexColor background;

  /// The button colour.
  final HexColor accent;
  final HexColor titleColor;
  final String font;

  /// Draw this theme's scene as the banner art; null = plain background.
  final String? artThemeId;

  Map<String, Object?> toJson() => compact({
    'background': background.hex,
    'accent': accent.hex,
    'titleColor': titleColor.hex,
    'font': font,
    'artThemeId': artThemeId,
  });
}

/// The kinds of app the store's previews show an icon pack with (Phone,
/// Messages, …) when it has no real apps to show: a symbol for each, on the
/// pack's tile.
abstract final class GlyphKeys {
  static const all = [
    'phone',
    'messages',
    'camera',
    'maps',
    'music',
    'mail',
    'photos',
    'clock',
    'calendar',
    'settings',
    'browser',
    'weather',
    'notes',
    'calculator',
    'wallet',
    'store',
    'video',
    'contacts',
    'files',
    'health',
  ];
}

enum IconPackKind {
  /// Drawn on the phone by ThemedIconPainter in a built-in style.
  painted,

  /// A downloaded [IconPack.background] tile, with each app's own logo on
  /// it.
  images,
}

enum IconShape { squircle, circle, square, leaf }

class IconPack {
  const IconPack({
    required this.id,
    required this.festivalId,
    required this.name,
    required this.style,
    required this.kind,
    required this.shape,
    required this.tile,
    required this.glyph,
    required this.ring,
    required this.publishedAt,
    this.painter,
    this.background,
    this.popularity = 0,
  });

  factory IconPack.fromJson(JsonReader r) {
    final kind = r.enumValue('kind', IconPackKind.values);
    final rawBackground = r.optObject('background');
    final painter = r.optId('painter');
    if (kind == IconPackKind.painted && painter == null) {
      r.fail('painter', 'a painted pack names its painter style');
    }
    if (kind == IconPackKind.images && rawBackground == null) {
      r.fail('background', 'an image pack needs its background tile');
    }
    return IconPack(
      id: r.id('id'),
      festivalId: r.id('festivalId'),
      name: r.text('name'),
      style: r.text('style'),
      kind: kind,
      painter: painter,
      shape: r.enumValue('shape', IconShape.values),
      tile: r.optColor('tile'),
      glyph: r.color('glyph'),
      ring: r.color('ring'),
      background: rawBackground == null
          ? null
          : AssetRef.fromJson(rawBackground),
      publishedAt: r.time('publishedAt'),
      popularity: r.integer('popularity', orElse: 0),
    );
  }

  final String id;
  final String festivalId;
  final LocalizedText name;

  /// "Neon outline", "Filled".
  final LocalizedText style;
  final IconPackKind kind;

  /// [IconPackKind.painted] only: a built-in engine ID.
  final String? painter;

  /// The default tile shape; users can change it per pack.
  final IconShape shape;

  /// Null = no tile (line icons straight on the wallpaper).
  final HexColor? tile;
  final HexColor glyph;
  final HexColor ring;

  /// [IconPackKind.images] only (required there): the pack's tile picture.
  /// wallp Home puts every app's own logo on it.
  final AssetRef? background;
  final DateTime publishedAt;
  final int popularity;

  /// Every picture the pack downloads.
  Iterable<AssetRef> get assets => [?background];

  int get bytes => assets.fold(0, (sum, a) => sum + a.bytes);

  bool isNew(DateTime now) {
    final age = now.difference(publishedAt);
    return !age.isNegative && age < const Duration(days: 14);
  }

  Map<String, Object?> toJson() => compact({
    'id': id,
    'festivalId': festivalId,
    'name': name.toJson(),
    'style': style.toJson(),
    'kind': kind.name,
    'painter': painter,
    'shape': shape.name,
    'tile': tile?.hex,
    'glyph': glyph.hex,
    'ring': ring.hex,
    'background': background?.toJson(),
    'publishedAt': publishedAt.toIso8601String(),
    'popularity': popularity,
  });
}
