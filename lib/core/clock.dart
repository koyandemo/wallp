/// "Now", replaceable so countdowns, NEW badges and banner windows can be
/// tested, and so developers can preview another date (Developer settings).
abstract class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// A clock that reports a fixed day while keeping the real time of day
/// running, so the lock screen clock still ticks.
class ShiftedClock implements Clock {
  ShiftedClock(this.pretendToday, {this.base = const SystemClock()});

  final DateTime pretendToday;
  final Clock base;

  @override
  DateTime now() {
    final real = base.now();
    return DateTime(
      pretendToday.year,
      pretendToday.month,
      pretendToday.day,
      real.hour,
      real.minute,
      real.second,
      real.millisecond,
    );
  }
}

/// Always the same moment; for tests.
class FixedClock implements Clock {
  FixedClock(this.moment);

  DateTime moment;

  @override
  DateTime now() => moment;
}
