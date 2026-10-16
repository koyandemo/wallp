import '../json.dart';
import 'common.dart';

/// A festival (Halloween, Thingyan) or an undated collection (Minimal).
class Festival {
  const Festival({
    required this.id,
    required this.name,
    required this.kind,
    required this.sort,
    required this.look,
    this.tags = const [],
    this.occurrences = const [],
    this.fallbackDate,
    this.durationDays = 1,
    this.unit = CountdownUnit.day,
    this.comingSoon = false,
    this.coverThemeId,
  });

  factory Festival.fromJson(JsonReader r) {
    final kind = r.enumValue('kind', FestivalKind.values);
    final occurrences = [
      for (final (i, s) in r.strings('occurrences').indexed)
        JsonReader.parseDate(s, '${r.at('occurrences')}[$i]'),
    ];
    for (var i = 1; i < occurrences.length; i++) {
      if (!occurrences[i].isAfter(occurrences[i - 1])) {
        r.fail('occurrences', 'dates must be in order, no repeats');
      }
    }
    final fallback = r.optObject('fallbackDate');
    final festival = Festival(
      id: r.id('id'),
      name: r.text('name'),
      kind: kind,
      sort: r.integer('sort'),
      look: FestivalLook.fromJson(r.object('look')),
      tags: r.strings('tags'),
      occurrences: occurrences,
      fallbackDate: fallback == null ? null : MonthDay.fromJson(fallback),
      durationDays: r.integer('durationDays', orElse: 1),
      unit: r.enumValue(
        'unit',
        CountdownUnit.values,
        orElse: CountdownUnit.day,
      ),
      comingSoon: r.boolean('comingSoon', orElse: false),
      coverThemeId: r.optId('coverThemeId'),
    );
    if (festival.durationDays < 1) r.fail('durationDays', 'must be at least 1');
    if (kind == FestivalKind.festival &&
        occurrences.isEmpty &&
        festival.fallbackDate == null &&
        !festival.comingSoon) {
      r.fail(
        'occurrences',
        'a dated festival needs occurrences or fallbackDate',
      );
    }
    return festival;
  }

  final String id;
  final LocalizedText name;
  final FestivalKind kind;

  /// Lower comes first where festivals have no date to sort by.
  final int sort;
  final FestivalLook look;

  /// Filter tags, e.g. `myanmar` for the Themes "Myanmar" chip.
  final List<String> tags;

  /// Real first-day dates per year, in order. Needed for festivals on the
  /// Myanmar calendar, whose Gregorian date moves.
  final List<DateTime> occurrences;

  /// Used once [occurrences] runs out (or for fixed-date festivals).
  final MonthDay? fallbackDate;

  /// How many days the festival lasts; Thingyan is 4.
  final int durationDays;
  final CountdownUnit unit;
  final bool comingSoon;
  final String? coverThemeId;

  bool get isDated => kind == FestivalKind.festival && !comingSoon;

  /// The festival's next (or current) run, or null if it has no date.
  ///
  /// Uses the first occurrence whose last day is on or after [now]'s date,
  /// falling back to [fallbackDate] once the list runs out.
  FestivalRun? nextRun(DateTime now) {
    if (!isDated) return null;
    final today = _day(now);
    for (final start in occurrences) {
      final run = FestivalRun(_day(start), durationDays);
      if (!run.end.isBefore(today)) return run;
    }
    final fallback = fallbackDate;
    if (fallback == null) return null;
    // Don't fall back to a date before the last listed occurrence.
    final from = occurrences.isEmpty || occurrences.last.year < today.year
        ? today.year
        : occurrences.last.year + 1;
    for (var year = from; year <= from + 1; year++) {
      final run = FestivalRun(fallback.inYear(year), durationDays);
      if (!run.end.isBefore(today)) return run;
    }
    return FestivalRun(fallback.inYear(from + 2), durationDays);
  }

  /// "16 nights left", "Happy Thingyan!" during it, or "Any time".
  Countdown countdown(DateTime now) {
    final run = nextRun(now);
    if (run == null) return const Countdown.anyTime();
    final days = run.daysUntil(now);
    return days <= 0
        ? Countdown.ongoing(name)
        : Countdown(days: days, unit: unit, festivalName: name);
  }

  Map<String, Object?> toJson() => compact({
    'id': id,
    'name': name.toJson(),
    'kind': jsonName(kind),
    'tags': tags.isEmpty ? null : tags,
    'comingSoon': comingSoon ? true : null,
    'sort': sort,
    'occurrences': occurrences.isEmpty
        ? null
        : [for (final d in occurrences) formatDate(d)],
    'fallbackDate': fallbackDate?.toJson(),
    'durationDays': durationDays == 1 ? null : durationDays,
    'unit': kind == FestivalKind.festival ? unit.name : null,
    'look': look.toJson(),
    'coverThemeId': coverThemeId,
  });
}

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

enum FestivalKind {
  /// Has dates and a countdown.
  festival,

  /// A themed collection with no date, like Minimal.
  collection,
}

enum CountdownUnit { day, night }

class MonthDay {
  const MonthDay(this.month, this.day);

  factory MonthDay.fromJson(JsonReader r) {
    final month = r.integer('month');
    final day = r.integer('day');
    if (month < 1 || month > 12) r.fail('month', 'must be 1–12');
    // 29 Feb would vanish three years in four.
    final max = const [
      31,
      28,
      31,
      30,
      31,
      30,
      31,
      31,
      30,
      31,
      30,
      31,
    ][month - 1];
    if (day < 1 || day > max) r.fail('day', 'must be 1–$max');
    return MonthDay(month, day);
  }

  final int month;
  final int day;

  DateTime inYear(int year) => DateTime.utc(year, month, day);

  Map<String, Object?> toJson() => {'month': month, 'day': day};
}

/// One run of a festival: its first day and how long it lasts.
class FestivalRun {
  FestivalRun(this.start, this.durationDays);

  final DateTime start;
  final int durationDays;

  DateTime get end => start.add(Duration(days: durationDays - 1));

  /// Whole days from [now]'s date to the first day; 0 or less while it runs.
  int daysUntil(DateTime now) => start.difference(_day(now)).inDays;

  bool isOn(DateTime now) {
    final today = _day(now);
    return !today.isBefore(start) && !today.isAfter(end);
  }
}

/// What a countdown says. English only for now; the UI layer localizes.
class Countdown {
  const Countdown({
    required int this.days,
    required CountdownUnit this.unit,
    required LocalizedText this.festivalName,
  });

  const Countdown.anyTime() : days = null, unit = null, festivalName = null;

  const Countdown.ongoing(LocalizedText this.festivalName)
    : days = 0,
      unit = null;

  /// Null for undated collections; 0 while the festival runs.
  final int? days;
  final CountdownUnit? unit;
  final LocalizedText? festivalName;

  bool get isAnyTime => days == null;
  bool get isOngoing => days == 0;

  /// For sorting: soonest first, ongoing before upcoming, undated last.
  int get sortKey => days ?? 1 << 30;

  /// "16 nights", "1 day".
  String get value {
    final d = days;
    if (d == null) return 'Any time';
    if (d == 0) return 'Today';
    return '$d ${d == 1 ? unit!.name : '${unit!.name}s'}';
  }

  /// "16 nights left", "Happy Halloween!", "Any time".
  String label([String lang = 'en']) {
    if (isAnyTime) return 'Any time';
    if (isOngoing) return 'Happy ${festivalName!.resolve(lang)}!';
    return '$value left';
  }
}

/// The app's own colours while browsing a festival ("Match app to my theme").
class FestivalLook {
  const FestivalLook({
    required this.background,
    required this.surface,
    required this.surface2,
    required this.outline,
    required this.nav,
    required this.muted,
    required this.brand,
    required this.displayFont,
  });

  factory FestivalLook.fromJson(JsonReader r) => FestivalLook(
    background: r.color('background'),
    surface: r.color('surface'),
    surface2: r.color('surface2'),
    outline: r.color('outline'),
    nav: r.color('nav'),
    muted: r.color('muted'),
    brand: r.color('brand'),
    displayFont: r.id('displayFont'),
  );

  final HexColor background;
  final HexColor surface;
  final HexColor surface2;
  final HexColor outline;
  final HexColor nav;

  /// Secondary text; must stay ≥ 4.5:1 on [background].
  final HexColor muted;
  final HexColor brand;

  /// A font ID from the catalog's fonts.
  final String displayFont;

  Map<String, Object?> toJson() => {
    'background': background.hex,
    'surface': surface.hex,
    'surface2': surface2.hex,
    'outline': outline.hex,
    'nav': nav.hex,
    'muted': muted.hex,
    'brand': brand.hex,
    'displayFont': displayFont,
  };
}
