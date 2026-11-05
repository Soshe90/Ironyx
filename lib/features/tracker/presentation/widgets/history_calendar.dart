import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/formatters/date_formatters.dart';
import '../../../../core/formatters/week_start.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_spacing.dart';

/// Month-grid view of workout history: a marker on every day that has at
/// least one logged workout, tap-to-drill-in via [onDayTap].
///
/// Purely a different lens on the same data the list view already shows —
/// no new query, no new persisted state (the caller owns [visibleMonth]).
class HistoryCalendar extends StatelessWidget {
  const HistoryCalendar({
    required this.visibleMonth,
    required this.today,
    required this.weekStart,
    required this.markedDates,
    required this.onMonthChanged,
    required this.onDayTap,
    super.key,
  });

  /// Any date within the month to display — only year/month are used.
  final DateTime visibleMonth;

  /// The current local date, from `todayProvider`. Passed in rather than
  /// read from the clock so the "today" ring and the next-month limit move
  /// when the day does, and so tests can pin the date.
  final DateTime today;

  /// The day the grid's first column is, from Settings.
  final WeekStart weekStart;

  /// Date-only (`DateTime(y, m, d)`) dates that have at least one workout.
  final Set<DateTime> markedDates;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDayTap;

  /// Rebuilt per locale so the month name follows the app's language.
  static final Map<String, DateFormat> _monthYearByLocale =
      <String, DateFormat>{};

  static DateFormat _monthYear(String locale) => _monthYearByLocale.putIfAbsent(
        locale,
        () => DateFormat('MMMM yyyy', locale),
      );

  bool get _isCurrentMonth =>
      visibleMonth.year == today.year && visibleMonth.month == today.month;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DateTime todayDate = _dateOnly(today);
    final List<DateTime?> cells = _gridDays(visibleMonth, weekStart);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: context.l10n.calendarPreviousMonth,
              onPressed: () => onMonthChanged(
                DateTime(visibleMonth.year, visibleMonth.month - 1),
              ),
            ),
            Expanded(
              child: Text(
                DateFormatters.toWesternDigits(
                  _monthYear(context.localeName).format(visibleMonth),
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: context.l10n.calendarNextMonth,
              onPressed: _isCurrentMonth
                  ? null
                  : () => onMonthChanged(
                        DateTime(visibleMonth.year, visibleMonth.month + 1),
                      ),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            for (final label in _weekdayLabels(context.localeName, weekStart))
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        for (var week = 0; week < cells.length ~/ 7; week++)
          Row(
            children: <Widget>[
              for (var weekday = 0; weekday < 7; weekday++)
                Expanded(
                  child: _DayCell(
                    date: cells[week * 7 + weekday],
                    isToday: cells[week * 7 + weekday] == todayDate,
                    isMarked: cells[week * 7 + weekday] != null &&
                        markedDates.contains(cells[week * 7 + weekday]),
                    onTap: onDayTap,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// Grid cells for [month] with [weekStart] in the first column, padded
  /// with `null`s so the total count is a multiple of 7. `null` cells render
  /// blank and ignore taps.
  static List<DateTime?> _gridDays(DateTime month, WeekStart weekStart) {
    final DateTime first = DateTime(month.year, month.month, 1);
    final int daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final int leading = weekStart.indexOf(first.weekday);
    final int totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;
    return [
      for (var i = 0; i < totalCells; i++)
        i < leading || i >= leading + daysInMonth
            ? null
            : DateTime(month.year, month.month, i - leading + 1),
    ];
  }

  /// Locale-aware day labels in the order the week runs, anchored to a
  /// known Monday (2024-01-01) rather than hard-coding English names.
  static List<String> _weekdayLabels(String locale, WeekStart weekStart) {
    final DateFormat format = DateFormat.E(locale);
    return [
      for (final int weekday in weekStart.weekdays)
        format.format(DateTime(2024, 1, weekday)),
    ];
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.isToday,
    required this.isMarked,
    required this.onTap,
  });

  final DateTime? date;
  final bool isToday;
  final bool isMarked;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final DateTime? date = this.date;
    if (date == null) {
      return const SizedBox(height: AppSpacing.minTapTarget);
    }

    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: isMarked
          ? context.l10n.calendarDayWithWorkout(date.day)
          : '${date.day}',
      button: isMarked,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: isMarked ? () => onTap(date) : null,
        child: SizedBox(
          height: AppSpacing.minTapTarget,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: isToday
                      ? Border.all(color: scheme.primary, width: 1.5)
                      : null,
                ),
                child: Text(
                  '${date.day}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isMarked ? scheme.primary : scheme.onSurface,
                        fontWeight:
                            isMarked ? FontWeight.w700 : FontWeight.w400,
                      ),
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: 4,
                height: 4,
                child: isMarked
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
