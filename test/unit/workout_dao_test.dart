import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/daos/exercise_dao.dart';
import 'package:fittrack/core/database/daos/workout_dao.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late WorkoutDao workoutDao;
  late ExerciseDao exerciseDao;

  setUp(() async {
    database = AppDatabase.forTesting();
    workoutDao = WorkoutDao(database);
    exerciseDao = ExerciseDao(database);
    await exerciseDao.upsertExercises([
      ExercisesTableCompanion.insert(
        id: 'squat',
        slug: 'squat',
        name: 'Back Squat',
        category: 'strength',
        difficulty: 'intermediate',
        movementPattern: 'kneeDominant',
        isBodyweight: const Value(false),
        seedVersion: 1,
      ),
    ]);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> insertSampleWorkout(
    String workoutId, {
    DateTime? startedAt,
  }) {
    final start = startedAt ?? DateTime.utc(2026, 1, 1);
    return workoutDao.insertWorkout(
      WorkoutsTableCompanion.insert(
        id: workoutId,
        startedAt: start,
        endedAt: Value(start.add(const Duration(hours: 1))),
        totalVolumeKg: const Value(500),
      ),
      [
        WorkoutExercisesTableCompanion.insert(
          id: '${workoutId}_ex1',
          workoutId: workoutId,
          exerciseId: 'squat',
          orderIndex: 0,
        ),
      ],
      [
        WorkoutSetsTableCompanion.insert(
          id: '${workoutId}_set1',
          workoutExerciseId: '${workoutId}_ex1',
          setIndex: 0,
          weightKg: 100,
          reps: 5,
          isCompleted: const Value(true),
        ),
      ],
    );
  }

  group('WorkoutDao', () {
    test('getWithDetails joins the exercise name', () async {
      await insertSampleWorkout('w1');

      final details = await workoutDao.getWithDetails('w1');

      expect(details, isNotNull);
      expect(details!.exercises, hasLength(1));
      expect(details.exerciseNames['w1_ex1'], 'Back Squat');
      expect(details.setsByExercise['w1_ex1'], hasLength(1));
      expect(details.setsByExercise['w1_ex1']!.single.weightKg, 100);
    });

    test('deleteWorkout cascades to exercises and sets', () async {
      await insertSampleWorkout('w1');

      await workoutDao.deleteWorkout('w1');

      expect(await workoutDao.getWithDetails('w1'), isNull);
      final orphanSets = await database.customSelect(
        'SELECT COUNT(*) AS c FROM workout_sets_table '
        'WHERE workout_exercise_id = ?',
        variables: [Variable.withString('w1_ex1')],
      ).getSingle();
      expect(orphanSets.data['c'], 0);
    });

    test('groups completed workouts into weekly frequency in SQL', () async {
      await insertSampleWorkout('w1', startedAt: DateTime.utc(2026, 1, 5));
      await insertSampleWorkout('w2', startedAt: DateTime.utc(2026, 1, 7));
      await insertSampleWorkout('w3', startedAt: DateTime.utc(2026, 1, 19));

      final frequency = await workoutDao.watchWorkoutFrequency().first;

      expect(frequency, hasLength(2));
      expect(frequency[0].workoutCount, 2);
      expect(frequency[1].workoutCount, 1);
    });

    test('updateWorkout replaces exercises/sets and recomputes volume',
        () async {
      await insertSampleWorkout('w1');

      await workoutDao.updateWorkout(
        workoutId: 'w1',
        totalVolumeKg: 240,
        exercises: [
          WorkoutExercisesTableCompanion.insert(
            id: 'w1_ex_new',
            workoutId: 'w1',
            exerciseId: 'squat',
            orderIndex: 0,
          ),
        ],
        sets: [
          WorkoutSetsTableCompanion.insert(
            id: 'w1_set_new',
            workoutExerciseId: 'w1_ex_new',
            setIndex: 0,
            weightKg: 80,
            reps: 3,
            isCompleted: const Value(true),
          ),
        ],
      );

      final details = await workoutDao.getWithDetails('w1');
      expect(details!.workout.totalVolumeKg, 240);
      expect(details.exercises.single.id, 'w1_ex_new');
      expect(details.setsByExercise['w1_ex_new']!.single.weightKg, 80);
      // The old exercise row (and its cascaded set) must be gone.
      expect(details.exerciseNames.containsKey('w1_ex1'), isFalse);
    });
  });
}
