import 'package:drift/drift.dart' show Value;
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/formatters/unit_formatters.dart';
import 'package:ironyx/core/services/workout_xlsx_import_service.dart';

void main() {
  const service = WorkoutXlsxImportService();

  Future<void> seedExercise(AppDatabase database, String id) =>
      ExerciseDao(database).upsertExercises([
        ExercisesTableCompanion.insert(
          id: id,
          slug: id,
          name: id,
          category: 'strength',
          difficulty: 'intermediate',
          movementPattern: 'horizontalPush',
          seedVersion: 1,
        ),
      ]);

  /// Builds the minimal workbook shape `parse()` expects: a date in row 0
  /// at the group's start column, an exercise-name row, then one set row
  /// with reps/weight in the group's two columns.
  List<int> buildWorkbook({
    required DateTime date,
    required String exerciseName,
    required int reps,
    required double weight,
  }) {
    const groupStart = 3;
    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet()!];
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: groupStart, rowIndex: 0))
        .value = DateCellValue(year: date.year, month: date.month, day: date.day);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value =
        TextCellValue(exerciseName);
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: groupStart, rowIndex: 3))
        .value = IntCellValue(reps);
    sheet
        .cell(
          CellIndex.indexByColumnRow(columnIndex: groupStart + 1, rowIndex: 3),
        )
        .value = DoubleCellValue(weight);
    return excel.encode()!;
  }

  test('apply writes one workout per imported session', () async {
    final database = AppDatabase.forTesting();
    await seedExercise(database, 'bench');

    final result = WorkoutXlsxImportResult(
      workouts: [
        ImportedHistoricalWorkout(
          date: DateTime.utc(2026, 1, 1),
          exercises: [
            ImportedHistoricalExercise(
              exerciseId: 'bench',
              name: 'Bench Press',
              sets: [
                const ImportedHistoricalSet(reps: 5, weightKg: 60),
              ],
            ),
          ],
        ),
      ],
      unknownExercises: const [],
      totalSets: 1,
    );

    await service.apply(database, result);

    final count = await database
        .customSelect('SELECT COUNT(*) AS count FROM workouts_table')
        .getSingle()
        .then((row) => row.read<int>('count'));
    expect(count, 1);
    await database.close();
  });

  test(
      'apply rolls back every workout in the batch when one exercise '
      'reference is invalid', () async {
    final database = AppDatabase.forTesting();
    await seedExercise(database, 'bench');

    final result = WorkoutXlsxImportResult(
      workouts: [
        // Valid workout, would succeed in isolation.
        ImportedHistoricalWorkout(
          date: DateTime.utc(2026, 1, 1),
          exercises: [
            ImportedHistoricalExercise(
              exerciseId: 'bench',
              name: 'Bench Press',
              sets: [
                const ImportedHistoricalSet(reps: 5, weightKg: 60),
              ],
            ),
          ],
        ),
        // Second workout references an exercise id that doesn't exist in
        // exercises_table. Supplying a non-null exerciseId skips the
        // "create a custom exercise" path in apply(), so this becomes a
        // foreign-key violation on insert.
        ImportedHistoricalWorkout(
          date: DateTime.utc(2026, 1, 2),
          exercises: [
            ImportedHistoricalExercise(
              exerciseId: 'does-not-exist',
              name: 'Ghost Exercise',
              sets: [
                const ImportedHistoricalSet(reps: 5, weightKg: 40),
              ],
            ),
          ],
        ),
      ],
      unknownExercises: const [],
      totalSets: 2,
    );

    await expectLater(service.apply(database, result), throwsException);

    // The whole apply() runs in one transaction: the first (valid) workout
    // must not survive when the second one fails.
    final count = await database
        .customSelect('SELECT COUNT(*) AS count FROM workouts_table')
        .getSingle()
        .then((row) => row.read<int>('count'));
    expect(count, 0);
    await database.close();
  });

  test('apply creates a custom exercise for an unmatched exercise name',
      () async {
    final database = AppDatabase.forTesting();

    final result = WorkoutXlsxImportResult(
      workouts: [
        ImportedHistoricalWorkout(
          date: DateTime.utc(2026, 1, 1),
          exercises: [
            // No exerciseId: the catalogue has no match for this name.
            ImportedHistoricalExercise(
              exerciseId: null,
              name: 'Sled Push',
              sets: [
                const ImportedHistoricalSet(reps: 10, weightKg: 80),
              ],
            ),
          ],
        ),
      ],
      unknownExercises: const ['Sled Push'],
      totalSets: 1,
    );

    await service.apply(database, result);

    final created = await database
        .customSelect(
          'SELECT seed_version, is_custom FROM exercises_table '
          "WHERE name = 'Sled Push'",
        )
        .getSingleOrNull();
    expect(created, isNotNull);
    // seedVersion 0 marks it as user-imported rather than shipped catalogue
    // content, matching ExerciseSeeder's versioning (always >= 1).
    expect(created!.read<int>('seed_version'), 0);
    expect(created.read<bool>('is_custom'), isTrue);

    final workoutCount = await database
        .customSelect('SELECT COUNT(*) AS count FROM workouts_table')
        .getSingle()
        .then((row) => row.read<int>('count'));
    expect(workoutCount, 1);
    await database.close();
  });

  test(
      'a non-Latin exercise name still gets a sane slug when created as '
      'custom', () async {
    // `_normalize` strips everything outside `[a-z0-9]`, so an Arabic name
    // normalizes to the empty string. The id suffix alone still keeps the
    // slug unique, but without a fallback prefix it reads
    // `-imported-a1b2c3d4` — a display bug, not a crash.
    final database = AppDatabase.forTesting();

    final result = WorkoutXlsxImportResult(
      workouts: [
        ImportedHistoricalWorkout(
          date: DateTime.utc(2026, 1, 1),
          exercises: [
            ImportedHistoricalExercise(
              exerciseId: null,
              name: 'دفع الحديد',
              sets: [
                const ImportedHistoricalSet(reps: 10, weightKg: 80),
              ],
            ),
          ],
        ),
      ],
      unknownExercises: const ['دفع الحديد'],
      totalSets: 1,
    );

    await service.apply(database, result);

    final created = await database
        .customSelect(
          "SELECT slug FROM exercises_table WHERE name = 'دفع الحديد'",
        )
        .getSingleOrNull();
    expect(created, isNotNull);
    expect(created!.read<String>('slug'), startsWith('exercise-imported-'));
    await database.close();
  });

  test(
      'importing the same workbook twice skips the duplicate the second '
      'time', () async {
    final database = AppDatabase.forTesting();
    await seedExercise(database, 'bench-press');

    final bytes = buildWorkbook(
      date: DateTime.utc(2026, 1, 1),
      exerciseName: 'bench-press',
      reps: 5,
      weight: 60,
    );

    final firstParse =
        await service.parse(bytes, database, sourceUnit: WeightUnit.kg);
    expect(firstParse.duplicateCount, 0);
    await service.apply(database, firstParse);

    final secondParse =
        await service.parse(bytes, database, sourceUnit: WeightUnit.kg);
    expect(secondParse.workouts, hasLength(1));
    expect(secondParse.duplicateCount, 1);
    await service.apply(database, secondParse);

    // The duplicate must not have been re-inserted.
    final count = await database
        .customSelect('SELECT COUNT(*) AS count FROM workouts_table')
        .getSingle()
        .then((row) => row.read<int>('count'));
    expect(count, 1);
    await database.close();
  });

  test(
      'retrying an import after a failed attempt does not duplicate the '
      'workout that never committed', () async {
    final database = AppDatabase.forTesting();
    await seedExercise(database, 'bench-press');

    final bytes = buildWorkbook(
      date: DateTime.utc(2026, 1, 1),
      exerciseName: 'bench-press',
      reps: 5,
      weight: 60,
    );

    // First attempt bundles the good workout with an unrelated, broken one
    // that trips a foreign-key violation — the whole transaction rolls
    // back, so nothing from this attempt should exist afterward.
    final firstParse =
        await service.parse(bytes, database, sourceUnit: WeightUnit.kg);
    final brokenResult = WorkoutXlsxImportResult(
      workouts: [
        ...firstParse.workouts,
        ImportedHistoricalWorkout(
          date: DateTime.utc(2026, 1, 2),
          exercises: [
            ImportedHistoricalExercise(
              exerciseId: 'does-not-exist',
              name: 'Ghost Exercise',
              sets: const [ImportedHistoricalSet(reps: 5, weightKg: 40)],
            ),
          ],
        ),
      ],
      unknownExercises: firstParse.unknownExercises,
      totalSets: firstParse.totalSets + 1,
    );
    await expectLater(
      service.apply(database, brokenResult),
      throwsException,
    );
    final countAfterFailure = await database
        .customSelect('SELECT COUNT(*) AS count FROM workouts_table')
        .getSingle()
        .then((row) => row.read<int>('count'));
    expect(countAfterFailure, 0);

    // Retrying with just the original (good) file must insert it exactly
    // once, since the failed attempt left nothing behind to duplicate.
    final retryParse =
        await service.parse(bytes, database, sourceUnit: WeightUnit.kg);
    expect(retryParse.duplicateCount, 0);
    await service.apply(database, retryParse);

    final finalCount = await database
        .customSelect('SELECT COUNT(*) AS count FROM workouts_table')
        .getSingle()
        .then((row) => row.read<int>('count'));
    expect(finalCount, 1);
    await database.close();
  });

  test('a blank trailing sheet does not abort the import of a populated one',
      () async {
    // Real workbooks commonly carry an extra blank tab (a template left over
    // from copying a previous month, say). `parse()` used to index row 0 of
    // every sheet unconditionally, so a sheet with no rows at all threw a
    // RangeError that aborted the whole workbook — including sheets that
    // parsed fine on their own.
    final database = AppDatabase.forTesting();
    await seedExercise(database, 'bench-press');

    final excel = Excel.decodeBytes(
      buildWorkbook(
        date: DateTime.utc(2026, 1, 1),
        exerciseName: 'bench-press',
        reps: 5,
        weight: 60,
      ),
    );
    // `excel['name']` creates the sheet if it doesn't exist yet, with zero
    // rows — exactly the shape a blank tab has.
    excel['Blank Tab'];
    final bytes = excel.encode()!;

    final result =
        await service.parse(bytes, database, sourceUnit: WeightUnit.kg);

    expect(result.workouts, hasLength(1));
    expect(result.totalSets, 1);
    await database.close();
  });

  test('two workouts already at one date no longer break the import', () async {
    final database = AppDatabase.forTesting();
    await seedExercise(database, 'bench-press');
    List<int> workbook(int reps) => buildWorkbook(
          date: DateTime.utc(2026, 1, 1),
          exerciseName: 'bench-press',
          reps: reps,
          weight: 60,
        );

    // Imported, then the file edited and imported again: the edited
    // session is not a duplicate, so a second workout lands on that date.
    await service.apply(
      database,
      await service.parse(workbook(5), database, sourceUnit: WeightUnit.kg),
    );
    final edited =
        await service.parse(workbook(6), database, sourceUnit: WeightUnit.kg);
    expect(edited.duplicateCount, 0);
    await service.apply(database, edited);

    // A third import of either file used to throw "Too many elements".
    final again =
        await service.parse(workbook(5), database, sourceUnit: WeightUnit.kg);
    expect(again.duplicateCount, 1, reason: 'matches the first of the two');
    final third =
        await service.parse(workbook(7), database, sourceUnit: WeightUnit.kg);
    expect(third.duplicateCount, 0);
    await database.close();
  });

  test(
      'a set with a negative weight is left out and counted; a zero weight '
      'is kept', () async {
    // Production review 2026-11-12, finding 6: a negative weight was
    // imported, and its negative volume skewed every total.
    final database = AppDatabase.forTesting();
    addTearDown(database.close);
    await seedExercise(database, 'bench');

    final negative = await service.parse(
      buildWorkbook(
        date: DateTime(2026, 3, 1),
        exerciseName: 'bench',
        reps: 5,
        weight: -10,
      ),
      database,
      sourceUnit: WeightUnit.kg,
    );
    expect(negative.negativeWeightSetsSkipped, 1);
    expect(negative.totalSets, 0);
    expect(negative.workouts, isEmpty,
        reason: 'its only set was left out, so nothing is left to import');

    final zero = await service.parse(
      buildWorkbook(
        date: DateTime(2026, 3, 1),
        exerciseName: 'bench',
        reps: 12,
        weight: 0,
      ),
      database,
      sourceUnit: WeightUnit.kg,
    );
    expect(zero.negativeWeightSetsSkipped, 0);
    expect(zero.totalSets, 1);
  });

  test(
      'a session imported before negative weights were left out is still '
      'recognised as already imported', () async {
    // The negative set was stored then and is left out of a parse now;
    // compared as stored, the session no longer matched and was imported
    // a second time.
    final database = AppDatabase.forTesting();
    addTearDown(database.close);
    await seedExercise(database, 'bench');
    await WorkoutDao(database).insertWorkout(
      WorkoutsTableCompanion.insert(
        id: 'old',
        startedAt: DateTime.utc(2026, 3, 1, 12),
        endedAt: Value(DateTime.utc(2026, 3, 1, 13)),
      ),
      [
        WorkoutExercisesTableCompanion.insert(
          id: 'old_we',
          workoutId: 'old',
          exerciseId: 'bench',
          orderIndex: 0,
        ),
      ],
      [
        WorkoutSetsTableCompanion.insert(
          id: 'old_s0',
          workoutExerciseId: 'old_we',
          setIndex: 0,
          weightKg: 60,
          reps: 5,
          isCompleted: const Value(true),
        ),
        WorkoutSetsTableCompanion.insert(
          id: 'old_s1',
          workoutExerciseId: 'old_we',
          setIndex: 1,
          weightKg: -10,
          reps: 5,
          isCompleted: const Value(true),
        ),
      ],
    );

    final result = await service.parse(
      buildWorkbook(
        date: DateTime(2026, 3, 1),
        exerciseName: 'bench',
        reps: 5,
        weight: 60,
      ),
      database,
      sourceUnit: WeightUnit.kg,
    );

    expect(result.workouts.single.isDuplicate, isTrue);
  });

  test('an unknown exercise whose sets were all left out is not listed',
      () async {
    final database = AppDatabase.forTesting();
    addTearDown(database.close);

    final result = await service.parse(
      buildWorkbook(
        date: DateTime(2026, 3, 1),
        exerciseName: 'Mystery Lift',
        reps: 5,
        weight: -10,
      ),
      database,
      sourceUnit: WeightUnit.kg,
    );

    expect(result.unknownExercises, isEmpty,
        reason: 'the preview would promise a custom exercise never created');
    expect(result.negativeWeightSetsSkipped, 1);
  });

  test('a workbook over the size limit is refused before it is read', () async {
    final database = AppDatabase.forTesting();
    await expectLater(
      service.parse(
        List<int>.filled(kMaxWorkoutXlsxBytes + 1, 0),
        database,
        sourceUnit: WeightUnit.kg,
      ),
      throwsA(isA<WorkoutXlsxTooLargeException>()),
    );
    await database.close();
  });

  test('a file that is not a workbook fails to parse, without a hang',
      () async {
    final database = AppDatabase.forTesting();
    await expectLater(
      service.parse(
        List<int>.generate(2048, (int i) => i % 251),
        database,
        sourceUnit: WeightUnit.kg,
      ),
      throwsA(anything),
    );
    await database.close();
  });
}
