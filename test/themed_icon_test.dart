import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wallp/data/theme_catalog.dart';
import 'package:wallp/icons/themed_icon_painter.dart';
import 'package:wallp/models/phone_theme.dart';

void main() {
  test('every festival style paints, with a glyph and without', () {
    for (final style in SceneKind.values) {
      for (final glyph in [Icons.phone_rounded, null]) {
        final recorder = ui.PictureRecorder();
        ThemedIconPainter(
          style: style,
          accent: const Color(0xFFFF8A2A),
          glyph: glyph,
        ).paint(ui.Canvas(recorder), const Size.square(432));
        recorder.endRecording().dispose();
      }
    }
  });

  test('glyph uses the accent only when it reads on the tile', () {
    final christmas = ThemeCatalog.byId('christmas-eve')!;
    final red = christmas.palette.accentOptions[0];
    const paleGold = Color(0xFFFFE08A);
    ThemedIconPainter painter(Color accent) =>
        ThemedIconPainter(style: SceneKind.christmas, accent: accent);

    // Christmas red on pine green is too dark: fall back to cream.
    expect(painter(red).glyphColor, const Color(0xFFFFF6E5));
    expect(painter(paleGold).glyphColor, paleGold);

    final halloween = ThemeCatalog.byId('halloween-night')!;
    expect(
      ThemedIconPainter(
        style: SceneKind.halloween,
        accent: halloween.palette.accent,
      ).glyphColor,
      halloween.palette.accent,
    );
  });

  test('Thingyan keeps its yellow accent on the glyph', () {
    final thingyan = ThemeCatalog.byId('thingyan-water')!;
    final yellow = thingyan.palette.accent;
    expect(
      ThemedIconPainter(style: SceneKind.thingyan, accent: yellow).glyphColor,
      yellow,
    );
  });

  test('contrastRatio', () {
    expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
    expect(contrastRatio(Colors.white, Colors.white), closeTo(1, 0.01));
  });

  test('all themes now offer icon packs', () {
    expect(ThemeCatalog.themes.every((t) => t.hasIconPack), isTrue);
  });
}
