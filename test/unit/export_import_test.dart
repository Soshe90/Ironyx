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

    // A hand-edited/partial backup that has no 'exercises_table' key at all.
    final String partialJson = jsonEncode({
      'formatVersion': DataExportService.formatVersion,
      'dbSchemaVersion': 4,
      'appVersion': '0.1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': <String, dynamic>{
        'workouts_table': <Map<String, Object?>>[],
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

  test('rejects a file that is not valid JSON', () {
    const service = DataExportService();
    expect(
      () => service.parseImport('not json'),
      throwsA(isA<ImportValidationException>()),
    );
  });
}
