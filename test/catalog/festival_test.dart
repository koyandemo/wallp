import 'package:flutter_test/flutter_test.dart';
import 'package:wallp/catalog/catalog.dart';

FestivalLook get _look => const FestivalLook(
  background: HexColor('#0E0C12'),
  surface: HexColor('#1A1720'),
  surface2: HexColor('#26222E'),
  outline: HexColor('#332E3D'),
  nav: HexColor('#15121B'),
  muted: HexColor('#A39DAE'),
  brand: HexColor('#FFB547'),
  displayFont: 'sora',
);

Festival _festival({
  List<DateTime> occurrences = const [],
  MonthDay? fallback,
  int durationDays = 1,
  CountdownUnit unit = CountdownUnit.day,
  FestivalKind kind = FestivalKind.festival,
  bool comingSoon = false,
}) => Festival(
  id: 'f',
  name: LocalizedText.en('Thingyan'),
  kind: kind,
  sort: 0,
  look: _look,
  occurrences: occurrences,
  fallbackDate: fallback,
  durationDays: durationDays,
  unit: unit,
  comingSoon: comingSoon,
);

void main() {
  group('Festival.countdown', () {
    final halloween = _festival(
      fallback: const MonthDay(10, 31),
      unit: CountdownUnit.night,
    );

    test('counts nights to a fixed-date festival', () {
      final c = halloween.countdown(DateTime(2026, 10, 15, 23, 59));
      expect(c.days, 16);
      expect(c.label(), '16 nights left');
    });

    test('says 1 night, not 1 nights', () {
      expect(
        halloween.countdown(DateTime(2026, 10, 30)).label(),
        '1 night left',
      );
    });

    test('greets on the day, then rolls over to next year', () {
      expect(
        halloween.countdown(DateTime(2026, 10, 31)).label(),
        'Happy Thingyan!',
      );
      expect(
        halloween.nextRun(DateTime(2026, 11, 1))!.start,
        DateTime.utc(2027, 10, 31),
      );
    });

    final thingyan = _festival(
      occurrences: [DateTime(2027, 4, 13), DateTime(2028, 4, 14)],
      fallback: const MonthDay(4, 13),
      durationDays: 4,
    );

    test('uses the listed occurrence, not the fallback date', () {
      expect(
        thingyan.nextRun(DateTime(2027, 5, 1))!.start,
        DateTime.utc(2028, 4, 14),
      );
    });

    test('stays "happening now" for every day of a multi-day festival', () {
      for (var day = 13; day <= 16; day++) {
        expect(
          thingyan.countdown(DateTime(2027, 4, day)).isOngoing,
          isTrue,
          reason: '$day April',
        );
      }
      expect(thingyan.countdown(DateTime(2027, 4, 17)).isOngoing, isFalse);
    });

    test('falls back to the fixed date after the list runs out', () {
      // 2028 is the last listed year, so 2029 uses 13 April.
      expect(
        thingyan.nextRun(DateTime(2028, 6, 1))!.start,
        DateTime.utc(2029, 4, 13),
      );
    });

    test('never falls back to a year the list already covered', () {
      // List ends with 2028-04-14; on 2028-04-20 the next run is 2029.
      expect(
        thingyan.nextRun(DateTime(2028, 4, 20))!.start,
        DateTime.utc(2029, 4, 13),
      );
    });

    test('has no date once the list runs out with no fallback', () {
      final listed = _festival(occurrences: [DateTime(2027, 10, 11)]);
      expect(listed.nextRun(DateTime(2027, 10, 12)), isNull);
      expect(listed.countdown(DateTime(2027, 10, 12)).isAnyTime, isTrue);
    });

    test('collections and coming-soon festivals are "Any time"', () {
      final minimal = _festival(kind: FestivalKind.collection);
      final soon = _festival(comingSoon: true, fallback: const MonthDay(9, 1));
      for (final f in [minimal, soon]) {
        final c = f.countdown(DateTime(2026, 10, 15));
        expect(c.isAnyTime, isTrue);
        expect(c.label(), 'Any time');
      }
    });

    test('sorts ongoing first, undated last', () {
      final now = DateTime(2027, 4, 14);
      final keys = [
        halloween.countdown(now).sortKey,
        thingyan.countdown(now).sortKey,
        _festival(kind: FestivalKind.collection).countdown(now).sortKey,
      ];
      expect(keys[1], lessThan(keys[0]));
      expect(keys[0], lessThan(keys[2]));
    });

    test('counts across a daylight-saving change by calendar days', () {
      // Local times either side of a DST switch still differ by whole days.
      final f = _festival(fallback: const MonthDay(11, 5));
      expect(f.countdown(DateTime(2026, 10, 30, 23, 30)).days, 6);
    });
  });

  group('Festival.fromJson', () {
    Map<String, Object?> json([Map<String, Object?> extra = const {}]) => {
      'id': 'thingyan',
      'name': {'en': 'Thingyan', 'my': 'သင်္ကြန်'},
      'kind': 'festival',
      'sort': 30,
      'look': {
        'background': '#062848',
        'surface': '#0C375F',
        'surface2': '#124570',
        'outline': '#1E5A8C',
        'nav': '#083054',
        'muted': '#B6D0E8',
        'brand': '#FFC21A',
        'displayFont': 'baloo-2',
      },
      'occurrences': ['2027-04-13', '2028-04-13'],
      ...extra,
    };

    Festival parse(Map<String, Object?> j) =>
        Festival.fromJson(JsonReader(j.cast<String, dynamic>(), 'f'));

    test('reads names in both languages', () {
      final f = parse(json());
      expect(f.name.resolve('my'), 'သင်္ကြန်');
      expect(f.name.resolve('th'), 'Thingyan');
    });

    test('rejects dates out of order', () {
      expect(
        () => parse(
          json({
            'occurrences': ['2028-04-13', '2027-04-13'],
          }),
        ),
        throwsA(isA<CatalogFormatException>()),
      );
    });

    test('rejects impossible dates instead of rolling them over', () {
      expect(
        () => parse(
          json({
            'occurrences': ['2027-02-31'],
          }),
        ),
        throwsA(
          isA<CatalogFormatException>().having(
            (e) => e.path,
            'path',
            'f.occurrences[0]',
          ),
        ),
      );
    });

    test('rejects 29 February as a yearly fallback', () {
      expect(
        () => parse(
          json({
            'fallbackDate': {'month': 2, 'day': 29},
          }),
        ),
        throwsA(isA<CatalogFormatException>()),
      );
    });

    test('a dated festival needs some date', () {
      expect(
        () => parse(json({'occurrences': []})),
        throwsA(isA<CatalogFormatException>()),
      );
    });
  });
}
