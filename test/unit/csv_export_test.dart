import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/services/data_export_service.dart';

/// The one-way CSV export: one row per set, opened in a spreadsheet.
void main() {
  group('csvField', () {
    test('plain text is written as it is', () {
      expect(DataExportService.csvField('Bench Press'), 'Bench Press');
      expect(DataExportService.csvField(''), '');
    });

    test('commas, quotes and line breaks are quoted', () {
      expect(DataExportService.csvField('Press, close'), '"Press, close"');
      expect(DataExportService.csvField('The "big" one'), '"The ""big"" one"');
      expect(DataExportService.csvField('two\nlines'), '"two\nlines"');
    });

    // Production review 2026-11-12, finding 10: exercise names are user
    // text, and a spreadsheet runs one that starts like a formula.
    for (final String start in <String>['=', '+', '-', '@', '\t', '\r']) {
      test('text starting with ${start.codeUnitAt(0)} is kept as text', () {
        final String field = DataExportService.csvField('${start}1+1');
        expect(field, anyOf(startsWith("'"), startsWith("\"'")));
        expect(field, contains('${start}1+1'));
      });
    }

    test('a formula with a comma is both neutralised and quoted', () {
      expect(
        DataExportService.csvField('=HYPERLINK("x","y")'),
        '"\'=HYPERLINK(""x"",""y"")"',
      );
    });

    test('a sign or symbol later in the name is left alone', () {
      expect(DataExportService.csvField('Push-up'), 'Push-up');
      expect(DataExportService.csvField('Curl @ 45°'), 'Curl @ 45°');
    });
  });

  test('the export writes a formula-like exercise name as text', () async {
    final AppDatabase db = AppDatabase.forTesting();
    addTearDown(db.close);
    await ExerciseDao(db).upsertExercises([
      ExercisesTableCompanion.insert(
        id: 'custom-1',
        slug: 'custom-1',
        name: '=1+1',
        category: 'other',
        difficulty: 'intermediate',
        movementPattern: 'other',
        seedVersion: 0,
        isCustom: const Value(true),
      ),
    ]);
    await WorkoutDao(db).insertWorkout(
      WorkoutsTableCompanion.insert(
        id: 'w1',
        startedAt: DateTime.utc(2026, 1, 1),
        endedAt: Value(DateTime.utc(2026, 1, 1, 1)),
      ),
      [
        WorkoutExercisesTableCompanion.insert(
          id: 'we1',
          workoutId: 'w1',
          exerciseId: 'custom-1',
          orderIndex: 0,
        ),
      ],
      [
        WorkoutSetsTableCompanion.insert(
          id: 's1',
          workoutExerciseId: 'we1',
          setIndex: 0,
          weightKg: 20,
          reps: 10,
          isCompleted: const Value(true),
        ),
      ],
    );

    final String csv = await const DataExportService().buildCsvExport(db);
    final List<String> lines = csv.trim().split('\n');

    expect(lines, hasLength(2));
    expect(lines[1], contains(",'=1+1,"));
    expect(
      (await ExerciseDao(db).getById('custom-1'))!.name,
      '=1+1',
      reason: 'only the export changes, not the stored name',
    );
  });
}
