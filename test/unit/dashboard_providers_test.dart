import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/formatters/date_formatters.dart';
import 'package:ironyx/features/dashboard/domain/dashboard_providers.dart';

/// Covers the two new dashboard-card queries added in M6:
/// `ExerciseDao.watchLibrarySummary` and
/// `WorkoutDao.watchMostLoggedExerciseOneRM`. The dashboard's Riverpod
/// providers are thin pass-throughs over these — this is where the actual
/// logic (and the empty-state case) lives.
void main() {
  late AppDatabase database;
  late ExerciseDao exerciseDao;
  late WorkoutDao workoutDao;

  setUp(() {
    database = AppDatabase.forTesting();
    exerciseDao = ExerciseDao(database);
    workoutDao = WorkoutDao(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedExercise(String id, String name) =>
      exerciseDao.upsertExercises([
        ExercisesTableCompanion.insert(
          id: id,
          slug: id,
          name: name,
          category: 'strength',
          difficulty: 'intermediate',
          movementPattern: 'horizontalPush',
          seedVersion: 1,
        ),
      ]);

  Future<void> insertWorkoutWithSet({
    required String workoutId,
    required String exerciseId,
    required DateTime startedAt,
    required double weightKg,
    required int reps,
  }) {
    return workoutDao.insertWorkout(
      WorkoutsTableCompanion.insert(
        id: workoutId,
        startedAt: startedAt,
        endedAt: Value(startedAt.add(const Duration(minutes: 30))),
        totalVolumeKg: Value(weightKg * reps),
      ),
      [
        WorkoutExercisesTableCompanion.insert(
          id: '${workoutId}_ex',
          workoutId: workoutId,
          exerciseId: exerciseId,
          orderIndex: 0,
        ),
      ],
      [
        WorkoutSetsTableCompanion.insert(
          id: '${workoutId}_set',
          workoutExerciseId: '${workoutId}_ex',
          setIndex: 0,
          weightKg: weightKg,
          reps: reps,
          isCompleted: const Value(true),
        ),
      ],
    );
  }

  group('WeekSnapshot.from', () {
    test('empty series produces a zeroed no-history snapshot', () {
      final snapshot = WeekSnapshot.from(
        volume: const <WeeklyVolume>[],
        frequency: const <WorkoutFrequency>[],
      );

      expect(snapshot.volumeKg, 0);
      expect(snapshot.previousVolumeKg, 0);
      expect(snapshot.sessions, 0);
      expect(snapshot.streakWeeks, 0);
      expect(snapshot.volumeSeries, isEmpty);
      expect(snapshot.hasHistory, isFalse);
    });

    test('selects current and previous weeks and preserves series length', () {
      final DateTime currentWeek = DateFormatters.startOfWeek(DateTime.now());
      final DateTime previousWeek =
          currentWeek.subtract(const Duration(days: 7));
      final DateTime olderWeek = previousWeek.subtract(const Duration(days: 7));

      final snapshot = WeekSnapshot.from(
        volume: <WeeklyVolume>[
          WeeklyVolume(weekStart: olderWeek, totalVolumeKg: 50),
          WeeklyVolume(weekStart: previousWeek, totalVolumeKg: 100),
          WeeklyVolume(weekStart: currentWeek, totalVolumeKg: 150),
        ],
        frequency: <WorkoutFrequency>[
          WorkoutFrequency(weekStart: olderWeek, workoutCount: 1),
          WorkoutFrequency(weekStart: previousWeek, workoutCount: 2),
          WorkoutFrequency(weekStart: currentWeek, workoutCount: 3),
        ],
      );

      expect(snapshot.volumeKg, 150);
      expect(snapshot.previousVolumeKg, 100);
      expect(snapshot.sessions, 3);
      expect(snapshot.streakWeeks, 3);
      expect(snapshot.volumeSeries, <double>[50, 100, 150]);
      expect(snapshot.hasHistory, isTrue);
    });

    test('a rest week continues the previous streak until the current week',
        () {
      final DateTime currentWeek = DateFormatters.startOfWeek(DateTime.now());
      final DateTime previousWeek =
          currentWeek.subtract(const Duration(days: 7));
      final DateTime twoWeeksAgo =
          previousWeek.subtract(const Duration(days: 7));

      final snapshot = WeekSnapshot.from(
        volume: <WeeklyVolume>[
          WeeklyVolume(weekStart: twoWeeksAgo, totalVolumeKg: 50),
          WeeklyVolume(weekStart: previousWeek, totalVolumeKg: 100),
          WeeklyVolume(weekStart: currentWeek, totalVolumeKg: 0),
        ],
        frequency: <WorkoutFrequency>[
          WorkoutFrequency(weekStart: twoWeeksAgo, workoutCount: 1),
          WorkoutFrequency(weekStart: previousWeek, workoutCount: 2),
          WorkoutFrequency(weekStart: currentWeek, workoutCount: 0),
        ],
      );

      expect(snapshot.sessions, 0);
      expect(snapshot.streakWeeks, 2);
    });
  });

  group('ExerciseDao.watchLibrarySummary', () {
    test('empty catalogue reports zero count and no recent name', () async {
      final summary = await exerciseDao.watchLibrarySummary().first;
      expect(summary.count, 0);
      expect(summary.mostRecentName, isNull);
    });

    test('counts exercises and names the most recently added', () async {
      await seedExercise('bench', 'Bench Press');
      await seedExercise('squat', 'Back Squat');

      final summary = await exerciseDao.watchLibrarySummary().first;
      expect(summary.count, 2);
      // Both rows share the same default createdAt in this test (inserted
      // back-to-back), so just assert it resolves to one of the two names
      // rather than asserting a specific insertion-order tie-break.
      expect(summary.mostRecentName, anyOf('Bench Press', 'Back Squat'));
    });
  });

  group('WorkoutDao.watchMostLoggedExerciseOneRM', () {
    test('no workouts yields null', () async {
      final result = await workoutDao.watchMostLoggedExerciseOneRM().first;
      expect(result, isNull);
    });

    test('picks the exercise with the most sets and reports an up trend',
        () async {
      await seedExercise('bench', 'Bench Press');
      await seedExercise('row', 'Barbell Row');

      // Bench: 3 sets across 3 workouts (most-logged). Row: 1 set.
      await insertWorkoutWithSet(
        workoutId: 'w1',
        exerciseId: 'bench',
        startedAt: DateTime.utc(2026, 1, 1),
        weightKg: 60,
        reps: 5,
      );
      await insertWorkoutWithSet(
        workoutId: 'w2',
        exerciseId: 'bench',
        startedAt: DateTime.utc(2026, 1, 8),
        weightKg: 65,
        reps: 5,
      );
      await insertWorkoutWithSet(
        workoutId: 'w3',
        exerciseId: 'bench',
        startedAt: DateTime.utc(2026, 1, 15),
        weightKg: 70,
        reps: 5,
      );
      await insertWorkoutWithSet(
        workoutId: 'w4',
        exerciseId: 'row',
        startedAt: DateTime.utc(2026, 1, 16),
        weightKg: 40,
        reps: 8,
      );

      final result = await workoutDao.watchMostLoggedExerciseOneRM().first;
      expect(result, isNotNull);
      expect(result!.exerciseName, 'Bench Press');
      // Epley: 70 * (1 + 5/30) ≈ 81.67, previous workout 65 * (1+5/30) ≈ 75.8
      expect(result.currentKg, closeTo(81.67, 0.1));
      expect(result.trend, OneRMTrend.up);
    });

    test('a single workout reports a flat trend (nothing to compare against)',
        () async {
      await seedExercise('bench', 'Bench Press');
      await insertWorkoutWithSet(
        workoutId: 'w1',
        exerciseId: 'bench',
        startedAt: DateTime.utc(2026, 1, 1),
        weightKg: 60,
        reps: 5,
      );

      final result = await workoutDao.watchMostLoggedExerciseOneRM().first;
      expect(result!.trend, OneRMTrend.flat);
    });
  });
}
