import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:wallp/data/theme_catalog.dart';
import 'package:wallp/scenes/scene_math.dart';
import 'package:wallp/scenes/scene_view.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('scene math', () {
    test('phase wraps and honours negative delay', () {
      expect(phase(7, 7), closeTo(0, 1e-9));
      expect(phase(0, 9, -3), closeTo(1 / 3, 1e-9));
    });

    test('pingPong goes 0 → 1 → 0', () {
      expect(pingPong(0), closeTo(0, 1e-9));
      expect(pingPong(0.5), closeTo(1, 1e-9));
      expect(pingPong(1), closeTo(0, 1e-9));
    });

    test('keyframes hits each stop value', () {
      const stops = [0.0, 0.25, 0.5, 0.75, 1.0];
      const values = [0.0, -16.0, -30.0, -12.0, 0.0];
      for (var i = 0; i < stops.length; i++) {
        expect(keyframes(stops[i], stops, values), closeTo(values[i], 1e-9));
      }
    });
  });

  testWidgets('every theme scene animates without errors', (tester) async {
    for (final theme in ThemeCatalog.themes) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 195,
              height: 422,
              child: SceneView(theme: theme, animate: true),
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 370));
      }
      expect(tester.takeException(), isNull, reason: theme.id);
    }
    // Unmount so the ticker is disposed before the test ends.
    await tester.pumpWidget(const SizedBox());
  });
}
