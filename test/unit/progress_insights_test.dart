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
    );
    expect(insights, isNotEmpty);
    expect(insights.first.severity, InsightSeverity.actionable);
    expect(insights.length, lessThanOrEqualTo(4));
  });

  test('names its subject by id as well, so the page can translate it', () {
    final insights = buildProgressInsights(
      strengthChanges: [strength('Bench', -.2), strength('Row', -.1)],
      volume: const [],
      frequency: const [],
      currentMuscleVolume: const [],
      previousMuscleVolume: const [
        MuscleGroupVolume(
            muscleId: 'legs', muscleName: 'Legs', totalVolumeKg: 500),
      ],
    );

    final ProgressInsight muscle = insights.singleWhere(
      (i) => i.kind == InsightKind.neglectedMuscle,
    );
    expect(muscle.subjectId, 'legs');
    expect(muscle.subjectName, 'Legs');
    final ProgressInsight lift = insights.singleWhere(
      (i) => i.kind == InsightKind.strengthChange,
    );
    // The fixture uses the id as the name; the larger mover is Bench.
    expect(lift.subjectId, 'Bench');
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

  group('the week in progress', () {
    // Local midnight, as the DAO emits buckets, so they can match the
    // current week the function works out from `now`.
    DateTime monday(int offset) =>
        DateTime.parse('2026-01-05').add(Duration(days: offset * 7));
    WeeklyVolume volumeWeek(int offset, double kg) =>
        WeeklyVolume(weekStart: monday(offset), totalVolumeKg: kg);
    WorkoutFrequency countWeek(int offset, int count) =>
        WorkoutFrequency(weekStart: monday(offset), workoutCount: count);

    test('an empty Monday is not a volume drop', () {
      // Five steady weeks, then a week that has only just begun. With it,
      // the recent half read 33% down.
      final insights = buildProgressInsights(
        strengthChanges: const [],
        volume: [
          for (var i = 0; i < 5; i++) volumeWeek(i, 100),
          volumeWeek(5, 0),
        ],
        frequency: const [],
        currentMuscleVolume: const [],
        previousMuscleVolume: const [],
        now: monday(5).add(const Duration(hours: 9)),
      );
      expect(
        insights.where((i) => i.kind == InsightKind.volumeTrendingDown),
        isEmpty,
      );
    });

    test('an empty Monday is not consistency slipping', () {
      final insights = buildProgressInsights(
        strengthChanges: const [],
        volume: const [],
        frequency: [
          for (var i = 0; i < 4; i++) countWeek(i, 1),
          countWeek(4, 0),
        ],
        currentMuscleVolume: const [],
        previousMuscleVolume: const [],
        now: monday(4).add(const Duration(hours: 9)),
      );
      expect(
        insights.where((i) => i.kind == InsightKind.consistencySlipping),
        isEmpty,
      );
    });

    test('finished weeks still count, however busy this one is', () {
      final insights = buildProgressInsights(
        strengthChanges: const [],
        volume: const [],
        frequency: [
          countWeek(0, 1),
          countWeek(1, 0),
          countWeek(2, 1),
          countWeek(3, 0),
          countWeek(4, 3),
        ],
        currentMuscleVolume: const [],
        previousMuscleVolume: const [],
        now: monday(4).add(const Duration(days: 4)),
      );
      final ProgressInsight slipping = insights.singleWhere(
        (i) => i.kind == InsightKind.consistencySlipping,
      );
      expect(slipping.averageSessionsPerWeek, closeTo(0.5, 0.0001));
    });
  });

  group('strength change threshold', () {
    Iterable<ProgressInsight> strengthOf(List<StrengthChange> rows) =>
        buildProgressInsights(
          strengthChanges: rows,
          volume: const [],
          frequency: const [],
          currentMuscleVolume: const [],
          previousMuscleVolume: const [],
        ).where((i) => i.kind == InsightKind.strengthChange);

    test('stays silent when every lift moved less than the threshold', () {
      expect(
          strengthOf([strength('Bench', .01), strength('Row', -.02)]), isEmpty);
    });

    test('speaks once the biggest mover is past it', () {
      final insight = strengthOf([
        strength('Bench', .01),
        strength('Row', -.05),
      ]).single;
      expect(insight.subjectId, 'Row');
      expect(insight.direction, InsightDirection.down);
    });
  });
}
