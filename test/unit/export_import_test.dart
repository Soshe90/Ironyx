import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/daos/exercise_dao.dart';
import 'package:fittrack/core/database/daos/workout_dao.dart';
import 'package:fittrack/core/services/data_export_service.dart';
import 'package:fittrack/features/settings/domain/export_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

/// The M6 exit criterion, verbatim: "Export → wipe → import produces
/// byte-identical data." Verified here as deep-equal table contents (the
/// `exportedAt` timestamp in the envelope itself necessarily differs
/// between two real export calls, so the comparison is on `tables`, not
/// the raw JSON string).
void main() {
  late Directory snapshotDir;

  setUp(() {
    snapshotDir = Directory.systemTemp.createTempSync('fittrack_export_test');
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

    test('rejects a backup from an older schema version', () async {
      const service = DataExportService();
      final database = AppDatabase.forTesting();
      final envelope = service.parseImport(
        jsonEncode(envelopeJson(database.schemaVersion - 1)),
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
  });

  test('rejects a file that is not valid JSON', () {
    const service = DataExportService();
    expect(
      () => service.parseImport('not json'),
      throwsA(isA<ImportValidationException>()),
    );
  });
}
