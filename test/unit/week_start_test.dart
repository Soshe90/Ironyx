import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/formatters/date_formatters.dart';
import 'package:ironyx/core/formatters/week_start.dart';
import 'package:ironyx/core/formatters/week_start_controller.dart';
import 'package:ironyx/core/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The first day of the week, chosen in Settings: the day arithmetic, the
/// saved preference, and the week maths in `DateFormatters` that takes it.
///
/// Reference calendar, January 2026: Thu 1, Fri 2, Sat 3, Sun 4, Mon 5,
/// … Sat 10, Sun 11, Mon 12.
void main() {
  group('WeekStart', () {
    test('lists the seven days in the order its week runs', () {
      expect(
        WeekStart.monday.weekdays,
        <int>[1, 2, 3, 4, 5, 6, 7],
      );
      expect(
        WeekStart.sunday.weekdays,
        <int>[7, 1, 2, 3, 4, 5, 6],
      );
      expect(
        WeekStart.saturday.weekdays,
        <int>[6, 7, 1, 2, 3, 4, 5],
      );
    });

    test('counts how far into its week each day falls', () {
      for (final WeekStart start in WeekStart.values) {
        final List<int> days = start.weekdays;
        for (int i = 0; i < days.length; i++) {
          expect(start.indexOf(days[i]), i, reason: '$start, day ${days[i]}');
        }
      }
      expect(WeekStart.saturday.indexOf(DateTime.friday), 6);
      expect(WeekStart.sunday.indexOf(DateTime.saturday), 6);
      expect(WeekStart.monday.indexOf(DateTime.sunday), 6);
    });

    test('names its last day the way SQLite numbers days', () {
      // SQLite: Sunday 0 … Saturday 6.
      expect(WeekStart.monday.sqliteLastWeekday, 0, reason: 'ends on Sunday');
      expect(WeekStart.sunday.sqliteLastWeekday, 6, reason: 'ends Saturday');
      expect(WeekStart.saturday.sqliteLastWeekday, 5, reason: 'ends Friday');
    });
  });

  group('WeekStartController', () {
    Future<ProviderContainer> containerWith(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final ProviderContainer container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider
              .overrideWithValue(await SharedPreferences.getInstance()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('is Monday until a day is chosen, as every week was before', () async {
      final container = await containerWith(<String, Object>{});
      expect(container.read(weekStartControllerProvider), WeekStart.monday);
    });

    test('reads back each day it can store', () async {
      for (final WeekStart day in WeekStart.values) {
        // Started on a different day, so that choosing [day] is a change
        // even when it is Monday, the day an empty preference reads as.
        final WeekStart other =
            WeekStart.values[(day.index + 1) % WeekStart.values.length];
        final container =
            await containerWith(<String, Object>{'week_start': other.name});
        expect(container.read(weekStartControllerProvider), other);
        await container.read(weekStartControllerProvider.notifier).set(day);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('week_start'), day.name);

        // A new container over the same preferences: the next launch.
        final relaunched = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(relaunched.dispose);
        expect(relaunched.read(weekStartControllerProvider), day);
      }
    });

    test('anything unrecognised reads as Monday instead of failing', () async {
      for (final Object stored in <Object>['friday', '', 'SATURDAY', 6, true]) {
        final container =
            await containerWith(<String, Object>{'week_start': stored});
        expect(
          container.read(weekStartControllerProvider),
          WeekStart.monday,
          reason: 'stored $stored',
        );
      }
    });

    test('choosing the day already chosen writes nothing', () async {
      final container = await containerWith(<String, Object>{});
      await container
          .read(weekStartControllerProvider.notifier)
          .set(WeekStart.monday);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('week_start'), isFalse);
    });

    test('tells its listeners when the day changes', () async {
      final container = await containerWith(<String, Object>{});
      final List<WeekStart> seen = <WeekStart>[];
      container.listen<WeekStart>(
        weekStartControllerProvider,
        (_, WeekStart next) => seen.add(next),
      );

      final notifier = container.read(weekStartControllerProvider.notifier);
      await notifier.set(WeekStart.saturday);
      await notifier.set(WeekStart.saturday);
      await notifier.set(WeekStart.sunday);

      expect(seen, <WeekStart>[WeekStart.saturday, WeekStart.sunday]);
    });
  });

  group('DateFormatters.startOfWeek', () {
    test('finds the first day for every day of a week, for each start', () {
      // Sat 3 Jan to Fri 9 Jan 2026.
      final Map<WeekStart, List<int>> expectedDayOfMonth =
          <WeekStart, List<int>>{
        //                    Sa Su Mo Tu We Th Fr
        WeekStart.saturday: <int>[3, 3, 3, 3, 3, 3, 3],
        WeekStart.sunday: <int>[-3, 4, 4, 4, 4, 4, 4],
        WeekStart.monday: <int>[-2, -2, 5, 5, 5, 5, 5],
      };
      for (final WeekStart start in WeekStart.values) {
        for (int i = 0; i < 7; i++) {
          final int expected = expectedDayOfMonth[start]![i];
          expect(
            DateFormatters.startOfWeek(DateTime(2026, 1, 3 + i, 15, 30), start),
            // A negative day counts back from the end of December 2025:
            // DateTime(2026, 1, -3) is Sun 28 Dec, (2026, 1, -2) is Mon 29.
            DateTime(2026, 1, expected),
            reason: '$start, ${3 + i} Jan',
          );
        }
      }
    });

    test('lands on the chosen weekday at midnight, on or before the date', () {
      for (final WeekStart start in WeekStart.values) {
        // Every day of 2026 and into 2027, so both clock changes of any
        // zone these tests run in are crossed.
        for (int day = 0; day < 400; day++) {
          final DateTime date = DateTime(2026, 1, 1 + day, 23, 59);
          final DateTime first = DateFormatters.startOfWeek(date, start);

          expect(first.weekday, start.weekday, reason: '$start, $date');
          expect(
            <int>[first.hour, first.minute, first.second],
            <int>[0, 0, 0],
            reason: '$start, $date',
          );
          final int daysBack = DateTime.utc(date.year, date.month, date.day)
              .difference(DateTime.utc(first.year, first.month, first.day))
              .inDays;
          expect(daysBack, inInclusiveRange(0, 6), reason: '$start, $date');
        }
      }
    });

    test('crosses month and year ends', () {
      // Thu 1 Jan 2026.
      expect(
        DateFormatters.startOfWeek(DateTime(2026), WeekStart.saturday),
        DateTime(2025, 12, 27),
      );
      expect(
        DateFormatters.startOfWeek(DateTime(2026), WeekStart.sunday),
        DateTime(2025, 12, 28),
      );
      expect(
        DateFormatters.startOfWeek(DateTime(2026), WeekStart.monday),
        DateTime(2025, 12, 29),
      );
      // Sun 1 Mar 2026, after a 28-day February.
      expect(
        DateFormatters.startOfWeek(DateTime(2026, 3), WeekStart.monday),
        DateTime(2026, 2, 23),
      );
      // Leap day, Thu 29 Feb 2024.
      expect(
        DateFormatters.startOfWeek(DateTime(2024, 2, 29), WeekStart.saturday),
        DateTime(2024, 2, 24),
      );
    });
  });

  group('DateFormatters.weekBucketStart', () {
    test('with no offset, takes the day from UTC', () {
      // Mon 5 Jan 2026, 00:00 UTC, whatever the local time is.
      final DateTime instant = DateTime.utc(2026, 1, 5);
      expect(
        DateFormatters.weekBucketStart(
          instant,
          weekStart: WeekStart.monday,
          utcOffset: Duration.zero,
        ),
        DateTime(2026, 1, 5),
      );
      // The same instant given as a local time is the same instant.
      expect(
        DateFormatters.weekBucketStart(
          instant.toLocal(),
          weekStart: WeekStart.monday,
          utcOffset: Duration.zero,
        ),
        DateTime(2026, 1, 5),
      );
    });

    test('an offset east of UTC moves a late-evening instant to the next week',
        () {
      // Sat 10 Jan 21:30 UTC is Sun 11 Jan 00:30 at UTC+3.
      final DateTime instant = DateTime.utc(2026, 1, 10, 21, 30);
      expect(
        DateFormatters.weekBucketStart(
          instant,
          weekStart: WeekStart.sunday,
          utcOffset: Duration.zero,
        ),
        DateTime(2026, 1, 4),
      );
      expect(
        DateFormatters.weekBucketStart(
          instant,
          weekStart: WeekStart.sunday,
          utcOffset: const Duration(hours: 3),
        ),
        DateTime(2026, 1, 11),
      );
    });

    test('an offset west of UTC keeps an early-morning instant in last week',
        () {
      // Sun 11 Jan 02:00 UTC is Sat 10 Jan 18:00 at UTC−8.
      final DateTime instant = DateTime.utc(2026, 1, 11, 2);
      expect(
        DateFormatters.weekBucketStart(
          instant,
          weekStart: WeekStart.sunday,
          utcOffset: const Duration(hours: -8),
        ),
        DateTime(2026, 1, 4),
      );
    });

    test('half-hour offsets count', () {
      // Fri 9 Jan 18:45 UTC is Sat 10 Jan 00:15 at UTC+5:30.
      final DateTime instant = DateTime.utc(2026, 1, 9, 18, 45);
      expect(
        DateFormatters.weekBucketStart(
          instant,
          weekStart: WeekStart.saturday,
          utcOffset: const Duration(hours: 5, minutes: 30),
        ),
        DateTime(2026, 1, 10),
      );
      expect(
        DateFormatters.weekBucketStart(
          instant,
          weekStart: WeekStart.saturday,
          utcOffset: const Duration(hours: 5),
        ),
        DateTime(2026, 1, 3),
      );
    });
  });

  group('DateFormatters.nextWeek and previousWeek', () {
    test('step by calendar weeks through a whole year of clock changes', () {
      // 168-hour steps drift to 23:00 or 01:00 across a clock change; these
      // must stay on midnight of the same weekday in whatever zone this runs.
      for (final WeekStart start in WeekStart.values) {
        DateTime week = DateFormatters.startOfWeek(DateTime(2026), start);
        for (int i = 0; i < 60; i++) {
          final DateTime next = DateFormatters.nextWeek(week);
          expect(next.weekday, start.weekday);
          expect(next.hour, 0);
          expect(
            DateTime.utc(next.year, next.month, next.day)
                .difference(DateTime.utc(week.year, week.month, week.day))
                .inDays,
            7,
          );
          expect(DateFormatters.previousWeek(next), week);
          week = next;
        }
      }
    });

    test('cross a year end', () {
      expect(
        DateFormatters.nextWeek(DateTime(2025, 12, 27)),
        DateTime(2026, 1, 3),
      );
      expect(
        DateFormatters.previousWeek(DateTime(2026, 1, 3)),
        DateTime(2025, 12, 27),
      );
    });
  });
}
