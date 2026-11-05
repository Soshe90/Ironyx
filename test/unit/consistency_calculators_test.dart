import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/formatters/week_start.dart';
import 'package:ironyx/features/progress/domain/consistency_calculators.dart';

void main() {
  // Shaped exactly like `WorkoutDao.watchWorkoutFrequency` emits: a bare
  // `YYYY-MM-DD` bucket read back through `DateTime.parse`, i.e. *local*
  // midnight. A UTC fixture here silently passed while the real page always
  // reported a zero current streak — `DateTime ==` also compares `isUtc`.
  WorkoutFrequency week(int offset, int count) => WorkoutFrequency(
        weekStart: DateTime.parse('2026-01-05')
            .add(Duration(days: offset * DateTime.daysPerWeek)),
        workoutCount: count,
      );

  test('calculates streaks and adherence over elapsed weeks', () {
    final result = calculateConsistency(
      weeks: [week(0, 4), week(1, 0), week(2, 3), week(3, 3)],
      targetSessionsPerWeek: 3,
      now: DateTime.parse('2026-01-28 09:00:00'),
    );
    expect(result.longestStreakWeeks, 2);
    expect(result.currentStreakWeeks, 2);
    expect(result.hitTargetWeeks, 3);
    expect(result.eligibleWeeks, 4);
    expect(result.adherenceFraction, .75);
  });

  test('a rest week today does not erase last weeks streak', () {
    final result = calculateConsistency(
      weeks: [week(0, 2), week(1, 2), week(2, 0)],
      targetSessionsPerWeek: 3,
      now: DateTime.parse('2026-01-21 09:00:00'),
    );
    expect(result.currentStreakWeeks, 2);
    expect(result.longestStreakWeeks, 2);
  });

  test('empty history stays empty rather than fabricating zero weeks', () {
    final result = calculateConsistency(
      weeks: const [],
      targetSessionsPerWeek: 3,
    );
    expect(result.adherenceFraction, isNull);
    expect(result.currentStreakWeeks, 0);
  });

  test(
      'weeks that pre-date the first-ever workout are not counted as '
      'missed target', () {
    // `WorkoutDao.watchWorkoutFrequency` zero-fills from the *selected
    // range's* start, not from the user's first workout — a lifter two
    // weeks in who picks a 3-month range gets 11 weeks of zeroes before
    // training began. Counting those as misses reported 2 good weeks out
    // of 13 as 15% adherence; the user was never even trainable those
    // first 11 weeks.
    final result = calculateConsistency(
      weeks: [
        for (var i = 0; i < 11; i++) week(i, 0), // before the user existed
        week(11, 4), // started, hit target
        week(12, 3), // hit target
      ],
      targetSessionsPerWeek: 3,
      now: DateTime.parse('2026-04-06 09:00:00'),
    );
    expect(result.eligibleWeeks, 2);
    expect(result.hitTargetWeeks, 2);
    expect(result.adherenceFraction, 1.0);
  });

  test(
      'a rest week after training began still counts as a miss, unlike '
      'the untrainable weeks before it', () {
    final result = calculateConsistency(
      weeks: [
        for (var i = 0; i < 5; i++) week(i, 0), // pre-training
        week(5, 3), // hit target
        week(6, 0), // a genuine rest week — still eligible, still a miss
        week(7, 3), // hit target
      ],
      targetSessionsPerWeek: 3,
      now: DateTime.parse('2026-02-25 09:00:00'),
    );
    expect(result.eligibleWeeks, 3);
    expect(result.hitTargetWeeks, 2);
    expect(result.adherenceFraction, closeTo(2 / 3, 0.001));
  });

  group('first day of the week', () {
    // Buckets as the query emits them for a week starting on Saturday:
    // Sat 3, Sat 10 and Sat 17 Jan 2026, local midnight.
    WorkoutFrequency saturdayWeek(int offset, int count) => WorkoutFrequency(
          weekStart: DateTime(2026, 1, 3 + offset * DateTime.daysPerWeek),
          workoutCount: count,
        );

    test('the current streak is found with the first day the series uses', () {
      // Mon 19 Jan: in the week of Sat 17 Jan.
      final DateTime now = DateTime(2026, 1, 19, 9);
      final result = calculateConsistency(
        weeks: [saturdayWeek(0, 1), saturdayWeek(1, 2), saturdayWeek(2, 1)],
        targetSessionsPerWeek: 3,
        weekStart: WeekStart.saturday,
        utcOffset: now.timeZoneOffset,
        now: now,
      );

      expect(result.currentStreakWeeks, 3);
      expect(result.longestStreakWeeks, 3);
    });

    test('a rest week now still counts the weeks before it', () {
      final DateTime now = DateTime(2026, 1, 19, 9);
      final result = calculateConsistency(
        weeks: [saturdayWeek(0, 1), saturdayWeek(1, 2), saturdayWeek(2, 0)],
        targetSessionsPerWeek: 3,
        weekStart: WeekStart.saturday,
        utcOffset: now.timeZoneOffset,
        now: now,
      );

      expect(result.currentStreakWeeks, 2);
    });

    test('asked with a different first day, no bucket matches', () {
      // What a caller that forgot to pass the setting would get: "this
      // week" is then Mon 19 Jan, and no Saturday bucket is that day.
      final DateTime now = DateTime(2026, 1, 19, 9);
      final result = calculateConsistency(
        weeks: [saturdayWeek(0, 1), saturdayWeek(1, 2), saturdayWeek(2, 1)],
        targetSessionsPerWeek: 3,
        utcOffset: now.timeZoneOffset,
        now: now,
      );

      expect(result.currentStreakWeeks, 0);
      // The longest run does not depend on which week is the current one.
      expect(result.longestStreakWeeks, 3);
    });

    test('the first minutes of a week count for that week, in device time', () {
      // Sat 17 Jan 00:20 local. With no offset this would be read in UTC,
      // which east of UTC is still Friday, the week before.
      final DateTime now = DateTime(2026, 1, 17, 0, 20);
      final result = calculateConsistency(
        weeks: [saturdayWeek(1, 2), saturdayWeek(2, 1)],
        targetSessionsPerWeek: 3,
        weekStart: WeekStart.saturday,
        utcOffset: now.timeZoneOffset,
        now: now,
      );

      expect(result.currentStreakWeeks, 2);
    });
  });

  test('a streak is not broken by a week in which the clocks change', () {
    // Weeks of Mon 2, 9 and 16 March and Mon 26 Oct, 2 and 9 Nov 2026: the
    // United States changes its clocks on 8 March and 1 November, Europe on
    // 29 March and 25 October. Stepping back 168 hours from a Monday
    // midnight across one of those lands on Sunday 23:00, which is no
    // bucket, and the streak stopped there. (Only a zone that changes its
    // clocks can tell: run with TZ=PST8PDT.)
    for (final List<DateTime> mondays in <List<DateTime>>[
      <DateTime>[
        DateTime(2026, 3, 2),
        DateTime(2026, 3, 9),
        DateTime(2026, 3, 16)
      ],
      <DateTime>[
        DateTime(2026, 3, 16),
        DateTime(2026, 3, 23),
        DateTime(2026, 3, 30)
      ],
      <DateTime>[
        DateTime(2026, 10, 19),
        DateTime(2026, 10, 26),
        DateTime(2026, 11, 2)
      ],
      <DateTime>[
        DateTime(2026, 10, 26),
        DateTime(2026, 11, 2),
        DateTime(2026, 11, 9)
      ],
    ]) {
      final DateTime now = DateTime(
        mondays.last.year,
        mondays.last.month,
        mondays.last.day + 1,
        9,
      );
      final result = calculateConsistency(
        weeks: [
          for (final DateTime monday in mondays)
            WorkoutFrequency(weekStart: monday, workoutCount: 1),
        ],
        targetSessionsPerWeek: 1,
        utcOffset: now.timeZoneOffset,
        now: now,
      );

      expect(result.currentStreakWeeks, 3, reason: 'weeks $mondays');
    }
  });
}
