import 'package:drift/drift.dart';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import 'tables/body_metrics.dart';
import 'tables/equipment.dart';
import 'tables/exercise_aliases.dart';
import 'tables/exercise_equipment.dart';
import 'tables/exercise_instructions.dart';
import 'tables/exercise_media.dart';
import 'tables/exercise_muscles.dart';
import 'tables/exercise_sources.dart';
import 'tables/exercise_tags.dart';
import 'tables/exercise_variations.dart';
import 'tables/exercises.dart';
import 'tables/muscles.dart';
import 'tables/programs.dart';
import 'tables/templates.dart';
import 'tables/timer_presets.dart';
import 'tables/timer_sessions.dart';
import 'tables/workout_exercises.dart';
import 'tables/workout_sets.dart';
import 'tables/workouts.dart';
import 'testing_database_executor.dart';

part 'app_database.g.dart';

/// Drift database for all durable FitTrack data.
@DriftDatabase(
  tables: <Type>[
    ExercisesTable,
    MusclesTable,
    EquipmentTable,
    ExerciseMusclesTable,
    ExerciseEquipmentTable,
    ExerciseInstructionsTable,
    ExerciseAliasesTable,
    ExerciseMediaTable,
    ExerciseVariationsTable,
    ExerciseSourcesTable,
    ExerciseTagsTable,
    WorkoutsTable,
    WorkoutExercisesTable,
    WorkoutSetsTable,
    TemplatesTable,
    TemplateExercisesTable,
    ProgramsTable,
    ProgramTemplatesTable,
    TimerSessionsTable,
    TimerIntervalsTable,
    TimerPresetsTable,
    BodyMetricsTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'fittrack'));

  /// In-memory database used by unit and widget tests.
  AppDatabase.forTesting() : super(createTestingExecutor());

  /// Opens an arbitrary executor — used by migration tests to reopen a
  /// simulated old-schema file and exercise the real `onUpgrade` path.
  @visibleForTesting
  AppDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) => m.createAll(),
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            // Historical step, frozen as raw SQL rather than a reference to
            // `exercisesTable.imageUrl` — that column no longer exists on
            // the current (v3+) table definition, but a v1 database still
            // needs it added transiently so the v3 migration below can read
            // it uniformly regardless of which version it's coming from.
            await customStatement(
              'ALTER TABLE exercises_table ADD COLUMN image_url TEXT',
            );
          }
          if (from < 3) {
            await _normalizeExercises(m);
          }
          if (from < 4) {
            await m.createTable(timerPresetsTable);
          }
          if (from < 5) {
            await m.createTable(programsTable);
            await m.createTable(programTemplatesTable);
          }
        },
        beforeOpen: (OpeningDetails details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Splits the old flat `exercises_table` (single primary/secondary
  /// muscle, single equipment, one instructions paragraph, two nullable
  /// media columns) into the normalized muscles/equipment/instructions/
  /// media tables.
  ///
  /// `id` is preserved exactly for every existing exercise —
  /// `workout_exercises.exercise_id` is a `RESTRICT` foreign key, so any
  /// exercise a logged workout references must keep resolving after this
  /// runs (see the migration test, which simulates exactly that case).
  Future<void> _normalizeExercises(Migrator m) async {
    const uuid = Uuid();
    final now = DateTime.now().toUtc();

    // 1. Read every row in the old shape before anything is touched.
    final oldRows = await customSelect(
      'SELECT id, name, primary_muscle, secondary_muscles, equipment, '
      'movement_pattern, instructions, video_url, image_url, '
      'is_bodyweight, seed_version FROM exercises_table',
    ).get();

    // 2. Move the old table aside and create every table in the new shape.
    await customStatement(
      'ALTER TABLE exercises_table RENAME TO exercises_table_v2',
    );
    await m.createTable(exercisesTable);
    await m.createTable(musclesTable);
    await m.createTable(equipmentTable);
    await m.createTable(exerciseMusclesTable);
    await m.createTable(exerciseEquipmentTable);
    await m.createTable(exerciseInstructionsTable);
    await m.createTable(exerciseAliasesTable);
    await m.createTable(exerciseMediaTable);
    await m.createTable(exerciseVariationsTable);
    await m.createTable(exerciseSourcesTable);
    await m.createTable(exerciseTagsTable);

    // 3. Seed the muscle/equipment taxonomy from the old enums — same ids
    // the seeder uses going forward, so a later reseed upserts rather than
    // duplicating.
    const muscleSeed = <(String, String)>[
      ('chest', 'Chest'),
      ('back', 'Back'),
      ('shoulders', 'Shoulders'),
      ('arms', 'Arms'),
      ('legs', 'Legs'),
      ('glutes', 'Glutes'),
      ('core', 'Core'),
      ('calves', 'Calves'),
      ('forearms', 'Forearms'),
      ('traps', 'Traps'),
      ('neck', 'Neck'),
    ];
    for (final (id, displayName) in muscleSeed) {
      await into(musclesTable).insert(
        MusclesTableCompanion.insert(
            id: id, name: id, displayName: displayName),
      );
    }

    const equipmentSeed = <(String, String)>[
      ('barbell', 'Barbell'),
      ('dumbbell', 'Dumbbell'),
      ('machine', 'Machine'),
      ('cable', 'Cable'),
      ('bodyweight', 'Bodyweight'),
      ('kettlebell', 'Kettlebell'),
      ('band', 'Band'),
      ('plate', 'Plate'),
      ('sled', 'Sled'),
      ('other', 'Other'),
    ];
    for (final (id, name) in equipmentSeed) {
      await into(equipmentTable).insert(
        EquipmentTableCompanion.insert(id: id, name: name),
      );
    }

    // 4. Migrate every existing exercise's row and fan its data out into
    // the new child tables.
    for (final row in oldRows) {
      final id = row.read<String>('id');
      final name = row.read<String>('name');
      final primaryMuscle = row.read<String>('primary_muscle');
      final secondaryMuscles = row.readNullable<String>('secondary_muscles');
      final equipmentId = row.read<String>('equipment');
      final movementPattern = row.read<String>('movement_pattern');
      final instructions = row.read<String>('instructions');
      final videoUrl = row.readNullable<String>('video_url');
      final imageUrl = row.readNullable<String>('image_url');
      final isBodyweight = row.read<bool>('is_bodyweight');
      final seedVersion = row.read<int>('seed_version');

      await into(exercisesTable).insert(
        ExercisesTableCompanion.insert(
          id: id,
          slug: _slugify(name),
          name: name,
          category: 'strength',
          difficulty: 'intermediate',
          movementPattern: movementPattern,
          isBodyweight: Value(isBodyweight),
          seedVersion: seedVersion,
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      await into(exerciseMusclesTable).insert(
        ExerciseMusclesTableCompanion.insert(
          id: uuid.v4(),
          exerciseId: id,
          muscleId: primaryMuscle,
          role: 'primary',
        ),
      );
      for (final muscle in (secondaryMuscles ?? '')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)) {
        await into(exerciseMusclesTable).insert(
          ExerciseMusclesTableCompanion.insert(
            id: uuid.v4(),
            exerciseId: id,
            muscleId: muscle,
            role: 'secondary',
          ),
        );
      }

      await into(exerciseEquipmentTable).insert(
        ExerciseEquipmentTableCompanion.insert(
          id: uuid.v4(),
          exerciseId: id,
          equipmentId: equipmentId,
        ),
      );

      await into(exerciseInstructionsTable).insert(
        ExerciseInstructionsTableCompanion.insert(
          id: uuid.v4(),
          exerciseId: id,
          stepNumber: 1,
          instruction: instructions,
        ),
      );

      if (imageUrl != null) {
        await into(exerciseMediaTable).insert(
          ExerciseMediaTableCompanion.insert(
            id: uuid.v4(),
            exerciseId: id,
            type: 'image',
            url: Value(imageUrl),
          ),
        );
      }
      if (videoUrl != null) {
        await into(exerciseMediaTable).insert(
          ExerciseMediaTableCompanion.insert(
            id: uuid.v4(),
            exerciseId: id,
            type: 'video',
            url: Value(videoUrl),
          ),
        );
      }
    }

    // 5. The old table has been fully migrated — drop it.
    await customStatement('DROP TABLE exercises_table_v2');
  }

  String _slugify(String value) {
    final lower = value.toLowerCase().replaceAll("'", '');
    return lower
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }
}
