import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n_extension.dart';

/// Date rendering, plus the pure week-bucket maths the analytics queries need.
///
/// The formatting half is locale-dependent, so it hangs off an instance built
/// from a `BuildContext` ([DateFormatters.of]). The maths half is not, and
/// stays static — the DAOs that bucket workouts by week run nowhere near a
/// widget tree.
final class DateFormatters {
  DateFormatters._(this._l10n)
      : _dayMonth = DateFormat('d MMM', _l10n.localeName),
        _dayMonthYear = DateFormat('d MMM yyyy', _l10n.localeName),
        _weekday = DateFormat('EEEE', _l10n.localeName),
        _weekdayDayMonth = DateFormat('EEEE, d MMM', _l10n.localeName),
        _time = DateFormat.jm(_l10n.localeName);

  /// Cached per locale: building five [DateFormat]s is not free, and these
  /// are read from `build` methods that run on every frame of a scroll.
  static final Map<String, DateFormatters> _cache = <String, DateFormatters>{};

  factory DateFormatters.of(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return _cache.putIfAbsent(l10n.localeName, () => DateFormatters._(l10n));
  }

  final AppLocalizations _l10n;
  final DateFormat _dayMonth;
  final DateFormat _dayMonthYear;
  final DateFormat _weekday;
  final DateFormat _weekdayDayMonth;
  final DateFormat _time;

  /// `Monday, 21 Aug` — the dateline above the dashboard's primary action.
  String dayHeadline(DateTime date) => _format(_weekdayDayMonth, date);

  /// `1 Aug` — chart axis ticks.
  ///
  /// Deliberately *not* [relativeDay]: that switches between weekday names
  /// and dates depending on recency, which on an axis produces a row like
  /// "1 Aug · 7 Aug · Wednesday · Today" where the reader cannot tell the
  /// spacing. An axis needs one stable format.
  String axisLabel(DateTime date) => _format(_dayMonth, date);

  /// `Today`, `Yesterday`, `Tuesday` within the last week, then a date.
  String relativeDay(DateTime date, {DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final int days = _dateOnly(reference).difference(_dateOnly(date)).inDays;

    return switch (days) {
      0 => _l10n.commonToday,
      1 => _l10n.commonYesterday,
      >= 2 && < 7 => _format(_weekday, date),
      _ when date.year == reference.year => _format(_dayMonth, date),
      _ => _format(_dayMonthYear, date),
    };
  }

  String time(DateTime date) => _format(_time, date);

  String full(DateTime date) => _format(_dayMonthYear, date);

  /// Runs [format] and normalises the result for display.
  ///
  /// Two fixes, both cosmetic:
  ///
  /// * U+202F (narrow no-break space) is what recent CLDR data puts before
  ///   AM/PM. It renders as a missing-glyph box in some fonts.
  /// * `intl` renders Arabic dates with Arabic-Indic digits (`\u0662\u0661 \u0623\u063a\u0633\u0637\u0633`).
  ///   Every other number in the app is Western \u2014 `NumberFormat` already
  ///   emits `1,234` for `ar` \u2014 so leaving dates alone would put the two
  ///   numbering systems side by side on the same screen.
  String _format(DateFormat format, DateTime date) =>
      _toWesternDigits(format.format(date).replaceAll('\u202f', ' '));

  /// U+0660..U+0669 (Arabic-Indic) mapped back onto ASCII `0`..`9`.
  static String _toWesternDigits(String value) {
    const int arabicZero = 0x0660;
    return String.fromCharCodes(<int>[
      for (final int unit in value.codeUnits)
        if (unit >= arabicZero && unit <= arabicZero + 9)
          unit - arabicZero + 0x30
        else
          unit,
    ]);
  }

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
