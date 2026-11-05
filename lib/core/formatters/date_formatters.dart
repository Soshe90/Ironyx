import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n_extension.dart';
import 'week_start.dart';

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
        _weekdayShort = DateFormat('EEE', _l10n.localeName),
        _dayOfMonth = DateFormat('d', _l10n.localeName),
        _monthYear = DateFormat('MMMM yyyy', _l10n.localeName),
        _time = DateFormat.jm(_l10n.localeName);

  /// Cached per locale: building five [DateFormat]s is not free, and these
  /// are read from `build` methods that run on every frame of a scroll.
  static final Map<String, DateFormatters> _cache = <String, DateFormatters>{};

  factory DateFormatters.of(BuildContext context) =>
      DateFormatters.forLocalizations(context.l10n);

  /// The context-free form, for tests and for the rare caller that already
  /// holds an [AppLocalizations] (see `appLocalizationsProvider`).
  factory DateFormatters.forLocalizations(AppLocalizations l10n) =>
      _cache.putIfAbsent(l10n.localeName, () => DateFormatters._(l10n));

  final AppLocalizations _l10n;
  final DateFormat _dayMonth;
  final DateFormat _dayMonthYear;
  final DateFormat _weekday;
  final DateFormat _weekdayDayMonth;
  final DateFormat _weekdayShort;
  final DateFormat _dayOfMonth;
  final DateFormat _monthYear;
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

  /// `Tue` — the weekday on a history row's date tile.
  String weekdayShort(DateTime date) => _format(_weekdayShort, date);

  /// `15` — the day number on a history row's date tile.
  String dayOfMonth(DateTime date) => _format(_dayOfMonth, date);

  /// `September 2026` — a month heading in the workout history.
  String monthYear(DateTime date) => _format(_monthYear, date);

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
      toWesternDigits(format.format(date).replaceAll('\u202f', ' '));

  /// U+0660..U+0669 (Arabic-Indic) mapped back onto ASCII `0`..`9`.
  ///
  /// Public so callers formatting a date outside the fixed set above (e.g.
  /// a raw `DateFormat('MMMM yyyy', locale)`) can still follow the app's
  /// Western-digit policy without duplicating this table.
  static String toWesternDigits(String value) {
    const int arabicZero = 0x0660;
    return String.fromCharCodes(<int>[
      for (final int unit in value.codeUnits)
        if (unit >= arabicZero && unit <= arabicZero + 9)
          unit - arabicZero + 0x30
        else
          unit,
    ]);
  }

  /// The first day of the week [date] falls in, as local midnight, for a
  /// week that begins on [weekStart].
  ///
  /// Steps by calendar day rather than by 24-hour days: subtracting a
  /// `Duration` from local midnight lands on 23:00 the day before whenever
  /// a daylight-saving change lies in between.
  static DateTime startOfWeek(DateTime date, WeekStart weekStart) => DateTime(
        date.year,
        date.month,
        date.day - weekStart.indexOf(date.weekday),
      );

  /// The weekly bucket the analytics queries file [instant] under, as a
  /// local-midnight `DateTime`.
  ///
  /// The queries bucket in SQL with
  /// `date(started_at + offset, 'unixepoch', 'weekday N', '-6 days')`
  /// (see `WorkoutDao`), which resolves the stored epoch in UTC after
  /// shifting it by a fixed [utcOffset]. Anything that has to name the same
  /// bucket in Dart, such as gap-filling or finding "this week" in a series,
  /// must derive the day the same way, so it goes through here with the
  /// same [weekStart] and [utcOffset] the query was given. [startOfWeek] on
  /// a local time agrees with it except within an hour of midnight in a
  /// week where the clocks change.
  static DateTime weekBucketStart(
    DateTime instant, {
    required WeekStart weekStart,
    required Duration utcOffset,
  }) {
    final DateTime shifted = instant.toUtc().add(utcOffset);
    return startOfWeek(
      DateTime(shifted.year, shifted.month, shifted.day),
      weekStart,
    );
  }

  /// The next weekly bucket after [weekStart].
  ///
  /// Steps by calendar day so a `+7 days` hop across a daylight-saving
  /// boundary cannot land on 23:00 the previous day and desynchronise the
  /// sequence.
  static DateTime nextWeek(DateTime weekStart) => DateTime(
        weekStart.year,
        weekStart.month,
        weekStart.day + DateTime.daysPerWeek,
      );

  /// The weekly bucket before [weekStart]. See [nextWeek].
  static DateTime previousWeek(DateTime weekStart) => DateTime(
        weekStart.year,
        weekStart.month,
        weekStart.day - DateTime.daysPerWeek,
      );

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
