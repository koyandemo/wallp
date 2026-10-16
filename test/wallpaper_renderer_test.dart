import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:wallp/data/theme_catalog.dart';
import 'package:wallp/services/wallpaper_renderer.dart';

void main() {
  testWidgets('renders every theme to a PNG of the requested size', (
    tester,
  ) async {
    for (final theme in ThemeCatalog.themes) {
      final png = await tester.runAsync(
        () => WallpaperRenderer.renderPng(
          theme: theme,
          accent: theme.palette.accent,
          pixelSize: const ui.Size(120, 260),
        ),
      );
      expect(png!.sublist(1, 4), 'PNG'.codeUnits, reason: theme.id);
      // PNG IHDR: width and height are big-endian ints at bytes 16 and 20.
      final header = ByteData.sublistView(png, 16, 24);
      expect(header.getUint32(0), 120, reason: theme.id);
      expect(header.getUint32(4), 260, reason: theme.id);
    }
  });
}
