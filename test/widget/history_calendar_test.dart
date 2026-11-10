import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:ironyx/core/formatters/week_start.dart';
import 'package:ironyx/features/tracker/presentation/widgets/history_calendar.dart';
import 'package:ironyx/l10n/app_localizations.dart';

/// The history calendar's columns follow the first day of the week chosen
/// in Settings.
///
/// November 2026 begins on a Sunday and has 30 days; February 2026 begins
/// on a Sunday and has 28.
void main() {
  Future<void> pumpCalendar(
    WidgetTester tester, {
    required WeekStart weekStart,
    DateTime? month,
    Set<DateTime> marked = const <DateTime>{},
    ValueChanged<DateTime>? onDayTap,
    Locale locale = const Locale('en'),
  }) =>
      tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            // In a scroll view so the calendar is as tall as its rows, as
            // it is inside the tracker's list.
            body: SingleChildScrollView(
              child: HistoryCalendar(
                visibleMonth: month ?? DateTime(2026, 11),
                today: DateTime(2026, 11, 3),
                weekStart: weekStart,
                markedDates: marked,
                onMonthChanged: (_) {},
                onDayTap: onDayTap ?? (_) {},
              ),
            ),
          ),
        ),
      );

  double xOf(WidgetTester tester, String text) =>
      tester.getCenter(find.text(text)).dx;
  double yOf(WidgetTester tester, String text) =>
      tester.getCenter(find.text(text)).dy;

  const Map<WeekStart, List<String>> labels = <WeekStart, List<String>>{
    WeekStart.monday: <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    WeekStart.sunday: <String>['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
    WeekStart.saturday: <String>[
      'Sat',
      'Sun',
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
    ],
  };

  for (final WeekStart start in WeekStart.values) {
    group('week starting ${start.name}', () {
      testWidgets('the day labels run from the first day', (tester) async {
        await pumpCalendar(tester, weekStart: start);

        final List<double> xs = <double>[
          for (final String label in labels[start]!) xOf(tester, label),
        ];
        for (int i = 1; i < xs.length; i++) {
          expect(xs[i], greaterThan(xs[i - 1]), reason: labels[start]![i]);
        }
      });

      testWidgets('every day of the month sits under its own weekday',
          (tester) async {
        await pumpCalendar(tester, weekStart: start);

        final DateFormat weekday = DateFormat.E('en');
        for (int day = 1; day <= 30; day++) {
          final String label = weekday.format(DateTime(2026, 11, day));
          expect(
            xOf(tester, '$day'),
            moreOrLessEquals(xOf(tester, label), epsilon: 0.5),
            reason: '$day Nov is a $label',
          );
        }
        expect(find.text('31'), findsNothing);
      });

      testWidgets('a new row begins on the first day and nowhere else',
          (tester) async {
        await pumpCalendar(tester, weekStart: start);

        for (int day = 2; day <= 30; day++) {
          final bool startsRow =
              DateTime(2026, 11, day).weekday == start.weekday;
          final double step = yOf(tester, '$day') - yOf(tester, '${day - 1}');
          if (startsRow) {
            expect(step, greaterThan(0), reason: '$day Nov starts a row');
          } else {
            expect(step, 0, reason: '$day Nov continues a row');
          }
        }
      });

      testWidgets('tapping a marked day reports that date', (tester) async {
        final List<DateTime> tapped = <DateTime>[];
        await pumpCalendar(
          tester,
          weekStart: start,
          marked: <DateTime>{DateTime(2026, 11, 1), DateTime(2026, 11, 30)},
          onDayTap: tapped.add,
        );

        await tester.tap(find.text('1'));
        await tester.tap(find.text('30'));
        // Not marked: nothing to open.
        await tester.tap(find.text('15'));

        expect(
            tapped, <DateTime>[DateTime(2026, 11, 1), DateTime(2026, 11, 30)]);
      });
    });
  }

  testWidgets('the month takes as many rows as its first day needs',
      (tester) async {
    double height(WidgetTester tester) =>
        tester.getSize(find.byType(HistoryCalendar)).height;

    // November 2026 begins on a Sunday. With Monday first that Sunday is
    // alone on the first row, and the month runs to a sixth.
    await pumpCalendar(tester, weekStart: WeekStart.monday);
    final double sixRows = height(tester);
    await pumpCalendar(tester, weekStart: WeekStart.sunday);
    final double fiveRows = height(tester);
    await pumpCalendar(tester, weekStart: WeekStart.saturday);
    expect(height(tester), fiveRows);
    expect(sixRows, greaterThan(fiveRows));

    // February 2026: 28 days from a Sunday is exactly four rows.
    await pumpCalendar(
      tester,
      weekStart: WeekStart.sunday,
      month: DateTime(2026, 2),
    );
    expect(height(tester), lessThan(fiveRows));
    expect(find.text('28'), findsOneWidget);
    expect(find.text('29'), findsNothing);
  });

  testWidgets('right to left, the first day is the rightmost column',
      (tester) async {
    await pumpCalendar(
      tester,
      weekStart: WeekStart.saturday,
      locale: const Locale('ar'),
    );

    final DateFormat weekday = DateFormat.E('ar');
    final List<String> arabic = <String>[
      for (final int day in WeekStart.saturday.weekdays)
        weekday.format(DateTime(2024, 1, day)),
    ];
    final List<double> xs = <double>[
      for (final String label in arabic) xOf(tester, label),
    ];
    for (int i = 1; i < xs.length; i++) {
      expect(xs[i], lessThan(xs[i - 1]), reason: arabic[i]);
    }
    // Sun 1 Nov is the second day of a week that starts on Saturday.
    expect(xOf(tester, '1'), moreOrLessEquals(xs[1], epsilon: 0.5));
    expect(tester.takeException(), isNull);
  });
}
