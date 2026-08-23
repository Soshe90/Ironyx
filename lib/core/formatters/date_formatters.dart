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

  /// Monday-based week start derived from the *UTC* calendar day, returned
  /// as a local-midnight `DateTime`.
  ///
  /// This is the bucket SQLite produces for
  /// `date(started_at, 'unixepoch', 'weekday 0', '-6 days')` once drift hands
  /// it back and `DateTime.parse` reads it as a bare date. That expression
  /// resolves the stored epoch in UTC, so gap-filling those buckets has to
  /// use the UTC calendar day too — [startOfWeek] would land a week off for
  /// any workout logged near midnight in a non-UTC zone.
  static DateTime utcWeekStart(DateTime instant) {
    final DateTime utc = instant.toUtc();
    final DateTime monday = DateTime.utc(utc.year, utc.month, utc.day)
        .subtract(Duration(days: utc.weekday - DateTime.monday));
    return DateTime(monday.year, monday.month, monday.day);
  }

  /// The next weekly bucket after [weekStart].
  ///
  /// Steps through UTC so a `+7 days` hop across a daylight-saving boundary
  /// cannot land on 23:00 the previous day and desynchronise the sequence.
  static DateTime nextWeek(DateTime weekStart) {
    final DateTime next =
        DateTime.utc(weekStart.year, weekStart.month, weekStart.day)
            .add(const Duration(days: DateTime.daysPerWeek));
    return DateTime(next.year, next.month, next.day);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
