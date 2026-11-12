import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/services/export_schema_upgrades.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// The v12 -> v13 migration recomputes the stored total of a workout that
/// holds an assisted set (a negative weight), which adds no volume.
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ironyx_assisted_mig');
    dbFile = File('${tempDir.path}/test.sqlite');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<void> addWorkout(
    AppDatabase db,
    String id, {
    required double storedTotal,
    required List<(double, int, bool)> sets,
  }) =>
      WorkoutDao(db).insertWorkout(
        WorkoutsTableCompanion.insert(
          id: id,
          startedAt: DateTime.utc(2026, 1, 1),
          endedAt: Value(DateTime.utc(2026, 1, 1, 1)),
          totalVolumeKg: Value(storedTotal),
        ),
        [
          WorkoutExercisesTableCompanion.insert(
            id: '${id}_we',
            workoutId: id,
            exerciseId: 'pull',
            orderIndex: 0,
          ),
        ],
        [
          for (final (int i, (double weight, int reps, bool warmup))
              in sets.indexed)
            WorkoutSetsTableCompanion.insert(
              id: '${id}_s$i',
              workoutExerciseId: '${id}_we',
              setIndex: i,
              weightKg: weight,
              reps: reps,
              isCompleted: const Value(true),
              isWarmup: Value(warmup),
            ),
        ],
      );

  test(
      'an upgrade from v12 recomputes only workouts with an assisted set, '
      'and keeps the sets', () async {
    final AppDatabase before = AppDatabase.withExecutor(NativeDatabase(dbFile));
    await ExerciseDao(before).upsertExercises([
      ExercisesTableCompanion.insert(
        id: 'pull',
        slug: 'pull',
        name: 'Pull-Up',
        category: 'strength',
        difficulty: 'intermediate',
        movementPattern: 'verticalPull',
        seedVersion: 1,
      ),
    ]);
    // As the old XLSX import stored it: 60×5 + (-20×8) = 140.
    await addWorkout(
      before,
      'assisted',
      storedTotal: 140,
      sets: [(60, 5, false), (-20, 8, false), (40, 5, true)],
    );
    // A total written by some other rule, deliberately not 60×5: untouched.
    await addWorkout(
      before,
      'plain',
      storedTotal: 999,
      sets: [(60, 5, false)],
    );
    await before.close();

    final raw = sqlite3.sqlite3.open(dbFile.path);
    raw.execute('PRAGMA user_version = 12');
    raw.close();

    final AppDatabase after = AppDatabase.withExecutor(NativeDatabase(dbFile));
    addTearDown(after.close);
    final Map<String, double> totals = {
      for (final w in await after.select(after.workoutsTable).get())
        w.id: w.totalVolumeKg,
    };

    expect(totals['assisted'], 300, reason: 'the warm-up is not counted');
    expect(totals['plain'], 999);
    expect(await after.select(after.workoutSetsTable).get(), hasLength(4));
  });

  test('the export step recomputes the same workouts in an older backup', () {
    final ExportTables tables = {
      'workouts_table': [
        {'id': 'assisted', 'total_volume_kg': 140.0},
        {'id': 'plain', 'total_volume_kg': 999.0},
      ],
      'workout_exercises_table': [
        {'id': 'a_we', 'workout_id': 'assisted', 'is_warmup': 0},
        {'id': 'p_we', 'workout_id': 'plain'},
      ],
      'workout_sets_table': [
        {
          'workout_exercise_id': 'a_we',
          'weight_kg': 60.0,
          'reps': 5,
          'is_completed': 1,
          'is_warmup': 0,
        },
        {
          'workout_exercise_id': 'a_we',
          'weight_kg': -20.0,
          'reps': 8,
          'is_completed': 1,
          'is_warmup': 0,
        },
        {
          'workout_exercise_id': 'p_we',
          'weight_kg': 60.0,
          'reps': 5,
          'is_completed': 1,
        },
      ],
    };

    exportSchemaUpgrades[12]!(tables);

    expect(tables['workouts_table']![0]['total_volume_kg'], 300.0);
    expect(tables['workouts_table']![1]['total_volume_kg'], 999.0);
  });
}
