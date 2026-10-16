import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wallp/catalog/catalog.dart';
import 'package:wallp/look/accent_choices.dart';
import 'package:wallp/look/accent_contrast.dart';
import 'package:wallp/look/accent_paint.dart';
import 'package:wallp/look/applied_look.dart';
import 'package:wallp/look/my_accents.dart';
import 'package:wallp/look/resolved_look.dart';
import 'package:wallp/widgets/screen_overlays.dart';

import 'fixtures.dart';

Accent _solid(String hex) =>
    Accent(id: 'a', name: LocalizedText.en('A'), colors: [HexColor(hex)]);

Accent _gradient(List<String> hexes, {int angle = 135}) => Accent(
  id: 'g',
  name: LocalizedText.en('G'),
  colors: [for (final h in hexes) HexColor(h)],
  angle: angle,
);

void main() {
  group('contrast', () {
    const black = HexColor('#000000'), white = HexColor('#FFFFFF');

    test('matches WCAG at the extremes', () {
      expect(contrast(black, white), closeTo(21, 0.01));
      expect(contrast(white, white), 1);
    });

    test('a gradient is only as readable as its faintest stop', () {
      const sky = HexColor('#160C24');
      expect(isReadableClock(_solid('#FFB547'), sky), isTrue);
      expect(isReadableClock(_gradient(['#FFB547', '#2A1033']), sky), isFalse);
    });

    test('labels on an accent: dark on light accents, light on dark', () {
      expect(labelOn(_solid('#FFB547')).hex, '#0E0C12');
      expect(labelOn(_solid('#2A1033')).hex, '#F5F1EA');
      // Judged by each colour's worst stop: light candle colours take
      // dark text, a deep plum-to-red gradient light text. With one light
      // and one dark stop, the colour whose worst case is better wins.
      expect(labelOn(_gradient(['#FFE08A', '#FFB547'])).hex, '#0E0C12');
      expect(labelOn(_gradient(['#2A1033', '#7A0A1E'])).hex, '#F5F1EA');
      expect(labelOn(_gradient(['#FFB547', '#7A0A1E'])).hex, '#0E0C12');
    });
  });

  group('CSS angles become Flutter gradients', () {
    LinearGradient g(int deg) =>
        cssLinearGradient(deg, const [Colors.black, Colors.white]);

    test('90° runs left to right, 180° top to bottom', () {
      expect(g(90).begin, Alignment.centerLeft);
      expect(g(90).end, Alignment.centerRight);
      expect(g(180).begin, Alignment.topCenter);
      expect(g(180).end, Alignment.bottomCenter);
    });

    test('diagonals run corner to corner', () {
      expect(g(135).begin, Alignment.topLeft);
      expect(g(135).end, Alignment.bottomRight);
      expect(g(45).begin, Alignment.bottomLeft);
      expect(g(45).end, Alignment.topRight);
    });

    test('a solid accent has no gradient; a gradient keeps its stops', () {
      expect(_solid('#FF7A1A').gradient, isNull);
      expect(_gradient(['#FFE08A', '#FF7A1A', '#D7263D']).gradient!.colors, [
        const Color(0xFFFFE08A),
        const Color(0xFFFF7A1A),
        const Color(0xFFD7263D),
      ]);
    });
  });

  group('the picker\'s choices', () {
    final catalog = mockCatalog();
    final halloween = mockTheme('halloween-night');

    test('the theme first, then presets it doesn\'t already offer', () {
      final choices = AccentChoices.forTheme(
        halloween,
        catalog.accentPresets,
        const [],
      );
      expect(choices.theme, halloween.accents);
      // Halloween offers "Pumpkin glow" itself, so the preset is skipped.
      expect(
        choices.gradients.map((a) => a.id),
        isNot(contains('pumpkin-glow')),
      );
      expect(choices.gradients, hasLength(5));
      expect(choices.solids, hasLength(10));
    });

    test('readability is judged on the variant\'s sky', () {
      final christmas = mockTheme('christmas-eve');
      final dark = AccentChoices.forTheme(
        christmas,
        catalog.accentPresets,
        const [],
        variantId: 'midnight',
      );
      expect(dark.background.hex, '#10223D');
      expect(dark.isReadable(_solid('#F5F1EA')), isTrue);
      expect(dark.isReadable(_solid('#10223D')), isFalse);
    });

    test('a custom gradient must use one of the four directions', () {
      expect(
        () => customAccent(
          id: 'x',
          name: 'X',
          start: const HexColor('#FF7A1A'),
          end: const HexColor('#E0245E'),
          angle: 30,
        ),
        throwsArgumentError,
      );
      final solid = customAccent(
        id: 'x',
        name: 'X',
        start: const HexColor('#FF7A1A'),
      );
      expect(solid.type, AccentType.solid);
    });
  });

  group('My accents', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test('newest first, named Mine 1, 2…, and kept after a restart', () async {
      final mine = MyAccents();
      await mine.load();
      final a = await mine.add(start: const HexColor('#FF7A1A'));
      final b = await mine.add(
        start: const HexColor('#A970FF'),
        end: const HexColor('#FF5FA2'),
      );
      expect(mine.accents.map((x) => x.name.en), ['Mine 2', 'Mine 1']);
      expect(b.type, AccentType.gradient);

      final again = MyAccents();
      await again.load();
      expect(again.accents.map((x) => x.id), [b.id, a.id]);
    });

    test('saving the same colours again moves it up, no duplicate', () async {
      final mine = MyAccents();
      await mine.load();
      final a = await mine.add(start: const HexColor('#FF7A1A'));
      await mine.add(start: const HexColor('#A970FF'));
      final again = await mine.add(start: const HexColor('#ff7a1a'));
      expect(again.id, a.id);
      expect(mine.accents, hasLength(2));
      expect(mine.accents.first.id, a.id);
    });

    test('keeps the newest 6, and never reuses a name', () async {
      final mine = MyAccents();
      await mine.load();
      for (var i = 0; i < 8; i++) {
        await mine.add(
          start: HexColor(
            '#${(0x101010 * (i + 1)).toRadixString(16).padLeft(6, '0')}',
          ),
        );
      }
      expect(mine.accents, hasLength(MyAccents.limit));
      expect(mine.accents.first.name.en, 'Mine 8');
      await mine.remove(mine.accents.first.id);
      final next = await mine.add(start: const HexColor('#ABCDEF'));
      expect(next.name.en, 'Mine 9');
    });
  });

  group('on screen', () {
    final catalog = mockCatalog();

    AppliedLook halloweenIn(Accent accent) => AppliedLook.wholeTheme(
      catalog,
      mockTheme('halloween-night'),
      at: designDay,
    ).withAccent(accent, at: designDay);

    test('a gradient accent paints the clock only when the clock uses it', () {
      final glow = mockTheme('halloween-night').accentById('pumpkin-glow')!;
      final look = halloweenIn(glow);
      expect(ResolvedLook.of(look, designDay).clockGradient, isNotNull);
      final textClock = look.withClockFont(
        catalog.font('creepster')!,
        at: designDay,
        color: const ClockColor.text(),
      );
      expect(ResolvedLook.of(textClock, designDay).clockGradient, isNull);
      // The countdown badge still uses the gradient.
      expect(ResolvedLook.of(textClock, designDay).accentGradient, isNotNull);
    });

    test('a solid accent paints no gradient anywhere', () {
      final r = ResolvedLook.of(halloweenIn(_solid('#7BD44A')), designDay);
      expect(r.clockGradient, isNull);
      expect(r.accentGradient, isNull);
    });

    testWidgets('the lock screen clock is painted with the gradient', (
      tester,
    ) async {
      final glow = mockTheme('halloween-night').accentById('pumpkin-glow')!;
      final r = ResolvedLook.of(halloweenIn(glow), designDay);
      await tester.pumpWidget(
        MaterialApp(
          home: LockScreenOverlay(
            theme: r.lockTheme,
            accent: r.accent,
            now: designDay,
            clockColor: r.clockColor,
            clockGradient: r.clockGradient,
            accentGradient: r.accentGradient,
            onAccent: r.onAccent,
          ),
        ),
      );
      final clock = find.ancestor(
        of: find.text('7:47'),
        matching: find.byType(ShaderMask),
      );
      expect(clock, findsOneWidget);
      final badge = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.shape == BoxShape.circle);
      expect(badge.single.gradient, isA<LinearGradient>());
    });
  });
}
