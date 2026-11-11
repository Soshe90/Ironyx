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

  group('the week in progress', () {
    test('is left out of adherence until it meets the target', () {
      // Tuesday of the third week, one session in: not a miss yet.
      final result = calculateConsistency(
        weeks: [week(0, 3), week(1, 3), week(2, 1)],
        targetSessionsPerWeek: 3,
        now: DateTime.parse('2026-01-20 09:00:00'),
      );
      expect(result.eligibleWeeks, 2);
      expect(result.hitTargetWeeks, 2);
      expect(result.adherenceFraction, 1.0);
    });

    test('counts once it has met the target', () {
      final result = calculateConsistency(
        weeks: [week(0, 3), week(1, 0), week(2, 3)],
        targetSessionsPerWeek: 3,
        now: DateTime.parse('2026-01-20 09:00:00'),
      );
      expect(result.eligibleWeeks, 3);
      expect(result.hitTargetWeeks, 2);
    });

    test('alone and unmet, leaves adherence unknown rather than 0%', () {
      final result = calculateConsistency(
        weeks: [week(0, 1)],
        targetSessionsPerWeek: 3,
        now: DateTime.parse('2026-01-06 09:00:00'),
      );
      expect(result.eligibleWeeks, 0);
      expect(result.adherenceFraction, isNull);
      // The streak still sees this week's session.
      expect(result.currentStreakWeeks, 1);
    });
  });

  group('averageSessionsPerWeek', () {
    test('divides by the range, not by the week buckets it touches', () {
      // A 14-day range spans three calendar weeks; six sessions in it are
      // three a week, not two.
      final double? average = averageSessionsPerWeek(
        weeks: [week(0, 2), week(1, 2), week(2, 2)],
        rangeDays: 14,
        now: DateTime.parse('2026-01-21 09:00:00'),
      );
      expect(average, closeTo(3.0, 0.0001));
    });

    test('counts from the first trained week when training began inside', () {
      // Two weeks in, inside a 90-day range: not averaged over the eleven
      // empty weeks before the first session.
      final DateTime now = DateTime.parse('2026-04-04 09:00:00');
      final double? average = averageSessionsPerWeek(
        weeks: [
          for (var i = 0; i < 11; i++) week(i, 0),
          week(11, 3),
          week(12, 3),
        ],
        rangeDays: 90,
        now: now,
      );
      final double elapsed =
          now.difference(week(11, 0).weekStart).inMinutes / (60 * 24 * 7);
      expect(average, closeTo(6 / elapsed, 0.0001));
      expect(average, greaterThan(3));
    });

    test('all-time runs from the first trained week to now', () {
      final DateTime now = DateTime.parse('2026-02-01 09:00:00');
      final double? average = averageSessionsPerWeek(
        weeks: [week(0, 2), week(1, 2), week(2, 2), week(3, 2)],
        rangeDays: null,
        now: now,
      );
      final double elapsed =
          now.difference(week(0, 0).weekStart).inMinutes / (60 * 24 * 7);
      expect(average, closeTo(8 / elapsed, 0.0001));
    });

    test('never divides by less than a week', () {
      final double? average = averageSessionsPerWeek(
        weeks: [week(0, 1)],
        rangeDays: null,
        now: DateTime.parse('2026-01-06 09:00:00'),
      );
      expect(average, 1.0);
    });

    test('is null with nothing trained', () {
      expect(
        averageSessionsPerWeek(
          weeks: const [],
          rangeDays: 30,
          now: DateTime.parse('2026-01-06 09:00:00'),
        ),
        isNull,
      );
      expect(
        averageSessionsPerWeek(
          weeks: [week(0, 0), week(1, 0)],
          rangeDays: 30,
          now: DateTime.parse('2026-01-13 09:00:00'),
        ),
        isNull,
      );
    });
  });

  group('back from a break inside the range', () {
    // Mon 5 Jan 2026 is week(0). The range starts mid-week(0); the user
    // trained long before it, stopped, and came back in week(4).
    final DateTime rangeStart = DateTime.parse('2026-01-07 09:00:00');
    final DateTime longAgo = DateTime.parse('2025-03-01 09:00:00');
    final DateTime now = DateTime.parse('2026-02-11 09:00:00'); // week(5)

    test('trainedBeforeRange', () {
      expect(
        trainedBeforeRange(rangeStart: rangeStart, firstWorkoutAt: longAgo),
        isTrue,
      );
      expect(
        trainedBeforeRange(
          rangeStart: rangeStart,
          firstWorkoutAt: DateTime.parse('2026-01-20'),
        ),
        isFalse,
      );
      expect(trainedBeforeRange(rangeStart: null, firstWorkoutAt: longAgo),
          isFalse,
          reason: 'all-time has no before');
      expect(trainedBeforeRange(rangeStart: rangeStart, firstWorkoutAt: null),
          isFalse,
          reason: 'unknown keeps the old rule');
    });

    test('adherence counts the empty weeks of the break', () {
      final result = calculateConsistency(
        weeks: [
          week(0, 0), // partial, unmet: left out
          week(1, 0),
          week(2, 0),
          week(3, 0),
          week(4, 3),
          week(5, 1), // this week, unmet: left out
        ],
        targetSessionsPerWeek: 3,
        now: now,
        rangeStart: rangeStart,
        firstWorkoutAt: longAgo,
      );
      expect(result.eligibleWeeks, 4);
      expect(result.hitTargetWeeks, 1);
      expect(result.adherenceFraction, .25);
    });

    test('without the first workout, the old rule still applies', () {
      final result = calculateConsistency(
        weeks: [week(0, 0), week(1, 0), week(2, 0), week(3, 0), week(4, 3)],
        targetSessionsPerWeek: 3,
        now: now,
      );
      expect(result.eligibleWeeks, 1);
      expect(result.adherenceFraction, 1.0);
    });

    test('a partial first week that met the target still counts', () {
      final result = calculateConsistency(
        weeks: [week(0, 3), week(1, 0), week(2, 3)],
        targetSessionsPerWeek: 3,
        now: DateTime.parse('2026-01-28 09:00:00'), // week(3), not listed
        rangeStart: rangeStart,
        firstWorkoutAt: longAgo,
      );
      expect(result.eligibleWeeks, 3);
      expect(result.hitTargetWeeks, 2);
    });

    test('the per-week average divides by the whole range', () {
      final double? average = averageSessionsPerWeek(
        weeks: [
          for (var i = 0; i < 11; i++) week(i, 0),
          week(11, 3),
          week(12, 3),
        ],
        rangeDays: 90,
        now: DateTime.parse('2026-04-04 09:00:00'),
        firstWorkoutAt: longAgo,
      );
      // Six sessions over 90 days, not over the two weeks since returning.
      expect(average, closeTo(6 / (90 / 7), 0.0001));
    });

    test('a first workout inside the range keeps counting from it', () {
      final DateTime now2 = DateTime.parse('2026-04-04 09:00:00');
      final double? average = averageSessionsPerWeek(
        weeks: [
          for (var i = 0; i < 11; i++) week(i, 0),
          week(11, 3),
          week(12, 3),
        ],
        rangeDays: 90,
        now: now2,
        firstWorkoutAt: week(11, 0).weekStart.add(const Duration(hours: 9)),
      );
      final double elapsed =
          now2.difference(week(11, 0).weekStart).inMinutes / (60 * 24 * 7);
      expect(average, closeTo(6 / elapsed, 0.0001));
    });
  });

  group('a range with nothing in it', () {
    final List<WorkoutFrequency> zeros = <WorkoutFrequency>[
      for (var i = 0; i < 5; i++) week(i, 0),
    ];
    final DateTime now = DateTime.parse('2026-02-06 09:00:00');

    test('averages 0 a week after a break', () {
      expect(
        averageSessionsPerWeek(
          weeks: zeros,
          rangeDays: 30,
          now: now,
          firstWorkoutAt: DateTime.parse('2025-06-01'),
        ),
        0,
      );
    });

    test('has no average without history before it', () {
      expect(
        averageSessionsPerWeek(weeks: zeros, rangeDays: 30, now: now),
        isNull,
      );
      expect(
        averageSessionsPerWeek(
          weeks: const [],
          rangeDays: 30,
          now: now,
        ),
        isNull,
      );
    });

    test('adherence is 0% after a break, not unknown', () {
      final result = calculateConsistency(
        weeks: zeros,
        targetSessionsPerWeek: 3,
        now: now,
        rangeStart: DateTime.parse('2026-01-07 09:00:00'),
        firstWorkoutAt: DateTime.parse('2025-06-01'),
      );
      // Weeks 1-3; week 0 is partial and week 4 is this week, both unmet.
      expect(result.eligibleWeeks, 3);
      expect(result.adherenceFraction, 0);
    });
  });

  // The one streak rule, shared by Home's tile and the consistency card.
  // Some of these cases were Home's WeekSnapshot tests until the streak
  // moved out of its eight-week snapshot.
  group('currentStreakWeeks', () {
    WorkoutFrequency at(DateTime monday, int count) =>
        WorkoutFrequency(weekStart: monday, workoutCount: count);

    test('nothing logged is no streak', () {
      expect(
        currentStreakWeeks(
          weeks: const <WorkoutFrequency>[],
          currentWeek: DateTime(2026, 11, 9),
        ),
        0,
      );
    });

    test('counts consecutive trained weeks ending this week, in any order', () {
      expect(
        currentStreakWeeks(
          weeks: <WorkoutFrequency>[
            at(DateTime(2026, 11, 9), 3),
            at(DateTime(2026, 10, 26), 1),
            at(DateTime(2026, 11, 2), 2),
          ],
          currentWeek: DateTime(2026, 11, 9),
        ),
        3,
      );
    });

    test('an empty week so far keeps the streak that ended last week', () {
      expect(
        currentStreakWeeks(
          weeks: <WorkoutFrequency>[
            at(DateTime(2026, 10, 26), 1),
            at(DateTime(2026, 11, 2), 2),
            at(DateTime(2026, 11, 9), 0),
          ],
          currentWeek: DateTime(2026, 11, 9),
        ),
        2,
      );
    });

    test('a zero week, or a missing one, ends it', () {
      for (final List<WorkoutFrequency> weeks in <List<WorkoutFrequency>>[
        <WorkoutFrequency>[
          at(DateTime(2026, 10, 19), 4),
          at(DateTime(2026, 10, 26), 0),
          at(DateTime(2026, 11, 2), 1),
        ],
        <WorkoutFrequency>[
          at(DateTime(2026, 10, 19), 4),
          at(DateTime(2026, 11, 2), 1),
        ],
      ]) {
        expect(
          currentStreakWeeks(weeks: weeks, currentWeek: DateTime(2026, 11, 9)),
          1,
        );
      }
    });

    test('no limit on its length', () {
      final List<WorkoutFrequency> weeks = <WorkoutFrequency>[
        for (int i = 0; i < 60; i++) at(DateTime(2025, 9, 15 + 7 * i), 1),
      ];
      expect(
        currentStreakWeeks(weeks: weeks, currentWeek: weeks.last.weekStart),
        60,
      );
    });

    test('this week has to be named with the first day the buckets use', () {
      // Buckets for weeks starting on Saturday: Sat 24 and Sat 31 Oct.
      final List<WorkoutFrequency> weeks = <WorkoutFrequency>[
        at(DateTime(2026, 10, 24), 1),
        at(DateTime(2026, 10, 31), 2),
      ];
      expect(
        currentStreakWeeks(weeks: weeks, currentWeek: DateTime(2026, 10, 31)),
        2,
      );
      // Monday 2 Nov is no bucket here, nor is the Monday before it.
      expect(
        currentStreakWeeks(weeks: weeks, currentWeek: DateTime(2026, 11, 2)),
        0,
      );
    });

    test('survives a week in which the clocks change', () {
      // Only a zone that changes its clocks can tell: run with TZ=PST8PDT.
      for (final List<DateTime> mondays in <List<DateTime>>[
        <DateTime>[DateTime(2026, 3, 2), DateTime(2026, 3, 9)],
        <DateTime>[DateTime(2026, 3, 23), DateTime(2026, 3, 30)],
        <DateTime>[DateTime(2026, 10, 19), DateTime(2026, 10, 26)],
        <DateTime>[DateTime(2026, 10, 26), DateTime(2026, 11, 2)],
      ]) {
        expect(
          currentStreakWeeks(
            weeks: <WorkoutFrequency>[at(mondays[0], 1), at(mondays[1], 2)],
            currentWeek: mondays[1],
          ),
          2,
          reason: 'weeks $mondays',
        );
      }
    });
  });

  group('longestStreakWeeks', () {
    WorkoutFrequency at(DateTime monday, int count) =>
        WorkoutFrequency(weekStart: monday, workoutCount: count);

    test('nothing logged is no streak', () {
      expect(longestStreakWeeks(weeks: const <WorkoutFrequency>[]), 0);
    });

    test('the longest run, broken by a zero week or a missing one', () {
      expect(
        longestStreakWeeks(weeks: <WorkoutFrequency>[
          at(DateTime(2026, 9, 7), 1),
          at(DateTime(2026, 9, 14), 1),
          at(DateTime(2026, 9, 21), 1),
          at(DateTime(2026, 9, 28), 0),
          at(DateTime(2026, 10, 5), 2),
          // 12 Oct missing
          at(DateTime(2026, 10, 19), 1),
          at(DateTime(2026, 10, 26), 1),
        ]),
        3,
      );
    });

    test('in any order, and a repeated week is counted once', () {
      expect(
        longestStreakWeeks(weeks: <WorkoutFrequency>[
          at(DateTime(2026, 11, 2), 1),
          at(DateTime(2026, 10, 19), 1),
          at(DateTime(2026, 10, 26), 1),
          at(DateTime(2026, 10, 26), 2),
        ]),
        3,
      );
    });

    test('survives weeks in which the clocks change', () {
      // Only a zone that changes its clocks can tell: run with TZ=PST8PDT.
      expect(
        longestStreakWeeks(weeks: <WorkoutFrequency>[
          for (final DateTime d in <DateTime>[
            DateTime(2026, 3, 2),
            DateTime(2026, 3, 9),
            DateTime(2026, 3, 16),
            DateTime(2026, 3, 23),
            DateTime(2026, 3, 30),
          ])
            at(d, 1),
        ]),
        5,
      );
    });
  });

  group('calculateConsistency with the whole history', () {
    WorkoutFrequency at(DateTime monday, int count) =>
        WorkoutFrequency(weekStart: monday, workoutCount: count);

    // Twenty trained weeks, the last one this week (Mon 9 Nov 2026).
    final List<WorkoutFrequency> history = <WorkoutFrequency>[
      for (int i = 0; i < 20; i++) at(DateTime(2026, 6, 29 + 7 * i), 1),
    ];
    final DateTime now = DateTime(2026, 11, 10, 11);

    test('streaks come from the history, adherence from the range', () {
      final ConsistencySummary summary = calculateConsistency(
        weeks: history.sublist(15), // a range of five weeks
        history: history,
        targetSessionsPerWeek: 1,
        now: now,
      );
      expect(summary.currentStreakWeeks, 20,
          reason: 'it was 5, the length of the range');
      expect(summary.longestStreakWeeks, 20);
      expect(summary.eligibleWeeks, 5);
      expect(summary.hitTargetWeeks, 5);
    });

    test('an empty range still shows the longest streak before it', () {
      final ConsistencySummary summary = calculateConsistency(
        weeks: const <WorkoutFrequency>[],
        history: history,
        targetSessionsPerWeek: 1,
        now: DateTime(2027, 3, 1),
      );
      expect(summary.currentStreakWeeks, 0);
      expect(summary.longestStreakWeeks, 20);
      expect(summary.adherenceFraction, isNull);
    });
  });
}
