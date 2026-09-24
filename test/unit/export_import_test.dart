import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/services/data_export_service.dart';
import 'package:ironyx/features/settings/domain/export_envelope.dart';

/// The M6 exit criterion, verbatim: "Export → wipe → import produces
/// byte-identical data." Verified here as deep-equal table contents (the
/// `exportedAt` timestamp in the envelope itself necessarily differs
/// between two real export calls, so the comparison is on `tables`, not
/// the raw JSON string).
void main() {
  late Directory snapshotDir;

  setUp(() {
    snapshotDir = Directory.systemTemp.createTempSync('ironyx_export_test');
  });

  tearDown(() {
    snapshotDir.deleteSync(recursive: true);
  });

  Future<void> seed(AppDatabase database) async {
    final exerciseDao = ExerciseDao(database);
    final workoutDao = WorkoutDao(database);

    await exerciseDao.upsertExercises([
      ExercisesTableCompanion.insert(
        id: 'bench',
        slug: 'bench',
        name: 'Bench Press',
        category: 'strength',
        difficulty: 'intermediate',
        movementPattern: 'horizontalPush',
        seedVersion: 1,
      ),
    ]);

    await workoutDao.insertWorkout(
      WorkoutsTableCompanion.insert(
        id: 'w1',
        startedAt: DateTime.utc(2026, 1, 1),
        endedAt: Value(DateTime.utc(2026, 1, 1, 1)),
        totalVolumeKg: const Value(300),
      ),
      [
        WorkoutExercisesTableCompanion.insert(
          id: 'w1_ex',
          workoutId: 'w1',
          exerciseId: 'bench',
          orderIndex: 0,
        ),
      ],
      [
        WorkoutSetsTableCompanion.insert(
          id: 'w1_set',
          workoutExerciseId: 'w1_ex',
          setIndex: 0,
          weightKg: 60,
          reps: 5,
          isCompleted: const Value(true),
        ),
      ],
    );
  }

  test('export -> import into a fresh database reproduces the same table data',
      () async {
    const service = DataExportService();

    final source = AppDatabase.forTesting();
    await seed(source);
    final String exportedJson = await service.buildJsonExport(source);
    await source.close();

    final destination = AppDatabase.forTesting();
    final envelope = service.parseImport(exportedJson);
    await service.applyImport(
      destination,
      envelope,
      mode: ImportMode.replace,
      snapshotDirPath: snapshotDir.path,
    );

    final String reExportedJson = await service.buildJsonExport(destination);
    await destination.close();

    final Map<String, dynamic> original =
        jsonDecode(exportedJson) as Map<String, dynamic>;
    final Map<String, dynamic> roundTripped =
        jsonDecode(reExportedJson) as Map<String, dynamic>;
    expect(roundTripped['tables'], equals(original['tables']));
  });

  test(
      'a local custom exercise survives a full export -> wipe -> import '
      'round trip', () async {
    const service = DataExportService();

    final source = AppDatabase.forTesting();
    await seed(source);
    // seedVersion 0 marks an exercise as user-created (e.g. via XLSX
    // import) rather than shipped catalogue content — it must round-trip
    // exactly like any other exercises_table row, not be treated as
    // disposable because it didn't come from the seeder.
    await ExerciseDao(source).upsertExercises([
      ExercisesTableCompanion.insert(
        id: 'custom-sled-push',
        slug: 'custom-sled-push',
        name: 'Sled Push',
        category: 'other',
        difficulty: 'intermediate',
        movementPattern: 'other',
        seedVersion: 0,
        isCustom: const Value(true),
      ),
    ]);
    final String exportedJson = await service.buildJsonExport(source);
    await source.close();

    final destination = AppDatabase.forTesting();
    final envelope = service.parseImport(exportedJson);
    await service.applyImport(
      destination,
      envelope,
      mode: ImportMode.replace,
      snapshotDirPath: snapshotDir.path,
    );

    final custom = await ExerciseDao(destination).getById('custom-sled-push');
    expect(custom, isNotNull);
    expect(custom!.seedVersion, 0);
    expect(custom.isCustom, isTrue);
    await destination.close();
  });

  test('merge mode upserts by id without disturbing unrelated existing rows',
      () async {
    const service = DataExportService();

    final source = AppDatabase.forTesting();
    await seed(source);
    final String exportedJson = await service.buildJsonExport(source);
    await source.close();

    final destination = AppDatabase.forTesting();
    final exerciseDao = ExerciseDao(destination);
    await exerciseDao.upsertExercises([
      ExercisesTableCompanion.insert(
        id: 'squat',
        slug: 'squat',
        name: 'Back Squat',
        category: 'strength',
        difficulty: 'intermediate',
        movementPattern: 'kneeDominant',
        seedVersion: 1,
      ),
    ]);

    final envelope = service.parseImport(exportedJson);
    await service.applyImport(
      destination,
      envelope,
      mode: ImportMode.merge,
      snapshotDirPath: snapshotDir.path,
    );

    final workoutDao = WorkoutDao(destination);
    final imported = await workoutDao.getWithDetails('w1');
    expect(imported, isNotNull);
    // The pre-existing exercise, untouched by the import, must survive.
    expect(await exerciseDao.getById('squat'), isNotNull);
    await destination.close();
  });

  test('pre-import snapshot can restore data after a replace', () async {
    const service = DataExportService();
    final database = AppDatabase.forTesting();
    await seed(database);

    final emptyEnvelope = ImportEnvelope(
      formatVersion: DataExportService.formatVersion,
      // Read from the database rather than hardcoded: import rejects any
      // schema mismatch, so a literal here silently breaks this test on
      // every schema bump.
      dbSchemaVersion: database.schemaVersion,
      appVersion: '0.1.0',
      exportedAt: DateTime(2026, 1, 1),
      // Replace now requires every non-catalogue table to be present
      // (even empty) so a truncated file can't be mistaken for "wipe
      // everything" — see the missing-table rejection test below.
      tables: {
        for (final table in database.allTables)
          if (!DataExportService.catalogueTableNames
              .contains(table.actualTableName))
            table.actualTableName: <Map<String, Object?>>[],
      },
    );
    await service.applyImport(
      database,
      emptyEnvelope,
      mode: ImportMode.replace,
      snapshotDirPath: snapshotDir.path,
    );
    expect(
      await database
          .customSelect('SELECT COUNT(*) AS count FROM workouts_table')
          .getSingle()
          .then((row) => row.read<int>('count')),
      0,
    );

    final snapshots = await service.listSnapshots(snapshotDir.path);
    expect(snapshots, hasLength(1));
    await ExerciseDao(database).upsertExercises([
      ExercisesTableCompanion.insert(
        id: 'new-local-catalogue-row',
        slug: 'new-local-catalogue-row',
        name: 'New Local Exercise',
        category: 'strength',
        difficulty: 'beginner',
        movementPattern: 'other',
        seedVersion: 1,
      ),
    ]);
    await service.restoreSnapshot(
      database,
      snapshots.single,
      snapshotDirPath: snapshotDir.path,
    );
    expect(
        await ExerciseDao(database).getById('new-local-catalogue-row'), isNull);
    expect(await ExerciseDao(database).getById('bench'), isNotNull);
    expect(
      await database
          .customSelect('SELECT COUNT(*) AS count FROM workouts_table')
          .getSingle()
          .then((row) => row.read<int>('count')),
      1,
    );
    await database.close();
  });

  test('rejects a file with a newer formatVersion', () async {
    const service = DataExportService();
    final String badJson = jsonEncode({
      'formatVersion': DataExportService.formatVersion + 1,
      'dbSchemaVersion': 4,
      'appVersion': '9.9.9',
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': <String, dynamic>{},
    });

    expect(
      () => service.parseImport(badJson),
      throwsA(isA<ImportValidationException>()),
    );
  });

  group('dbSchemaVersion compatibility', () {
    Map<String, Object?> envelopeJson(int dbSchemaVersion) => {
          'formatVersion': DataExportService.formatVersion,
          'dbSchemaVersion': dbSchemaVersion,
          'appVersion': '0.1.0',
          'exportedAt': DateTime.now().toIso8601String(),
          'tables': <String, dynamic>{},
        };

    test('accepts a backup matching the current schema version', () async {
      const service = DataExportService();
      final database = AppDatabase.forTesting();
      final envelope = service.parseImport(
        jsonEncode(envelopeJson(database.schemaVersion)),
      );
      // A schema-version match with no tables is otherwise a normal
      // (if empty) replace, so this must not throw.
      await service.applyImport(
        database,
        envelope,
        mode: ImportMode.merge,
        snapshotDirPath: snapshotDir.path,
      );
      await database.close();
    });

    test(
        'upgrades a backup from an older schema version instead of '
        'rejecting it (ADR-7)', () async {
      // Previously rejected outright, which made every backup unrestorable
      // after any schema change. The upgrade steps themselves are covered
      // against real historical exports in export_schema_upgrade_test.dart.
      const service = DataExportService();
      final database = AppDatabase.forTesting();
      final envelope = service.parseImport(
        jsonEncode(envelopeJson(database.schemaVersion - 1)),
      );

      await service.applyImport(
        database,
        envelope,
        mode: ImportMode.merge,
        snapshotDirPath: snapshotDir.path,
      );
      await database.close();
    });

    test('rejects a backup from a newer, unsupported schema version', () async {
      const service = DataExportService();
      final database = AppDatabase.forTesting();
      final envelope = service.parseImport(
        jsonEncode(envelopeJson(database.schemaVersion + 1)),
      );

      await expectLater(
        service.applyImport(
          database,
          envelope,
          mode: ImportMode.merge,
          snapshotDirPath: snapshotDir.path,
        ),
        throwsA(isA<ImportValidationException>()),
      );
      await database.close();
    });
  });

  test(
      'replace mode leaves the local exercise catalogue intact when the '
      'backup omits it', () async {
    const service = DataExportService();

    final destination = AppDatabase.forTesting();
    final exerciseDao = ExerciseDao(destination);
    await exerciseDao.upsertExercises([
      ExercisesTableCompanion.insert(
        id: 'bench',
        slug: 'bench',
        name: 'Bench Press',
        category: 'strength',
        difficulty: 'intermediate',
        movementPattern: 'horizontalPush',
        seedVersion: 1,
      ),
    ]);

    // A backup that has no 'exercises_table' key at all — every other
    // non-catalogue table must still be present for replace to accept it.
    final String partialJson = jsonEncode({
      'formatVersion': DataExportService.formatVersion,
      'dbSchemaVersion': destination.schemaVersion,
      'appVersion': '0.1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': <String, dynamic>{
        for (final table in destination.allTables)
          if (!DataExportService.catalogueTableNames
              .contains(table.actualTableName))
            table.actualTableName: <Map<String, Object?>>[],
      },
    });
    final envelope = service.parseImport(partialJson);
    await service.applyImport(
      destination,
      envelope,
      mode: ImportMode.replace,
      snapshotDirPath: snapshotDir.path,
    );

    expect(await exerciseDao.getById('bench'), isNotNull);
    await destination.close();
  });

  group('replace onto an install whose catalogue is already seeded', () {
    // The real reinstall case: the seeder fills the catalogue on first
    // launch, so a restore always meets a populated one. ADR-7 keeps that
    // catalogue as it is; exercises the backup needs but the device lacks
    // must still arrive, or the workouts that use them cannot.
    late AppDatabase source;
    late AppDatabase destination;
    const service = DataExportService();

    ExercisesTableCompanion exercise(
      String id, {
      String? name,
      int seedVersion = 1,
      bool isCustom = false,
    }) =>
        ExercisesTableCompanion.insert(
          id: id,
          slug: id,
          name: name ?? 'Exercise $id',
          category: 'strength',
          difficulty: 'intermediate',
          movementPattern: 'other',
          seedVersion: seedVersion,
          isCustom: Value(isCustom),
        );

    Future<void> logWorkoutWith(String exerciseId) =>
        WorkoutDao(source).insertWorkout(
          WorkoutsTableCompanion.insert(
            id: 'w_$exerciseId',
            startedAt: DateTime.utc(2026, 1, 1),
          ),
          [
            WorkoutExercisesTableCompanion.insert(
              id: 'we_$exerciseId',
              workoutId: 'w_$exerciseId',
              exerciseId: exerciseId,
              orderIndex: 0,
            ),
          ],
          const [],
        );

    Future<void> restore() async => service.applyImport(
          destination,
          service.parseImport(await service.buildJsonExport(source)),
          mode: ImportMode.replace,
          snapshotDirPath: snapshotDir.path,
        );

    setUp(() async {
      source = AppDatabase.forTesting();
      destination = AppDatabase.forTesting();
      await ExerciseDao(source).upsertExercises([exercise('bench')]);
      await ExerciseDao(destination).upsertExercises([exercise('bench')]);
    });

    tearDown(() async {
      await source.close();
      await destination.close();
    });

    test('a custom exercise and the workout using it are restored', () async {
      await ExerciseDao(source).upsertExercises([
        exercise('my_lift', seedVersion: 0, isCustom: true),
      ]);
      await logWorkoutWith('my_lift');

      await restore();

      final restored = await ExerciseDao(destination).getById('my_lift');
      expect(restored, isNotNull);
      expect(restored!.isCustom, isTrue);
      expect(
        (await WorkoutDao(destination).watchAll().first).map((w) => w.id),
        ['w_my_lift'],
      );
    });

    test('a retired seed exercise still referenced by a workout is restored',
        () async {
      await ExerciseDao(source).upsertExercises([exercise('old_curl')]);
      await logWorkoutWith('old_curl');

      await restore();

      expect(await ExerciseDao(destination).getById('old_curl'), isNotNull);
    });

    test(
        'an unused missing exercise is left out, so a name clash on it '
        'cannot block the restore', () async {
      await ExerciseDao(source).upsertExercises([
        exercise('unused_old', name: 'Exercise clash'),
      ]);
      await ExerciseDao(destination).upsertExercises([
        exercise('renamed_local', name: 'Exercise clash'),
      ]);

      await restore();

      expect(await ExerciseDao(destination).getById('unused_old'), isNull);
    });

    test('existing local catalogue rows are never overwritten', () async {
      await ExerciseDao(source).upsertExercises([
        exercise('bench', name: 'Renamed In Backup'),
      ]);

      await restore();

      expect(
        (await ExerciseDao(destination).getById('bench'))!.name,
        'Exercise bench',
      );
    });

    test(
        'a missing exercise whose name is taken locally is refused before '
        'anything is written', () async {
      await ExerciseDao(source).upsertExercises([
        exercise('dup_id', name: 'Exercise x'),
      ]);
      await logWorkoutWith('dup_id');
      await ExerciseDao(destination).upsertExercises([
        exercise('other_id', name: 'Exercise x'),
      ]);
      await WorkoutDao(destination).insertWorkout(
        WorkoutsTableCompanion.insert(
          id: 'local_workout',
          startedAt: DateTime.utc(2026, 2, 1),
        ),
        const [],
        const [],
      );

      await expectLater(
        restore(),
        throwsA(
          isA<ImportValidationException>()
              .having((e) => e.message, 'message', contains('Exercise x')),
        ),
      );
      expect(
        (await WorkoutDao(destination).watchAll().first).map((w) => w.id),
        ['local_workout'],
      );
    });
  });

  test(
      'replace rejects a backup missing a user-data table instead of '
      'wiping it', () async {
    const service = DataExportService();
    final destination = AppDatabase.forTesting();
    await seed(destination);

    // Truncated/hand-edited backup: every non-catalogue table present
    // except 'timer_sessions_table'.
    final String truncatedJson = jsonEncode({
      'formatVersion': DataExportService.formatVersion,
      'dbSchemaVersion': destination.schemaVersion,
      'appVersion': '0.1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': <String, dynamic>{
        for (final table in destination.allTables)
          if (!DataExportService.catalogueTableNames
                  .contains(table.actualTableName) &&
              table.actualTableName != 'timer_sessions_table')
            table.actualTableName: <Map<String, Object?>>[],
      },
    });
    final envelope = service.parseImport(truncatedJson);

    await expectLater(
      service.applyImport(
        destination,
        envelope,
        mode: ImportMode.replace,
        snapshotDirPath: snapshotDir.path,
      ),
      throwsA(isA<ImportValidationException>()),
    );

    // The seeded workout must survive untouched: rejection must happen
    // before any DELETE runs.
    final workoutDao = WorkoutDao(destination);
    expect(await workoutDao.getWithDetails('w1'), isNotNull);
    // No snapshot should have been written for a rejected import either.
    expect(await service.listSnapshots(snapshotDir.path), isEmpty);
    await destination.close();
  });

  test('rejects a backup that references an unrecognized table', () async {
    const service = DataExportService();
    final destination = AppDatabase.forTesting();

    final String unknownTableJson = jsonEncode({
      'formatVersion': DataExportService.formatVersion,
      'dbSchemaVersion': destination.schemaVersion,
      'appVersion': '0.1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': <String, dynamic>{
        'not_a_real_table': <Map<String, Object?>>[],
      },
    });
    final envelope = service.parseImport(unknownTableJson);

    await expectLater(
      service.applyImport(
        destination,
        envelope,
        mode: ImportMode.merge,
        snapshotDirPath: snapshotDir.path,
      ),
      throwsA(isA<ImportValidationException>()),
    );
    await destination.close();
  });

  test('rejects a JSON import containing a dangling foreign key', () async {
    const service = DataExportService();

    final source = AppDatabase.forTesting();
    await seed(source);
    final String validJson = await service.buildJsonExport(source);
    await source.close();

    // Corrupt the exported workout-exercise row to reference an exercise
    // that doesn't exist anywhere in this envelope — simulating a
    // hand-edited or bit-corrupted backup rather than building one from
    // scratch, since that would require reproducing sqlite's exact epoch/
    // boolean column representation by hand.
    final Map<String, dynamic> decoded =
        jsonDecode(validJson) as Map<String, dynamic>;
    final tables = decoded['tables'] as Map<String, dynamic>;
    final workoutExercises =
        (tables['workout_exercises_table'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
    workoutExercises.first['exercise_id'] = 'does-not-exist';
    final String corruptedJson = jsonEncode(decoded);

    final destination = AppDatabase.forTesting();
    final envelope = service.parseImport(corruptedJson);

    await expectLater(
      service.applyImport(
        destination,
        envelope,
        mode: ImportMode.replace,
        snapshotDirPath: snapshotDir.path,
      ),
      throwsException,
    );

    // The foreign-key violation must roll back everything, not just skip
    // the bad row.
    final count = await destination
        .customSelect('SELECT COUNT(*) AS count FROM workouts_table')
        .getSingle()
        .then((row) => row.read<int>('count'));
    expect(count, 0);
    await destination.close();
  });

  group('row validation happens before snapshots or writes', () {
    Future<Map<String, dynamic>> exportedTables() async {
      final source = AppDatabase.forTesting();
      await seed(source);
      final json = await const DataExportService().buildJsonExport(source);
      await source.close();
      return (jsonDecode(json) as Map<String, dynamic>)['tables']
          as Map<String, dynamic>;
    }

    test('rejects a missing required column with table and row context',
        () async {
      const service = DataExportService();
      final database = AppDatabase.forTesting();
      final tables = await exportedTables();
      final workout = (tables['workouts_table'] as List<dynamic>).first
          as Map<String, dynamic>;
      workout.remove('started_at');
      final envelope = ImportEnvelope(
        formatVersion: DataExportService.formatVersion,
        dbSchemaVersion: database.schemaVersion,
        appVersion: '0.1.0',
        exportedAt: DateTime.utc(2026),
        tables: tables.map(
          (key, value) => MapEntry(
            key,
            (value as List<dynamic>)
                .map((row) =>
                    (row as Map<String, dynamic>).cast<String, Object?>())
                .toList(),
          ),
        ),
      );

      await expectLater(
        service.applyImport(
          database,
          envelope,
          mode: ImportMode.replace,
          snapshotDirPath: snapshotDir.path,
        ),
        throwsA(
          predicate<ImportValidationException>(
            (error) =>
                error.message.contains('workouts_table row 1') &&
                error.message.contains('started_at'),
          ),
        ),
      );
      expect(await service.listSnapshots(snapshotDir.path), isEmpty);
      await database.close();
    });

    test('rejects invalid scalar types before touching the database', () async {
      const service = DataExportService();
      final database = AppDatabase.forTesting();
      final tables = await exportedTables();
      final set = (tables['workout_sets_table'] as List<dynamic>).first
          as Map<String, dynamic>;
      set['reps'] = 'five';
      final envelope = ImportEnvelope(
        formatVersion: DataExportService.formatVersion,
        dbSchemaVersion: database.schemaVersion,
        appVersion: '0.1.0',
        exportedAt: DateTime.utc(2026),
        tables: tables.map(
          (key, value) => MapEntry(
            key,
            (value as List<dynamic>)
                .map((row) =>
                    (row as Map<String, dynamic>).cast<String, Object?>())
                .toList(),
          ),
        ),
      );

      await expectLater(
        service.applyImport(
          database,
          envelope,
          mode: ImportMode.replace,
          snapshotDirPath: snapshotDir.path,
        ),
        throwsA(isA<ImportValidationException>()),
      );
      expect(await service.listSnapshots(snapshotDir.path), isEmpty);
      await database.close();
    });

    /// Mutates one row of an otherwise valid export and asserts the import is
    /// refused up front: with [message] in the error, no snapshot written and
    /// nothing changed in the destination.
    Future<void> expectRejected(
      void Function(Map<String, dynamic> tables) mutate,
      String message,
    ) async {
      const service = DataExportService();
      final database = AppDatabase.forTesting();
      final tables = await exportedTables();
      mutate(tables);
      final envelope = ImportEnvelope(
        formatVersion: DataExportService.formatVersion,
        dbSchemaVersion: database.schemaVersion,
        appVersion: '0.1.0',
        exportedAt: DateTime.utc(2026),
        tables: tables.map(
          (key, value) => MapEntry(
            key,
            (value as List<dynamic>)
                .map((row) =>
                    (row as Map<String, dynamic>).cast<String, Object?>())
                .toList(),
          ),
        ),
      );

      await expectLater(
        service.applyImport(
          database,
          envelope,
          mode: ImportMode.replace,
          snapshotDirPath: snapshotDir.path,
        ),
        throwsA(
          predicate<ImportValidationException>(
            (error) => error.message.contains(message),
            'an ImportValidationException mentioning "$message"',
          ),
        ),
      );
      expect(await service.listSnapshots(snapshotDir.path), isEmpty);
      final int workouts = await database
          .customSelect('SELECT COUNT(*) AS count FROM workouts_table')
          .getSingle()
          .then((row) => row.read<int>('count'));
      expect(workouts, 0);
      await database.close();
    }

    Map<String, dynamic> firstRow(
      Map<String, dynamic> tables,
      String table,
    ) =>
        (tables[table] as List<dynamic>).first as Map<String, dynamic>;

    test('rejects an id that is neither a UUID nor a plain identifier',
        () async {
      // Renamed consistently with its child row, so the foreign key still
      // resolves and only the id's own shape is wrong.
      await expectRejected((tables) {
        const String bad = 'not a uuid!!';
        final String original =
            firstRow(tables, 'workouts_table')['id']! as String;
        for (final row in (tables['workouts_table'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .where((row) => row['id'] == original)) {
          row['id'] = bad;
        }
        for (final row in (tables['workout_exercises_table'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .where((row) => row['workout_id'] == original)) {
          row['workout_id'] = bad;
        }
      }, 'must be a UUID or a plain alphanumeric identifier');
    });

    test('rejects a boolean column that is not 0 or 1', () async {
      await expectRejected(
        (tables) => firstRow(tables, 'workout_sets_table')['is_completed'] = 2,
        '"is_completed" has an invalid value type',
      );
    });

    test('rejects a REAL column that is not finite', () async {
      await expectRejected(
        (tables) =>
            firstRow(tables, 'workout_sets_table')['weight_kg'] = double.nan,
        '"weight_kg" has an invalid value type',
      );
    });

    test('rejects a null in a required column', () async {
      await expectRejected(
        (tables) => firstRow(tables, 'workout_sets_table')['reps'] = null,
        'required column "reps" cannot be null',
      );
    });

    test('rejects a column the schema does not have', () async {
      await expectRejected(
        (tables) => firstRow(tables, 'workouts_table')['bogus_column'] = 1,
        'unknown column "bogus_column"',
      );
    });

    test('rejects a duplicated primary key', () async {
      await expectRejected((tables) {
        final rows = tables['workouts_table'] as List<dynamic>;
        rows.add(Map<String, dynamic>.of(rows.first as Map<String, dynamic>));
      }, 'duplicate primary key');
    });
  });

  test('rejects a file that is not valid JSON', () {
    const service = DataExportService();
    expect(
      () => service.parseImport('not json'),
      throwsA(isA<ImportValidationException>()),
    );
  });

  group('stream refresh (writes go through customStatement)', () {
    test('a replace import notifies existing watch() streams', () async {
      const service = DataExportService();
      final database = AppDatabase.forTesting();
      addTearDown(database.close);
      await seed(database);

      final emissions = <int>[];
      final subscription =
          database.select(database.workoutsTable).watch().listen(
                (rows) => emissions.add(rows.length),
              );
      await pumpEventQueue();
      expect(emissions, [1]);

      final envelope = service.parseImport(await service.buildJsonExport(
        database,
      ));
      await service.applyImport(
        database,
        ImportEnvelope(
          formatVersion: envelope.formatVersion,
          dbSchemaVersion: envelope.dbSchemaVersion,
          appVersion: envelope.appVersion,
          exportedAt: envelope.exportedAt,
          tables: {
            ...envelope.tables,
            // Emptied together: a replace import must not leave a
            // `workout_exercises_table`/`workout_sets_table` row dangling on
            // a `workouts_table` id that no longer exists in the envelope.
            'workouts_table': const [],
            'workout_exercises_table': const [],
            'workout_sets_table': const [],
          },
        ),
        mode: ImportMode.replace,
        snapshotDirPath: snapshotDir.path,
      );
      await pumpEventQueue();

      expect(
        emissions,
        [1, 0],
        reason: 'the stream must re-emit after a replace import, not keep '
            'showing the pre-import row',
      );
      await subscription.cancel();
    });

    test('deleteAllUserData notifies existing watch() streams', () async {
      const service = DataExportService();
      final database = AppDatabase.forTesting();
      addTearDown(database.close);
      await seed(database);

      final emissions = <int>[];
      final subscription =
          database.select(database.workoutsTable).watch().listen(
                (rows) => emissions.add(rows.length),
              );
      await pumpEventQueue();
      expect(emissions, [1]);

      await service.deleteAllUserData(database);
      await pumpEventQueue();

      expect(
        emissions,
        [1, 0],
        reason: 'the stream must re-emit after delete-all, not keep showing '
            'the deleted workout',
      );
      await subscription.cancel();
    });
  });
}
