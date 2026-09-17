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
}
