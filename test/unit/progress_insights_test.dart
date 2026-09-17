import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/features/progress/domain/progress_insights.dart';

void main() {
  StrengthChange strength(String id, double? change) => StrengthChange(
        exerciseId: id,
        exerciseName: id,
        currentBestKg: 100,
        previousBestKg: change == null ? null : 100 / (1 + change),
      );

  WeeklyVolume volume(double kg) => WeeklyVolume(
        weekStart: DateTime.utc(2026, 1, 5),
        totalVolumeKg: kg,
      );

  WorkoutFrequency frequency(int count) => WorkoutFrequency(
        weekStart: DateTime.utc(2026, 1, 5),
        workoutCount: count,
      );

  test('stays silent below minimum strength data threshold', () {
    final insights = buildProgressInsights(
      strengthChanges: [strength('Bench', .2)],
      volume: const [],
      frequency: const [],
      currentMuscleVolume: const [],
      previousMuscleVolume: const [],
    );
    expect(insights, isEmpty);
  });

  test('ranks actionable neglected muscle before negative trends', () {
    final insights = buildProgressInsights(
      strengthChanges: [strength('Bench', -.2), strength('Row', -.1)],
      volume: [volume(100), volume(100), volume(50), volume(50)],
      frequency: [frequency(1), frequency(1), frequency(0), frequency(0)],
      currentMuscleVolume: const [],
      previousMuscleVolume: const [
        MuscleGroupVolume(
            muscleId: 'legs', muscleName: 'Legs', totalVolumeKg: 500),
      ],
      recentPersonalRecords: 2,
    );
    expect(insights, isNotEmpty);
    expect(insights.first.severity, InsightSeverity.actionable);
    expect(insights.length, lessThanOrEqualTo(4));
  });

  test('requires four weeks before making consistency or volume claims', () {
    final insights = buildProgressInsights(
      strengthChanges: const [],
      volume: [volume(100), volume(10), volume(10)],
      frequency: [frequency(1), frequency(0), frequency(0)],
      currentMuscleVolume: const [],
      previousMuscleVolume: const [],
    );
    expect(insights, isEmpty);
  });

  // Distinct weeks, unlike `frequency()` above which collapses every entry
  // onto one `weekStart` — these two tests need to distinguish weeks
  // before training started from weeks after, so each needs its own date.
  WorkoutFrequency week(int offset, int count) => WorkoutFrequency(
        weekStart: DateTime.utc(2026, 1, 5).add(Duration(days: offset * 7)),
        workoutCount: count,
      );

  test(
      'does not flag consistency as slipping over weeks that pre-date the '
      'first-ever workout', () {
    final insights = buildProgressInsights(
      strengthChanges: const [],
      volume: const [],
      frequency: [
        for (var i = 0; i < 10; i++) week(i, 0), // before the user existed
        week(10, 3),
        week(11, 3),
      ],
      currentMuscleVolume: const [],
      previousMuscleVolume: const [],
    );
    expect(
      insights.where((i) => i.kind == InsightKind.consistencySlipping),
      isEmpty,
    );
  });

  test('still flags a genuine decline after training began', () {
    final insights = buildProgressInsights(
      strengthChanges: const [],
      volume: const [],
      frequency: [
        week(0, 3),
        week(1, 3),
        week(2, 0),
        week(3, 0),
        week(4, 0),
        week(5, 0),
        week(6, 0),
      ],
      currentMuscleVolume: const [],
      previousMuscleVolume: const [],
    );
    expect(
      insights.where((i) => i.kind == InsightKind.consistencySlipping),
      isNotEmpty,
    );
  });
}
