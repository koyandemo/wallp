import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show CustomPainter, IconData;
import 'package:flutter/services.dart';

import '../icons/app_glyphs.dart';
import '../icons/themed_icon_painter.dart';
import '../models/phone_theme.dart';
import '../render/image_icons.dart';
import '../render/scene_assets.dart';
import 'wallpaper_service.dart';

/// An app installed on the phone that can get a themed icon.
class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.label,
    this.icon,
  });

  final String packageName;
  final String label;

  /// The app's own launcher icon, used when there's no themed glyph.
  final ui.Image? icon;

  IconData? get glyph => glyphFor(packageName, label);

  /// Which picture a downloaded icon pack draws it with, if any.
  String? get glyphKey => glyphKeyFor(packageName, label);
}

/// Adds themed app icons to the home screen as pinned shortcuts (Android 8+).
/// Talks to MainActivity.kt over the `wallp/icons` channel.
class IconPackService {
  const IconPackService();

  static const _channel = MethodChannel('wallp/icons');

  /// Size of the adaptive-icon bitmap sent to the launcher (108dp @ 4x).
  static const iconPixels = 432;

  Future<bool> canPinShortcuts() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('canPinShortcuts') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<List<InstalledApp>> installedApps() async {
    try {
      final raw = await _channel.invokeListMethod<Map>('listApps') ?? [];
      // Decode all icons at once rather than one after another.
      return await Future.wait(raw.map(_toApp));
    } on PlatformException catch (e) {
      throw WallpaperException(e.message ?? "Couldn't load your apps");
    }
  }

  /// One app by package, or null if it has no launcher icon (or is gone).
  Future<InstalledApp?> app(String packageName) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('getApp', {
        'package': packageName,
      });
      return raw == null ? null : await _toApp(raw);
    } on PlatformException {
      return null;
    }
  }

  Future<InstalledApp> _toApp(Map raw) async => InstalledApp(
    packageName: raw['package'] as String,
    label: raw['label'] as String,
    icon: await _decode(raw['icon'] as Uint8List?),
  );

  /// Asks the launcher to add [app] with [theme]'s icon style. Returns false
  /// if the launcher declined to show its confirm dialog.
  Future<bool> pin({
    required PhoneTheme theme,
    required InstalledApp app,
    required ui.Color accent,
    SceneAssets? assets,
  }) async {
    // A downloaded pack sends its picture as is (already a tile).
    assets ??= SceneAssets.shared;
    final picture = theme.imageIcons?.pictureFor(app.glyphKey);
    final downloaded = picture == null ? null : await assets.bytes(picture);
    final background = switch (theme.imageIcons?.background) {
      final ref? when downloaded == null => await assets.image(ref),
      _ => null,
    };
    final png =
        downloaded ??
        await _renderIcon(_painterFor(theme, app, accent, background));
    try {
      return await _channel.invokeMethod<bool>('pinShortcut', {
            'id': '${theme.id}-${app.packageName}',
            'package': app.packageName,
            'label': app.label,
            'icon': png,
          }) ??
          false;
    } on PlatformException catch (e) {
      throw WallpaperException(e.message ?? "Couldn't add the icon");
    }
  }

  /// How [app] is drawn when [theme]'s pack has no picture for it.
  CustomPainter _painterFor(
    PhoneTheme theme,
    InstalledApp app,
    ui.Color accent,
    ui.Image? background,
  ) {
    // A downloaded pack: the app's own icon framed in the pack's tile (or on
    // its background picture), small enough to stay inside the launcher's
    // mask.
    if (theme.imageIcons case final pack?) {
      return PackFallbackPainter(
        pack: pack,
        appIcon: app.icon,
        background: background,
        iconScale: 0.42,
      );
    }
    final style = theme.iconStyle;
    if (style == null) {
      throw const WallpaperException("This theme has no icon for this app");
    }
    return ThemedIconPainter(
      style: style,
      accent: accent,
      glyph: app.glyph,
      appIcon: app.icon,
    );
  }

  Future<Uint8List> _renderIcon(CustomPainter painter) async {
    final recorder = ui.PictureRecorder();
    const size = ui.Size.square(iconPixels + 0.0);
    painter.paint(ui.Canvas(recorder), size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(iconPixels, iconPixels);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  Future<ui.Image?> _decode(Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    }
  }
}
