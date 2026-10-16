/// Small date helpers so we don't need the intl package yet.
class DateFormatX {
  DateFormatX._();

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// "Wednesday, 14 October"
  static String longDate(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

  /// "Sat 31 Oct"
  static String shortDate(DateTime d) =>
      '${_weekdays[d.weekday - 1].substring(0, 3)} ${d.day} '
      '${_months[d.month - 1].substring(0, 3)}';

  /// "Just now", "5 min ago", "Today, 18:20", "Yesterday" or "Sat 31 Oct".
  static String ago(DateTime then, DateTime now, {bool use24h = true}) {
    final diff = now.difference(then);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(then.year, then.month, then.day);
    if (day == today) return 'Today, ${clock(then, use24h: use24h)}';
    if (today.difference(day).inDays == 1) return 'Yesterday';
    return shortDate(then);
  }

  /// "9:41" (12-hour, like a lock screen) or "21:41" when [use24h].
  static String clock(DateTime d, {bool use24h = false}) {
    final minutes = d.minute.toString().padLeft(2, '0');
    if (use24h) return '${d.hour.toString().padLeft(2, '0')}:$minutes';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:$minutes';
  }
}
