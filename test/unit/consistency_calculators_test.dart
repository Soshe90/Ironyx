import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
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
}
