import 'package:excel/excel.dart';
import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/daos/exercise_dao.dart';
import 'package:fittrack/core/formatters/unit_formatters.dart';
import 'package:fittrack/core/services/workout_xlsx_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
