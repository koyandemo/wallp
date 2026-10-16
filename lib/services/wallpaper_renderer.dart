import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../models/phone_theme.dart';
import '../scenes/scene_painter.dart';
import '../scenes/scene_view.dart';

/// Turns a theme's scene into a PNG at full screen resolution.
///
/// Only the painted scene is drawn: the phone adds its own clock and icons.
class WallpaperRenderer {
  WallpaperRenderer._();

  static Future<Uint8List> renderPng({
    required PhoneTheme theme,
    required ui.Color accent,
    required ui.Size pixelSize,
  }) async {
    final time = ValueNotifier<double>(kSceneStillTime);
    final painter = scenePainterFor(theme, time, accent);
    if (painter == null) {
      throw StateError('${theme.id} has no painted scene');
    }

    final width = pixelSize.width.round();
    final height = pixelSize.height.round();
    final recorder = ui.PictureRecorder();
    painter.paint(
      ui.Canvas(recorder),
      ui.Size(width.toDouble(), height.toDouble()),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
      time.dispose();
    }
  }
}
