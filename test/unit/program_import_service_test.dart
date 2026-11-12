import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/program_dao.dart';
import 'package:ironyx/core/services/program_import_service.dart';

void main() {
  late AppDatabase database;
  late ExerciseDao exerciseDao;
  late ProgramDao programDao;
  const service = ProgramImportService();

  setUp(() async {
    database = AppDatabase.forTesting();
    exerciseDao = ExerciseDao(database);
    programDao = ProgramDao(database);
    await exerciseDao.upsertExercises([
      ExercisesTableCompanion.insert(
        id: 'squat',
        slug: 'squat',
        name: 'Back Squat',
        category: 'strength',
        difficulty: 'intermediate',
        movementPattern: 'kneeDominant',
        isBodyweight: const Value(false),
        seedVersion: 1,
      ),
      ExercisesTableCompanion.insert(
        id: 'bench',
        slug: 'bench',
        name: 'Barbell Bench Press',
        category: 'strength',
        difficulty: 'intermediate',
        movementPattern: 'horizontalPush',
        isBodyweight: const Value(false),
        seedVersion: 1,
      ),
    ]);
  });

  tearDown(() async {
    await database.close();
  });

  test('parses a CSV into programs, days, and exercises', () async {
    const csv = 'program,day,exercise,sets,reps\n'
        'Full Body,Workout A,Back Squat,3,6-8\n'
        'Full Body,Workout A,Barbell Bench Press,3,8-10\n'
        'Full Body,Workout B,Back Squat,4,5\n';

    final result = await service.parse(csv, database);

    expect(result.programs, hasLength(1));
    expect(result.programs.single.name, 'Full Body');
    expect(result.programs.single.days, hasLength(2));
    expect(result.programs.single.days[0].exercises, hasLength(2));
    expect(result.programs.single.days[0].exercises.first.exerciseId, 'squat');
    expect(result.totalDays, 2);
    expect(result.totalExercises, 3);
    expect(result.unknownExercises, isEmpty);
  });

  test('reports unknown exercise names and excludes them', () async {
    const csv = 'program,day,exercise,sets,reps\n'
        'Full Body,Workout A,Back Squat,3,6-8\n'
        'Full Body,Workout A,Not A Real Exercise,3,8\n';

    final result = await service.parse(csv, database);

    expect(result.unknownExercises, ['Not A Real Exercise']);
    expect(result.programs.single.days.single.exercises, hasLength(1));
  });

  test('throws when required columns are missing', () async {
    const csv = 'name,day,exercise,sets,reps\n'
        'Full Body,Workout A,Back Squat,3,6-8\n';

    expect(
      () => service.parse(csv, database),
      throwsA(isA<ProgramImportException>()),
    );
  });

  test('a CSV over 1 MB is refused before it is split into rows', () async {
    // Production review 2026-11-12, finding 7: any size was read and split
    // on the UI isolate.
    final String huge = 'program,day,exercise\n${'x' * kMaxProgramCsvBytes}';

    await expectLater(
      service.parse(huge, database),
      throwsA(isA<ProgramCsvTooLargeException>()),
    );
  });

  test('a large CSV under the limit is split on another isolate and read',
      () async {
    // Over the 64 KB threshold: this one goes through `compute`.
    final StringBuffer csv = StringBuffer('program,day,exercise,sets\n');
    for (int i = 0; i < 3000; i++) {
      csv.writeln('Big Block,Day ${i % 7},Back Squat,3');
    }
    expect(csv.length, greaterThan(64 * 1024));

    final result = await service.parse(csv.toString(), database);

    expect(result.programs.single.name, 'Big Block');
    expect(result.programs.single.days, hasLength(7));
  });

  test('the split handles quotes, commas, CRLF and the byte-order mark', () {
    expect(
      parseProgramCsv('\uFEFFprogram,day\r\n"A, ""b""",Day 1\r\n'),
      <List<String>>[
        <String>['program', 'day'],
        <String>['A, "b"', 'Day 1'],
      ],
    );
  });

  test('apply inserts parsed programs into the database', () async {
    const csv = 'program,day,exercise,sets,reps\n'
        'Full Body,Workout A,Back Squat,3,6-8\n'
        'Full Body,Workout A,Barbell Bench Press,3,8-10\n';

    final result = await service.parse(csv, database);
    await service.apply(database, result);

    final summaries = await programDao.watchAll().first;
    expect(summaries, hasLength(1));
    expect(summaries.single.program.name, 'Full Body');
    expect(summaries.single.dayCount, 1);

    final detail = await programDao.getDetail(summaries.single.program.id);
    expect(detail!.days.single.exercises, hasLength(2));
  });

  test(
      'apply rolls back every program in the batch when one exercise '
      'reference is invalid', () async {
    // Built directly rather than through parse(), which only ever resolves
    // exerciseIds that exist in the catalogue — this simulates a corrupted
    // ProgramImportResult reaching apply() with a dangling reference.
    const result = ProgramImportResult(
      programs: [
        ImportedProgram(
          name: 'Valid Program',
          days: [
            ImportedDay(
              dayName: 'Day 1',
              exercises: [
                ImportedExercise(
                  exerciseId: 'squat',
                  exerciseName: 'Back Squat',
                  sets: 3,
                ),
              ],
            ),
          ],
        ),
        ImportedProgram(
          name: 'Broken Program',
          days: [
            ImportedDay(
              dayName: 'Day 1',
              exercises: [
                ImportedExercise(
                  exerciseId: 'does-not-exist',
                  exerciseName: 'Ghost Exercise',
                  sets: 3,
                ),
              ],
            ),
          ],
        ),
      ],
      unknownExercises: [],
      totalDays: 2,
      totalExercises: 2,
    );

    await expectLater(service.apply(database, result), throwsException);

    // apply() runs in one transaction: the first (valid) program must not
    // survive when the second one fails.
    final summaries = await programDao.watchAll().first;
    expect(summaries, isEmpty);
  });

  group('row validation', () {
    test('reports rows with an empty required cell by spreadsheet row',
        () async {
      // Row 1 is the header; the blank line (row 3) is ignored, not reported.
      const csv = 'program,day,exercise,sets,reps\n'
          'Full Body,Workout A,Back Squat,3,5\n'
          '\n'
          ',Workout A,Back Squat,3,5\n'
          'Full Body,,Back Squat,3,5\n'
          'Full Body,Workout A,"  ",3,5\n';

      final result = await service.parse(csv, database);

      expect(
        [for (final issue in result.rejectedRows) issue.rowNumber],
        [4, 5, 6],
      );
      expect(
        result.rejectedRows.map((issue) => issue.problem).toSet(),
        {ProgramImportRowProblem.missingField},
      );
      expect(result.totalExercises, 1);
    });

    test('rejects an unusable sets value instead of guessing 1', () async {
      const csv = 'program,day,exercise,sets,reps\n'
          'P,D,Back Squat,three,5\n' // row 2
          'P,D,Back Squat,0,5\n' // row 3
          'P,D,Back Squat,-1,5\n' // row 4
          'P,D,Back Squat,2.5,5\n' // row 5
          'P,D,Back Squat,21,5\n' // row 6
          'P,D,Back Squat,20,5\n' // accepted: the limit itself
          'P,D,Barbell Bench Press,,8\n'; // accepted: blank means 1

      final result = await service.parse(csv, database);

      expect(
        [for (final issue in result.rejectedRows) issue.rowNumber],
        [2, 3, 4, 5, 6],
      );
      expect(
        result.rejectedRows.map((issue) => issue.problem).toSet(),
        {ProgramImportRowProblem.invalidSets},
      );
      final exercises = result.programs.single.days.single.exercises;
      expect([for (final e in exercises) e.sets], [20, 1]);
    });

    test('a file without a sets column defaults every row to 1', () async {
      const csv = 'program,day,exercise\nP,D,Back Squat\n';

      final result = await service.parse(csv, database);

      expect(result.rejectedRows, isEmpty);
      expect(result.programs.single.days.single.exercises.single.sets, 1);
    });

    test('an empty file is refused like a missing header', () async {
      expect(
        () => service.parse('', database),
        throwsA(isA<ProgramImportException>()),
      );
    });

    test('a header-only file parses to nothing, with nothing reported',
        () async {
      final result =
          await service.parse('program,day,exercise,sets,reps\n', database);

      expect(result.programs, isEmpty);
      expect(result.rejectedRows, isEmpty);
      expect(result.unknownExercises, isEmpty);
    });

    test('reads a file saved as Excel "CSV UTF-8", which starts with a BOM',
        () async {
      const csv = '﻿program,day,exercise,sets,reps\r\n'
          'Full Body,Workout A,Back Squat,3,5\r\n';

      final result = await service.parse(csv, database);

      expect(result.programs.single.name, 'Full Body');
    });
  });

  group('name collisions', () {
    test(
        'a program whose name is already taken is skipped and reported, '
        'and the rest of the file still imports', () async {
      await service.apply(
        database,
        await service.parse(
          'program,day,exercise,sets\nFull Body,A,Back Squat,3\n',
          database,
        ),
      );

      const csv = 'program,day,exercise,sets\n'
          'Full Body,A,Barbell Bench Press,3\n'
          'Full Body,B,Back Squat,3\n'
          'Upper Lower,Upper,Barbell Bench Press,3\n';
      final result = await service.parse(csv, database);

      expect(result.existingPrograms, ['Full Body']);
      expect(result.programs.map((p) => p.name), ['Upper Lower']);
      expect(result.totalExercises, 1);

      // Used to fail the whole transaction on the UNIQUE program name.
      await service.apply(database, result);
      final names = (await programDao.watchAll().first)
          .map((s) => s.program.name)
          .toSet();
      expect(names, {'Full Body', 'Upper Lower'});
    });

    test('re-importing a file after deleting its program succeeds', () async {
      const csv = 'program,day,exercise,sets\nMine,Day 1,Back Squat,3\n';
      await service.apply(database, await service.parse(csv, database));
      final first = (await programDao.watchAll().first).single;

      // Deleting a program leaves its templates behind; their old
      // "<program> <day>" names used to collide with the second import.
      await programDao.deleteProgram(first.program.id);
      await service.apply(database, await service.parse(csv, database));

      final summaries = await programDao.watchAll().first;
      expect(summaries.single.program.name, 'Mine');
      expect(summaries.single.dayCount, 1);
    });

    test('programs and days whose names join the same way both import',
        () async {
      // "A B" + "C" and "A" + "B C" both made the template name "A B C".
      const csv = 'program,day,exercise,sets\n'
          'A B,C,Back Squat,3\n'
          'A,B C,Barbell Bench Press,3\n';

      await service.apply(database, await service.parse(csv, database));

      expect(await programDao.watchAll().first, hasLength(2));
    });
  });
}
