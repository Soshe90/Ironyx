import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/daos/exercise_dao.dart';
import 'package:fittrack/core/database/daos/program_dao.dart';
import 'package:fittrack/core/services/data_export_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

void main() {
  const uuid = Uuid();

  late AppDatabase database;
  late ProgramDao programDao;
  late ExerciseDao exerciseDao;

  setUp(() async {
    database = AppDatabase.forTesting();
    programDao = ProgramDao(database);
    exerciseDao = ExerciseDao(database);
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

  ProgramsTableCompanion programCompanion({
    required String id,
    String name = 'Full Body',
    bool isBuiltIn = false,
  }) {
    final now = DateTime.now().toUtc();
    return ProgramsTableCompanion.insert(
      id: id,
      name: name,
      description: const Value('3 days/week'),
      splitType: const Value('fullBody'),
      createdAt: now,
      updatedAt: now,
      isBuiltIn: Value(isBuiltIn),
    );
  }

  List<ProgramDayInsert> twoDays(String programId) {
    final now = DateTime.now().toUtc();
    return [
      ProgramDayInsert(
        id: '${programId}_day_0',
        dayName: 'Workout A',
        orderIndex: 0,
        template: TemplatesTableCompanion.insert(
          id: '${programId}_tpl_a',
          name: '${programId}_A',
          createdAt: now,
          updatedAt: now,
        ),
        exercises: [
          TemplateExercisesTableCompanion.insert(
            id: uuid.v4(),
            templateId: '${programId}_tpl_a',
            exerciseId: 'squat',
            orderIndex: 0,
            targetSets: 3,
            targetReps: const Value('6-8'),
          ),
        ],
      ),
      ProgramDayInsert(
        id: '${programId}_day_1',
        dayName: 'Workout B',
        orderIndex: 1,
        template: TemplatesTableCompanion.insert(
          id: '${programId}_tpl_b',
          name: '${programId}_B',
          createdAt: now,
          updatedAt: now,
        ),
        exercises: [
          TemplateExercisesTableCompanion.insert(
            id: uuid.v4(),
            templateId: '${programId}_tpl_b',
            exerciseId: 'bench',
            orderIndex: 0,
            targetSets: 3,
            targetReps: const Value('8-10'),
          ),
        ],
      ),
    ];
  }

  test('insertProgram and getDetail round-trips days and exercises', () async {
    await programDao.insertProgram(
      programCompanion(id: 'p1'),
      twoDays('p1'),
    );

    final detail = await programDao.getDetail('p1');
    expect(detail, isNotNull);
    expect(detail!.program.name, 'Full Body');
    expect(detail.days, hasLength(2));
    expect(detail.days[0].dayName, 'Workout A');
    expect(detail.days[0].exercises.single.exerciseName, 'Back Squat');
    expect(detail.days[0].exercises.single.targetReps, '6-8');
    expect(detail.days[1].exercises.single.exerciseName, 'Barbell Bench Press');
  });

  test('watchAll reports day count per program', () async {
    await programDao.insertProgram(
      programCompanion(id: 'p1', name: 'Alpha'),
      twoDays('p1'),
    );

    final summaries = await programDao.watchAll().first;
    expect(summaries, hasLength(1));
    expect(summaries.single.program.name, 'Alpha');
    expect(summaries.single.dayCount, 2);
  });

  test('deleteBuiltInPrograms removes only built-in programs', () async {
    await programDao.insertProgram(
      programCompanion(id: 'builtin', name: 'Built-in', isBuiltIn: true),
      twoDays('builtin'),
    );
    await programDao.insertProgram(
      programCompanion(id: 'user', name: 'My Program', isBuiltIn: false),
      twoDays('user'),
    );

    await programDao.deleteBuiltInPrograms();

    expect(await programDao.getDetail('builtin'), isNull);
    expect(await programDao.getDetail('user'), isNotNull);
  });

  test(
      'updateProgramWithDays renames the program and replaces its days '
      'entirely (old templates are gone, not just unlinked)', () async {
    await programDao.insertProgram(
      programCompanion(id: 'p1', name: 'Original'),
      twoDays('p1'),
    );
    final original = await programDao.getDetail('p1');
    final oldTemplateIds = original!.days.map((d) => d.templateId).toSet();

    await programDao.updateProgramWithDays(
      'p1',
      name: 'Renamed',
      description: 'New description',
      splitType: null,
      days: [
        ProgramDayInsert(
          id: 'p1_new_day',
          dayName: 'Solo Day',
          orderIndex: 0,
          template: TemplatesTableCompanion.insert(
            id: 'p1_new_tpl',
            name: 'p1_new_tpl_name',
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
          exercises: [
            TemplateExercisesTableCompanion.insert(
              id: uuid.v4(),
              templateId: 'p1_new_tpl',
              exerciseId: 'squat',
              orderIndex: 0,
              targetSets: 5,
              targetReps: const Value('5'),
            ),
          ],
        ),
      ],
    );

    final updated = await programDao.getDetail('p1');
    expect(updated!.program.name, 'Renamed');
    expect(updated.program.description, 'New description');
    expect(updated.days, hasLength(1));
    expect(updated.days.single.dayName, 'Solo Day');
    expect(updated.days.single.exercises.single.exerciseId, 'squat');
    expect(updated.days.single.exercises.single.targetSets, 5);

    // The old day-templates must be gone entirely, not merely unlinked —
    // otherwise they'd leak as orphaned rows forever.
    for (final oldId in oldTemplateIds) {
      final stillExists = await (database.select(database.templatesTable)
            ..where((t) => t.id.equals(oldId)))
          .getSingleOrNull();
      expect(stillExists, isNull);
    }
  });

  test(
      'editing a built-in program converts it to custom so re-seeding '
      'cannot discard the edit', () async {
    await programDao.insertProgram(
      programCompanion(id: 'builtin_full_body', isBuiltIn: true),
      twoDays('builtin_full_body'),
    );

    // Keep the program name — only the day changes, which is what a user
    // tweaking "Full Body / Workout A" actually does.
    await programDao.updateProgramWithDays(
      'builtin_full_body',
      name: 'Full Body',
      description: '3 days/week',
      splitType: 'fullBody',
      days: [
        ProgramDayInsert(
          id: 'edited_day',
          dayName: 'Workout A',
          orderIndex: 0,
          template: TemplatesTableCompanion.insert(
            id: 'edited_tpl',
            name: 'edited_tpl',
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
          exercises: [
            TemplateExercisesTableCompanion.insert(
              id: uuid.v4(),
              templateId: 'edited_tpl',
              exerciseId: 'bench',
              orderIndex: 0,
              targetSets: 5,
            ),
          ],
        ),
      ],
    );

    final edited = await programDao.getDetail('builtin_full_body');
    expect(edited!.program.isBuiltIn, isFalse);
    expect(edited.days.single.exercises.single.targetSets, 5);

    // The event that used to wipe user edits to a built-in.
    await programDao.deleteBuiltInPrograms();

    final survived = await programDao.getDetail('builtin_full_body');
    expect(survived, isNotNull);
    expect(survived!.days.single.exercises.single.targetSets, 5);
  });

  test('allProgramNames reports every stored program name', () async {
    await programDao.insertProgram(
      programCompanion(id: 'p1', name: 'Full Body'),
      twoDays('p1'),
    );
    await programDao.insertProgram(
      programCompanion(id: 'p2', name: 'My Split'),
      twoDays('p2'),
    );

    expect(await programDao.allProgramNames(), {'Full Body', 'My Split'});
  });

  test(
      'deleteAllUserData removes programs rather than leaving them as '
      'empty shells', () async {
    await programDao.insertProgram(
      programCompanion(id: 'builtin', name: 'Built-in', isBuiltIn: true),
      twoDays('builtin'),
    );
    await programDao.insertProgram(
      programCompanion(id: 'user', name: 'My Program', isBuiltIn: false),
      twoDays('user'),
    );

    await const DataExportService().deleteAllUserData(database);

    // Both programs must be gone entirely, not left behind with their
    // templates wiped out from under them.
    expect(await programDao.getDetail('builtin'), isNull);
    expect(await programDao.getDetail('user'), isNull);
    expect(await programDao.watchPrograms().first, isEmpty);
  });
}
