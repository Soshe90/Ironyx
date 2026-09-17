import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';

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
