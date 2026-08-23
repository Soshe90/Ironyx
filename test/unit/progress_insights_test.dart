import 'package:fittrack/core/database/daos/workout_dao.dart';
import 'package:fittrack/features/progress/domain/progress_insights.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
