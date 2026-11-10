import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/features/progress/domain/progress_calculators.dart';
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

    // Where the threshold comes from: the estimate's own formula.
    test('one more rep at the same weight is at least the threshold', () {
      for (int reps = 2; reps <= 9; reps++) {
        final double step =
            epleyOneRepMax(100, reps + 1) / epleyOneRepMax(100, reps) - 1;
        expect(step, greaterThanOrEqualTo(minInsightStrengthChange),
            reason: '$reps -> ${reps + 1} reps is ${step * 100}%');
      }
    });

    test('a whole-kilogram rounding step on a 100 kg lift is below it', () {
      expect(1 / 100, lessThan(minInsightStrengthChange));
    });

    test('an extra rep from five to six is now an insight', () {
      // 2.9%: silent under the old 3%.
      final double change = epleyOneRepMax(100, 6) / epleyOneRepMax(100, 5) - 1;
      expect(change, lessThan(0.03));
      expect(
        strengthOf([strength('Bench', change), strength('Row', .01)])
            .single
            .subjectId,
        'Bench',
      );
    });

    test('says when the comparison is with the first session', () {
      StrengthChange row(String id, {required bool first}) => StrengthChange(
            exerciseId: id,
            exerciseName: id,
            currentBestKg: 47,
            previousBestKg: 13,
            comparedWithFirstSession: first,
          );
      expect(
        strengthOf([row('Bench', first: true), strength('Row', .05)])
            .single
            .sinceFirstSession,
        isTrue,
      );
      expect(
        strengthOf([row('Bench', first: false), strength('Row', .05)])
            .single
            .sinceFirstSession,
        isFalse,
      );
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

  group('back from a break inside the range', () {
    DateTime monday(int offset) =>
        DateTime.parse('2026-01-05').add(Duration(days: offset * 7));
    WorkoutFrequency countWeek(int offset, int count) =>
        WorkoutFrequency(weekStart: monday(offset), workoutCount: count);
    final List<WorkoutFrequency> weeks = <WorkoutFrequency>[
      countWeek(0, 0), // partial first week: left out
      countWeek(1, 0),
      countWeek(2, 0),
      countWeek(3, 0),
      countWeek(4, 0),
      countWeek(5, 1),
      countWeek(6, 1),
      countWeek(7, 2), // this week: left out
    ];
    final DateTime now = monday(7).add(const Duration(days: 2));
    final DateTime rangeStart = monday(0).add(const Duration(days: 2));

    Iterable<ProgressInsight> slipping({DateTime? firstWorkoutAt}) =>
        buildProgressInsights(
          strengthChanges: const [],
          volume: const [],
          frequency: weeks,
          currentMuscleVolume: const [],
          previousMuscleVolume: const [],
          now: now,
          rangeStart: rangeStart,
          firstWorkoutAt: firstWorkoutAt,
        ).where((i) => i.kind == InsightKind.consistencySlipping);

    test('the break counts, so a slow return is slipping', () {
      final ProgressInsight insight =
          slipping(firstWorkoutAt: DateTime.parse('2025-01-01')).single;
      // Two sessions over six whole weeks.
      expect(insight.averageSessionsPerWeek, closeTo(2 / 6, 0.0001));
    });

    test('for someone who started in week 5, it is not', () {
      expect(slipping(firstWorkoutAt: monday(5)), isEmpty);
    });
  });

  group('a range longer than the history', () {
    DateTime monday(int offset) =>
        DateTime.parse('2026-01-05').add(Duration(days: offset * 7));
    // Eight trained weeks, the last four much lighter.
    const List<double> trained = <double>[100, 100, 100, 100, 20, 20, 20, 20];

    Iterable<ProgressInsight> volumeDown(int emptyWeeksBefore) {
      final List<WeeklyVolume> weeks = <WeeklyVolume>[
        for (int i = 0; i < emptyWeeksBefore; i++)
          WeeklyVolume(weekStart: monday(i), totalVolumeKg: 0),
        for (final (int i, double kg) in trained.indexed)
          WeeklyVolume(
            weekStart: monday(emptyWeeksBefore + i),
            totalVolumeKg: kg,
          ),
      ];
      return buildProgressInsights(
        strengthChanges: const [],
        volume: weeks,
        frequency: const [],
        currentMuscleVolume: const [],
        previousMuscleVolume: const [],
        now: monday(emptyWeeksBefore + trained.length)
            .add(const Duration(days: 2)),
      ).where((i) => i.kind == InsightKind.volumeTrendingDown);
    }

    test('says the same about volume whatever the range', () {
      // All-time starts at the first workout; 12 months starts 40 empty
      // weeks earlier. Same workouts, same finding.
      final int allTime = volumeDown(0).single.percentage!;
      final int year = volumeDown(40).single.percentage!;
      expect(allTime, 80);
      expect(year, allTime);
    });
  });
}
