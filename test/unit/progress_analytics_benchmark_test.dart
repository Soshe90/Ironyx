import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';

/// Keeps the Phase 2/4 aggregates honest against the project's representative
/// history size: 3,000 workouts and 36,000 sets. This is a regression guard,
/// not a precision microbenchmark; the limit catches accidental O(n²) queries.
void main() {
  test('progress aggregates remain bounded on 3,000 workouts', () async {
    final database = AppDatabase.forTesting();
    addTearDown(database.close);
    await database.into(database.musclesTable).insert(
          MusclesTableCompanion.insert(
              id: 'chest', name: 'chest', displayName: 'Chest'),
        );
    await database.into(database.exercisesTable).insert(
          ExercisesTableCompanion.insert(
            id: 'bench',
            slug: 'bench',
            name: 'Bench',
            category: 'strength',
            difficulty: 'intermediate',
            movementPattern: 'horizontalPush',
            seedVersion: 1,
          ),
        );
    await database.into(database.exerciseMusclesTable).insert(
          ExerciseMusclesTableCompanion.insert(
            id: 'bench_chest',
            exerciseId: 'bench',
            muscleId: 'chest',
            role: 'primary',
          ),
        );

    final workouts = <WorkoutsTableCompanion>[];
    final workoutExercises = <WorkoutExercisesTableCompanion>[];
    final sets = <WorkoutSetsTableCompanion>[];
    final origin = DateTime.utc(2020, 1, 6);
    for (var workout = 0; workout < 3000; workout++) {
      final id = 'benchmark_workout_$workout';
      final exerciseId = '${id}_exercise';
      final date = origin.add(Duration(days: workout));
      workouts.add(WorkoutsTableCompanion.insert(
        id: id,
        startedAt: date,
        endedAt: Value(date.add(const Duration(hours: 1))),
        totalVolumeKg: const Value(1200),
      ));
      workoutExercises.add(WorkoutExercisesTableCompanion.insert(
        id: exerciseId,
        workoutId: id,
        exerciseId: 'bench',
        orderIndex: 0,
      ));
      for (var set = 0; set < 12; set++) {
        sets.add(WorkoutSetsTableCompanion.insert(
          id: '${id}_set_$set',
          workoutExerciseId: exerciseId,
          setIndex: set,
          weightKg: 100,
          reps: 5,
          isCompleted: const Value(true),
        ));
      }
    }
    await database.batch((batch) {
      batch.insertAll(database.workoutsTable, workouts);
      batch.insertAll(database.workoutExercisesTable, workoutExercises);
      batch.insertAll(database.workoutSetsTable, sets);
    });

    final dao = WorkoutDao(database);
    final stopwatch = Stopwatch()..start();
    await Future.wait([
      dao.watchBalanceRatios().first,
      dao.watchWeeklyMuscleGroupVolume().first,
      dao.watchRepRangeDistribution().first,
      dao.watchWeekdayDistribution().first,
      dao.watchRpeAnalytics().first,
      dao.watchRestAnalytics().first,
    ]);
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
