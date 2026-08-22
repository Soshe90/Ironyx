import 'package:intl/intl.dart';

abstract final class DateFormatters {
  static final DateFormat _dayMonth = DateFormat('d MMM');
  static final DateFormat _dayMonthYear = DateFormat('d MMM yyyy');
  static final DateFormat _weekday = DateFormat('EEEE');
  static final DateFormat _weekdayDayMonth = DateFormat('EEEE, d MMM');
  static final DateFormat _time = DateFormat.jm();

  /// `Monday, 21 Aug` — the dateline above the dashboard's primary action.
  static String dayHeadline(DateTime date) => _weekdayDayMonth.format(date);

  /// `1 Aug` — chart axis ticks.
  ///
  /// Deliberately *not* [relativeDay]: that switches between weekday names
  /// and dates depending on recency, which on an axis produces a row like
  /// "1 Aug · 7 Aug · Wednesday · Today" where the reader cannot tell the
  /// spacing. An axis needs one stable format.
  static String axisLabel(DateTime date) => _dayMonth.format(date);

  /// `Today`, `Yesterday`, `Tuesday` within the last week, then a date.
  static String relativeDay(DateTime date, {DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final int days = _dateOnly(reference).difference(_dateOnly(date)).inDays;

    return switch (days) {
      0 => 'Today',
      1 => 'Yesterday',
      >= 2 && < 7 => _weekday.format(date),
      _ when date.year == reference.year => _dayMonth.format(date),
      _ => _dayMonthYear.format(date),
    };
  }

  static String time(DateTime date) =>
      _time.format(date).replaceAll('\u202f', ' ');

  static String full(DateTime date) => _dayMonthYear.format(date);

  /// Monday-based week start, used for weekly volume buckets (M5).
  static DateTime startOfWeek(DateTime date) {
    final DateTime d = _dateOnly(date);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
