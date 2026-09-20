import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';

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
    await database.into(database.exercisesTable).insert(
          ExercisesTableCompanion.insert(
            id: 'accessory_push',
            slug: 'accessory-push',
            name: 'Tricep Pushdown',
            category: 'strength',
            difficulty: 'beginner',
            movementPattern: 'horizontalPush',
            seedVersion: 17,
          ),
        );
    await database.into(database.exercisesTable).insert(
          ExercisesTableCompanion.insert(
            id: 'accessory_pull',
            slug: 'accessory-pull',
            name: 'Face Pull',
            category: 'strength',
            difficulty: 'beginner',
            movementPattern: 'horizontalPull',
            seedVersion: 17,
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

  /// One workout, one exercise, N sets described as (weight, reps, rpe×10).
  Future<void> insertSets({
    required String id,
    required DateTime date,
    required String exerciseId,
    required List<(double, int, int?)> sets,
  }) =>
      dao.insertWorkout(
        WorkoutsTableCompanion.insert(
          id: id,
          startedAt: date,
          endedAt: Value(date.add(const Duration(hours: 1))),
          totalVolumeKg: Value(
            sets.fold<double>(0, (sum, s) => sum + s.$1 * s.$2),
          ),
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
          for (final (int index, (double weight, int reps, int? rpe))
              in sets.indexed)
            WorkoutSetsTableCompanion.insert(
              id: '${id}_set_$index',
              workoutExerciseId: '${id}_exercise',
              setIndex: index,
              weightKg: weight,
              reps: reps,
              isCompleted: const Value(true),
              rpeTimes10: Value(rpe),
            ),
        ],
      );

  test('balance ratios include accessory push and pull patterns', () async {
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
    await insertWorkout(
        id: 'accessory_push_workout',
        date: DateTime.utc(2026, 1, 7),
        exerciseId: 'accessory_push',
        reps: 5);
    await insertWorkout(
        id: 'accessory_pull_workout',
        date: DateTime.utc(2026, 1, 8),
        exerciseId: 'accessory_pull',
        reps: 10);

    final result = await dao.watchBalanceRatios().first;
    expect(result.pushVolumeKg, 200);
    expect(result.pullVolumeKg, 300);
    expect(result.pushPullRatio, closeTo(2 / 3, 0.0001));
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

  test('weekday distribution applies the UTC offset to the day boundary',
      () async {
    // Monday 2026-01-05 22:30 UTC is already Tuesday at UTC+3.
    await insertWorkout(
        id: 'late',
        date: DateTime.utc(2026, 1, 5, 22, 30),
        exerciseId: 'push',
        reps: 5);
    final utc = await dao.watchWeekdayDistribution().first;
    expect(utc[0].workoutCount, 1);
    expect(utc[1].workoutCount, 0);
    final local = await dao
        .watchWeekdayDistribution(utcOffset: const Duration(hours: 3))
        .first;
    expect(local[0].workoutCount, 0);
    expect(local[1].workoutCount, 1);
    expect(local[1].trainingDayCount, 1);
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

  test('RPE analytics reports whole-session volume when a set has no RPE',
      () async {
    await insertSets(
      id: 'partial_rpe',
      date: DateTime.utc(2026, 1, 5),
      exerciseId: 'push',
      sets: [(20, 10, 70), (20, 10, 90), (20, 10, null)],
    );
    final result = await dao.watchRpeAnalytics().first;
    // Averaged over the two sets that carry an RPE...
    expect(result.single.averageRpe, 8);
    // ...but the volume is the session's, matching every other volume
    // figure in the app rather than dropping the un-rated set's 200 kg.
    expect(result.single.volumeKg, 600);
  });

  test('RPE analytics omits a session with no RPE anywhere', () async {
    await insertSets(
      id: 'no_rpe',
      date: DateTime.utc(2026, 1, 5),
      exerciseId: 'push',
      sets: [(20, 10, null)],
    );
    expect(await dao.watchRpeAnalytics().first, isEmpty);
  });

  test('session volume load counts sets above the 1RM rep window', () async {
    await insertSets(
      id: 'high_rep',
      date: DateTime.utc(2026, 1, 5),
      exerciseId: 'push',
      sets: [(20, 20, null)],
    );
    await insertSets(
      id: 'low_rep',
      date: DateTime.utc(2026, 1, 6),
      exerciseId: 'push',
      sets: [(20, 10, null)],
    );
    final result = await dao.watchSessionVolumeLoad('push').first;
    // A 20-rep session is still work done; only the 1RM estimate needs the
    // reps-1-12 window, and dropping the session hid it from the history.
    expect(result.map((row) => row.volumeKg), [400, 200]);
  });

  test('unloaded sets stay out of every 1RM-derived figure', () async {
    await insertSets(
      id: 'bodyweight',
      date: DateTime.utc(2026, 1, 5),
      exerciseId: 'push',
      sets: [(0, 10, null)],
    );
    await insertSets(
      id: 'loaded',
      date: DateTime.utc(2026, 1, 6),
      exerciseId: 'pull',
      sets: [(20, 10, null)],
    );
    // Epley over a zero load estimates 0 kg, which is not a strength figure.
    expect(await dao.watchOneRMSeries('push').first, isEmpty);
    expect(
      (await dao.watchLoggedExercises().first).map((row) => row.exerciseId),
      ['pull'],
    );
    expect(
      (await dao.watchStrengthChange().first).map((row) => row.exerciseId),
      ['pull'],
    );
    // The work itself is still counted where volume is the measure.
    expect(
      (await dao.watchSessionVolumeLoad('push').first).single.volumeKg,
      0,
    );
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
