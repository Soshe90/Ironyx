import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/daos/workout_dao.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late WorkoutDao dao;

  setUp(() async {
    database = AppDatabase.forTesting();
    dao = WorkoutDao(database);
    await database.into(database.musclesTable).insert(
          MusclesTableCompanion.insert(
            id: 'chest',
            name: 'chest',
            displayName: 'Chest',
          ),
        );
    await database.into(database.musclesTable).insert(
          MusclesTableCompanion.insert(
            id: 'back',
            name: 'back',
            displayName: 'Back',
          ),
        );
    await database.into(database.exercisesTable).insert(
          ExercisesTableCompanion.insert(
            id: 'push',
            slug: 'push',
            name: 'Push',
            category: 'strength',
            difficulty: 'intermediate',
            movementPattern: 'horizontalPush',
            seedVersion: 1,
          ),
        );
    await database.into(database.exercisesTable).insert(
          ExercisesTableCompanion.insert(
            id: 'pull',
            slug: 'pull',
            name: 'Pull',
            category: 'strength',
            difficulty: 'intermediate',
            movementPattern: 'horizontalPull',
            seedVersion: 1,
          ),
        );
    await database.into(database.exerciseMusclesTable).insert(
          ExerciseMusclesTableCompanion.insert(
            id: 'push_muscle',
            exerciseId: 'push',
            muscleId: 'chest',
            role: 'primary',
          ),
        );
    await database.into(database.exerciseMusclesTable).insert(
          ExerciseMusclesTableCompanion.insert(
            id: 'pull_muscle',
            exerciseId: 'pull',
            muscleId: 'back',
            role: 'primary',
          ),
        );
  });

  tearDown(() => database.close());

  Future<void> insertWorkout({
    required String id,
    required DateTime date,
    required String exerciseId,
    required int reps,
    int? rpeTimes10,
    int? restSeconds,
  }) =>
      dao.insertWorkout(
        WorkoutsTableCompanion.insert(
          id: id,
          startedAt: date,
          endedAt: Value(date.add(const Duration(hours: 1))),
          totalVolumeKg: const Value(100),
        ),
        [
          WorkoutExercisesTableCompanion.insert(
            id: '${id}_exercise',
            workoutId: id,
            exerciseId: exerciseId,
            orderIndex: 0,
          ),
        ],
        [
          WorkoutSetsTableCompanion.insert(
            id: '${id}_set',
            workoutExerciseId: '${id}_exercise',
            setIndex: 0,
            weightKg: 20,
            reps: reps,
            isCompleted: const Value(true),
            rpeTimes10: Value(rpeTimes10),
            restSeconds: Value(restSeconds),
          ),
        ],
      );

  test('balance ratios use movement patterns and ignore unsupported patterns',
      () async {
    await insertWorkout(
        id: 'push_workout',
        date: DateTime.utc(2026, 1, 5),
        exerciseId: 'push',
        reps: 5);
    await insertWorkout(
        id: 'pull_workout',
        date: DateTime.utc(2026, 1, 6),
        exerciseId: 'pull',
        reps: 5);
    final result = await dao.watchBalanceRatios().first;
    expect(result.pushVolumeKg, result.pullVolumeKg);
    expect(result.pushPullRatio, 1);
    expect(result.upperLowerRatio, isNull);
  });

  test('weekly muscle volume attributes primary muscle and preserves weeks',
      () async {
    await insertWorkout(
        id: 'muscle_workout',
        date: DateTime.utc(2026, 1, 5),
        exerciseId: 'push',
        reps: 5);
    final result = await dao.watchWeeklyMuscleGroupVolume().first;
    expect(result, hasLength(1));
    expect(result.single.muscleName, 'Chest');
    expect(result.single.totalVolumeKg, 100);
  });

  test('rep distribution returns all boundaries and zero buckets', () async {
    await insertWorkout(
        id: 'low', date: DateTime.utc(2026, 1, 5), exerciseId: 'push', reps: 5);
    await insertWorkout(
        id: 'middle',
        date: DateTime.utc(2026, 1, 6),
        exerciseId: 'push',
        reps: 6);
    await insertWorkout(
        id: 'high',
        date: DateTime.utc(2026, 1, 7),
        exerciseId: 'push',
        reps: 13);
    final result = await dao.watchRepRangeDistribution().first;
    expect(result.map((row) => row.setCount), [1, 1, 1]);
    expect(result.map((row) => row.range), RepRange.values);
  });

  test('weekday distribution returns Monday-first seven rows', () async {
    await insertWorkout(
        id: 'monday',
        date: DateTime.utc(2026, 1, 5),
        exerciseId: 'push',
        reps: 5);
    await insertWorkout(
        id: 'sunday',
        date: DateTime.utc(2026, 1, 11),
        exerciseId: 'push',
        reps: 5);
    final result = await dao.watchWeekdayDistribution().first;
    expect(result, hasLength(7));
    expect(result[0].workoutCount, 1);
    expect(result[6].workoutCount, 1);
  });

  test('RPE analytics pairs effort with session volume', () async {
    await insertWorkout(
        id: 'rpe',
        date: DateTime.utc(2026, 1, 5),
        exerciseId: 'push',
        reps: 5,
        rpeTimes10: 75,
        restSeconds: 120);
    final result = await dao.watchRpeAnalytics().first;
    expect(result.single.averageRpe, 7.5);
    expect(result.single.volumeKg, 100);
  });

  test('rest analytics reports average and recorded set count', () async {
    await insertWorkout(
        id: 'rest',
        date: DateTime.utc(2026, 1, 5),
        exerciseId: 'push',
        reps: 5,
        restSeconds: 90);
    final result = await dao.watchRestAnalytics().first;
    expect(result.single.averageRestSeconds, 90);
    expect(result.single.recordedSetCount, 1);
  });
}
