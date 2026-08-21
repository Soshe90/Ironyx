import 'package:drift/drift.dart' show Value;
import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/daos/exercise_dao.dart';
import 'package:fittrack/core/database/daos/workout_dao.dart';
import 'package:flutter_test/flutter_test.dart';

/// A seed-content update must never crash — or silently loop forever on
/// every launch — just because a user already logged a workout against one
/// of the exercises being touched. `workout_exercises.exercise_id` is a
/// RESTRICT foreign key, so a naive delete-then-reinsert reseed (or
/// `InsertMode.insertOrReplace`, which SQLite implements as delete-then-
/// insert) throws the moment that happens.
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

  ExercisesTableCompanion squat(
      {required int seedVersion, String name = 'Back Squat'}) {
    return ExercisesTableCompanion.insert(
      id: 'squat',
      slug: 'squat',
      name: name,
      category: 'strength',
      difficulty: 'intermediate',
      movementPattern: 'kneeDominant',
      isBodyweight: const Value(false),
      seedVersion: seedVersion,
    );
  }

  ExercisesTableCompanion curl({required int seedVersion}) {
    return ExercisesTableCompanion.insert(
      id: 'curl',
      slug: 'curl',
      name: 'Bicep Curl',
      category: 'strength',
      difficulty: 'intermediate',
      movementPattern: 'other',
      isBodyweight: const Value(false),
      seedVersion: seedVersion,
    );
  }

  test('reseeding an exercise referenced by a logged workout does not throw',
      () async {
    await exerciseDao
        .upsertExercises([squat(seedVersion: 1), curl(seedVersion: 1)]);
    await workoutDao.insertWorkout(
      WorkoutsTableCompanion.insert(
          id: 'w1', startedAt: DateTime.utc(2026, 1, 1)),
      [
        WorkoutExercisesTableCompanion.insert(
          id: 'w1_ex1',
          workoutId: 'w1',
          exerciseId: 'squat',
          orderIndex: 0,
        ),
      ],
      [
        WorkoutSetsTableCompanion.insert(
          id: 'w1_set1',
          workoutExerciseId: 'w1_ex1',
          setIndex: 0,
          weightKg: 100,
          reps: 5,
        ),
      ],
    );

    // 'curl' is dropped from the new seed (orphaned); 'squat' is kept but
    // edited, simulating a content-curation update after a version bump.
    await exerciseDao.deleteOrphanedSeed(2);
    await exerciseDao.upsertExercises([
      squat(seedVersion: 2, name: 'Back Squat (updated cue)'),
    ]);

    final squatRow = await exerciseDao.getById('squat');
    expect(squatRow!.name, 'Back Squat (updated cue)');
    expect(squatRow.seedVersion, 2);

    // The referenced exercise must survive even though it fell below the
    // new seed version at the delete step — deleting it would have thrown.
    final curlRow = await exerciseDao.getById('curl');
    expect(curlRow, isNull, reason: 'unreferenced orphan should be removed');

    final details = await workoutDao.getWithDetails('w1');
    expect(details!.exerciseNames['w1_ex1'], 'Back Squat (updated cue)');
  });
}
