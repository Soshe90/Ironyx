import 'package:fittrack/core/database/daos/workout_dao.dart';
import 'package:fittrack/features/progress/domain/consistency_calculators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WorkoutFrequency week(int offset, int count) => WorkoutFrequency(
        weekStart: DateTime.utc(2026, 1, 5).add(Duration(days: offset * 7)),
        workoutCount: count,
      );

  test('calculates streaks and adherence over elapsed weeks', () {
    final result = calculateConsistency(
      weeks: [week(0, 4), week(1, 0), week(2, 3), week(3, 3)],
      targetSessionsPerWeek: 3,
      now: DateTime.utc(2026, 1, 28),
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
      now: DateTime.utc(2026, 1, 21),
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
}
