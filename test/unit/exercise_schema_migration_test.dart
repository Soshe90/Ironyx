import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// `workout_exercises.exercise_id` is a `RESTRICT` foreign key, so the v2
/// -> v3 exercise-normalization migration (splitting the old flat
/// `exercises_table` into `exercise_muscles`/`exercise_equipment`/
/// `exercise_instructions`/`exercise_media`) must preserve every exercise
/// `id` exactly — otherwise a device with real logged workout history
/// would hit the same class of crash fixed earlier for reseeding (see
/// `exercise_reseed_test.dart`).
///
/// This simulates a v2-shaped database file (raw SQL, not through the
/// app's own — now v3 — table classes) with one exercise and one workout
/// logged against it, then opens it with the real [AppDatabase] to
/// trigger the actual `onUpgrade` migration.
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ironyx_migration_test');
    dbFile = File('${tempDir.path}/test.sqlite');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  void seedV2Database() {
    final raw = sqlite3.sqlite3.open(dbFile.path);
    raw.execute('''
      CREATE TABLE exercises_table (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        primary_muscle TEXT NOT NULL,
        secondary_muscles TEXT NULL,
        equipment TEXT NOT NULL,
        movement_pattern TEXT NOT NULL,
        instructions TEXT NOT NULL,
        video_url TEXT NULL,
        image_url TEXT NULL,
        is_bodyweight INTEGER NOT NULL DEFAULT 0,
        seed_version INTEGER NOT NULL
      );
    ''');
    raw.execute('''
      INSERT INTO exercises_table
        (id, name, primary_muscle, secondary_muscles, equipment,
         movement_pattern, instructions, video_url, image_url,
         is_bodyweight, seed_version)
      VALUES
        ('squat', 'Back Squat', 'legs', 'glutes,core', 'barbell',
         'kneeDominant', 'Squat with bar on back.', NULL, NULL, 0, 1);
    ''');
    raw.execute('''
      CREATE TABLE workouts_table (
        id TEXT NOT NULL PRIMARY KEY,
        started_at INTEGER NOT NULL
      );
    ''');
    raw.execute('''
      CREATE TABLE workout_exercises_table (
        id TEXT NOT NULL PRIMARY KEY,
        workout_id TEXT NOT NULL REFERENCES workouts_table (id) ON DELETE CASCADE,
        exercise_id TEXT NOT NULL REFERENCES exercises_table (id) ON DELETE RESTRICT,
        order_index INTEGER NOT NULL
      );
    ''');
    raw.execute('''
      INSERT INTO workouts_table (id, started_at) VALUES ('w1', 0);
    ''');
    raw.execute('''
      INSERT INTO workout_exercises_table (id, workout_id, exercise_id, order_index)
      VALUES ('w1_ex1', 'w1', 'squat', 0);
    ''');
    raw.execute('PRAGMA user_version = 2');
    raw.close();
  }

  test('v2 -> v3 migration preserves exercise ids referenced by a workout',
      () async {
    seedV2Database();

    final db = AppDatabase.withExecutor(NativeDatabase(dbFile));
    addTearDown(db.close);

    // Migration must run without throwing (would surface as a
    // FOREIGN KEY constraint failure if 'squat' were deleted+reinserted
    // instead of updated in place).
    final exerciseRow = await db.customSelect(
      'SELECT slug, name, category, difficulty, movement_pattern, '
      'is_bodyweight FROM exercises_table WHERE id = ?',
      variables: [Variable.withString('squat')],
    ).getSingle();
    expect(exerciseRow.data['slug'], 'back-squat');
    expect(exerciseRow.data['name'], 'Back Squat');
    expect(exerciseRow.data['movement_pattern'], 'kneeDominant');
    expect(exerciseRow.data['is_bodyweight'], 0);

    // The workout's reference must still resolve after the rebuild.
    final workoutExercise = await db
        .customSelect(
          "SELECT exercise_id FROM workout_exercises_table WHERE id = 'w1_ex1'",
        )
        .getSingle();
    expect(workoutExercise.data['exercise_id'], 'squat');

    // Muscles/equipment/instructions were fanned out correctly.
    final muscles = await db
        .customSelect(
          "SELECT muscle_id, role FROM exercise_muscles_table WHERE exercise_id = 'squat'",
        )
        .get();
    final muscleSet = muscles
        .map((r) => (r.data['muscle_id'] as String, r.data['role'] as String))
        .toSet();
    expect(muscleSet, {
      ('legs', 'primary'),
      ('glutes', 'secondary'),
      ('core', 'secondary'),
    });

    final equipmentLinks = await db
        .customSelect(
          "SELECT equipment_id FROM exercise_equipment_table WHERE exercise_id = 'squat'",
        )
        .get();
    expect(equipmentLinks.single.data['equipment_id'], 'barbell');

    final instructions = await db
        .customSelect(
          "SELECT step_number, instruction FROM exercise_instructions_table WHERE exercise_id = 'squat'",
        )
        .get();
    expect(instructions.single.data['instruction'], 'Squat with bar on back.');

    // The 11 muscles / 10 equipment rows from the old enums were seeded.
    final muscleCount = await db
        .customSelect('SELECT COUNT(*) AS c FROM muscles_table')
        .getSingle();
    expect(muscleCount.data['c'], 11);
    final equipmentCount = await db
        .customSelect('SELECT COUNT(*) AS c FROM equipment_table')
        .getSingle();
    expect(equipmentCount.data['c'], 10);
  });

  void seedV7Database() {
    final raw = sqlite3.sqlite3.open(dbFile.path);
    raw.execute('''
      CREATE TABLE exercises_table (
        id TEXT NOT NULL PRIMARY KEY,
        slug TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL UNIQUE,
        description TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL,
        difficulty TEXT NOT NULL,
        movement_pattern TEXT NOT NULL,
        force_type TEXT,
        mechanic TEXT,
        is_unilateral INTEGER NOT NULL DEFAULT 0,
        is_bodyweight INTEGER NOT NULL DEFAULT 0,
        seed_version INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    raw.execute('''
      INSERT INTO exercises_table
        (id, slug, name, category, difficulty, movement_pattern,
         seed_version, created_at, updated_at)
      VALUES
        ('squat', 'back-squat', 'Back Squat', 'strength', 'intermediate',
         'kneeDominant', 1, 0, 0),
        ('sled-push', 'sled-push', 'Sled Push', 'other', 'intermediate',
         'other', 0, 0, 0);
    ''');
    raw.execute('PRAGMA user_version = 7');
    raw.close();
  }

  test(
      'v7 -> v8 migration backfills isCustom from the old seedVersion == 0 '
      'convention', () async {
    seedV7Database();

    final db = AppDatabase.withExecutor(NativeDatabase(dbFile));
    addTearDown(db.close);

    final rows = await db
        .customSelect('SELECT id, is_custom FROM exercises_table')
        .get();
    final isCustomById = {
      for (final row in rows)
        row.read<String>('id'): row.read<bool>('is_custom'),
    };
    expect(isCustomById, {'squat': false, 'sled-push': true});
  });

  void seedV9Database() {
    final raw = sqlite3.sqlite3.open(dbFile.path);
    raw.execute('''
      CREATE TABLE exercises_table (
        id TEXT NOT NULL PRIMARY KEY,
        slug TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL UNIQUE,
        description TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL,
        difficulty TEXT NOT NULL,
        movement_pattern TEXT NOT NULL,
        force_type TEXT,
        mechanic TEXT,
        is_unilateral INTEGER NOT NULL DEFAULT 0,
        is_bodyweight INTEGER NOT NULL DEFAULT 0,
        seed_version INTEGER NOT NULL,
        is_custom INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    raw.execute('''
      INSERT INTO exercises_table
        (id, slug, name, category, difficulty, movement_pattern,
         seed_version, created_at, updated_at)
      VALUES
        ('plank', 'plank', 'Plank', 'strength', 'beginner',
         'antiRotation', 1, 0, 0);
    ''');
    raw.execute('''
      CREATE TABLE workouts_table (
        id TEXT NOT NULL PRIMARY KEY,
        started_at INTEGER NOT NULL
      );
    ''');
    raw.execute('''
      CREATE TABLE workout_exercises_table (
        id TEXT NOT NULL PRIMARY KEY,
        workout_id TEXT NOT NULL REFERENCES workouts_table (id) ON DELETE CASCADE,
        exercise_id TEXT NOT NULL REFERENCES exercises_table (id) ON DELETE RESTRICT,
        order_index INTEGER NOT NULL
      );
    ''');
    raw.execute('''
      CREATE TABLE workout_sets_table (
        id TEXT NOT NULL PRIMARY KEY,
        workout_exercise_id TEXT NOT NULL REFERENCES workout_exercises_table (id) ON DELETE CASCADE,
        set_index INTEGER NOT NULL,
        weight_kg REAL NOT NULL,
        reps INTEGER NOT NULL,
        rpe_times10 INTEGER,
        is_completed INTEGER NOT NULL DEFAULT 0,
        is_warmup INTEGER NOT NULL DEFAULT 0,
        rest_seconds INTEGER,
        note TEXT
      );
    ''');
    raw.execute('''
      INSERT INTO workouts_table (id, started_at) VALUES ('w1', 0);
    ''');
    raw.execute('''
      INSERT INTO workout_exercises_table (id, workout_id, exercise_id, order_index)
      VALUES ('w1_ex1', 'w1', 'plank', 0);
    ''');
    raw.execute('''
      INSERT INTO workout_sets_table
        (id, workout_exercise_id, set_index, weight_kg, reps, is_completed)
      VALUES ('w1_ex1_s0', 'w1_ex1', 0, 0, 0, 1);
    ''');
    raw.execute('PRAGMA user_version = 9');
    raw.close();
  }

  test(
      'v9 -> v10 migration adds isTimeBased and durationSeconds without '
      'disturbing existing rows', () async {
    seedV9Database();

    final db = AppDatabase.withExecutor(NativeDatabase(dbFile));
    addTearDown(db.close);

    final exerciseRow = await db.customSelect(
      'SELECT is_time_based FROM exercises_table WHERE id = ?',
      variables: [Variable.withString('plank')],
    ).getSingle();
    expect(exerciseRow.data['is_time_based'], 0);

    final setRow = await db
        .customSelect(
          'SELECT reps, duration_seconds FROM workout_sets_table '
          "WHERE id = 'w1_ex1_s0'",
        )
        .getSingle();
    expect(setRow.data['reps'], 0);
    expect(setRow.data['duration_seconds'], null);
  });

  void seedV10Database() {
    final raw = sqlite3.sqlite3.open(dbFile.path);
    raw.execute('''
      CREATE TABLE exercises_table (
        id TEXT NOT NULL PRIMARY KEY,
        slug TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL UNIQUE,
        description TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL,
        difficulty TEXT NOT NULL,
        movement_pattern TEXT NOT NULL,
        force_type TEXT,
        mechanic TEXT,
        is_unilateral INTEGER NOT NULL DEFAULT 0,
        is_bodyweight INTEGER NOT NULL DEFAULT 0,
        is_time_based INTEGER NOT NULL DEFAULT 0,
        seed_version INTEGER NOT NULL,
        is_custom INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    raw.execute('''
      INSERT INTO exercises_table
        (id, slug, name, category, difficulty, movement_pattern,
         seed_version, created_at, updated_at)
      VALUES
        ('bench', 'bench', 'Bench Press', 'strength', 'intermediate',
         'horizontalPush', 1, 0, 0),
        ('row', 'row', 'Barbell Row', 'strength', 'intermediate',
         'horizontalPull', 1, 0, 0);
    ''');
    raw.execute('''
      CREATE TABLE templates_table (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        description TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_built_in INTEGER NOT NULL DEFAULT 0
      );
    ''');
    raw.execute('''
      CREATE TABLE template_exercises_table (
        id TEXT NOT NULL PRIMARY KEY,
        template_id TEXT NOT NULL REFERENCES templates_table (id) ON DELETE CASCADE,
        exercise_id TEXT NOT NULL REFERENCES exercises_table (id) ON DELETE RESTRICT,
        order_index INTEGER NOT NULL,
        target_sets INTEGER NOT NULL,
        target_reps TEXT,
        target_rpe_times10 INTEGER,
        note TEXT
      );
    ''');
    raw.execute('''
      INSERT INTO templates_table (id, name, created_at, updated_at)
      VALUES ('tpl', 'template name', 0, 0);
    ''');
    raw.execute('''
      INSERT INTO template_exercises_table
        (id, template_id, exercise_id, order_index, target_sets)
      VALUES ('tpl_ex_bench', 'tpl', 'bench', 0, 3),
             ('tpl_ex_row', 'tpl', 'row', 1, 3);
    ''');
    raw.execute('''
      CREATE TABLE workouts_table (
        id TEXT NOT NULL PRIMARY KEY,
        started_at INTEGER NOT NULL
      );
    ''');
    raw.execute('''
      CREATE TABLE workout_exercises_table (
        id TEXT NOT NULL PRIMARY KEY,
        workout_id TEXT NOT NULL REFERENCES workouts_table (id) ON DELETE CASCADE,
        exercise_id TEXT NOT NULL REFERENCES exercises_table (id) ON DELETE RESTRICT,
        order_index INTEGER NOT NULL,
        is_warmup INTEGER NOT NULL DEFAULT 0,
        note TEXT
      );
    ''');
    raw.execute('''
      INSERT INTO workouts_table (id, started_at) VALUES ('w1', 0);
    ''');
    raw.execute('''
      INSERT INTO workout_exercises_table
        (id, workout_id, exercise_id, order_index)
      VALUES ('w1_ex_bench', 'w1', 'bench', 0),
             ('w1_ex_row', 'w1', 'row', 1);
    ''');
    raw.execute('PRAGMA user_version = 10');
    raw.close();
  }

  test(
      'v10 -> v11 migration adds supersetGroupId to template and workout '
      'exercise tables without disturbing existing rows', () async {
    seedV10Database();

    final db = AppDatabase.withExecutor(NativeDatabase(dbFile));
    addTearDown(db.close);

    final templateRow = await db
        .customSelect(
          'SELECT superset_group_id FROM template_exercises_table '
          "WHERE id = 'tpl_ex_bench'",
        )
        .getSingle();
    expect(templateRow.data['superset_group_id'], null);

    final workoutRow = await db
        .customSelect(
          'SELECT superset_group_id FROM workout_exercises_table '
          "WHERE id = 'w1_ex_bench'",
        )
        .getSingle();
    expect(workoutRow.data['superset_group_id'], null);
  });
}
