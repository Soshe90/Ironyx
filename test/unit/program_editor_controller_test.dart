import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/daos/exercise_dao.dart';
import 'package:fittrack/core/database/daos/program_dao.dart';
import 'package:fittrack/core/database/database_providers.dart';
import 'package:fittrack/core/theme/app_spacing.dart';
import 'package:fittrack/features/programs/domain/program_editor_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late ProviderContainer container;

  setUp(() async {
    database = AppDatabase.forTesting();
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    final exerciseDao = ExerciseDao(database);
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
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  test('creating a program builds a day with exercises and persists it',
      () async {
    final notifier =
        container.read(programEditorControllerProvider(null).notifier);
    await container.read(programEditorControllerProvider(null).future);

    notifier.setName('Full Body');
    notifier.addDay();
    final draft = container.read(programEditorControllerProvider(null)).value!;
    final dayId = draft.days.single.id;
    notifier.renameDay(dayId, 'Workout A');
    notifier.addExercise(dayId, exerciseId: 'bench', name: 'Bench Press');
    notifier.addExercise(dayId, exerciseId: 'squat', name: 'Back Squat');

    final programId = await notifier.save();

    final dao = container.read(programDaoProvider);
    final detail = await dao.getDetail(programId);
    expect(detail, isNotNull);
    expect(detail!.program.name, 'Full Body');
    expect(detail.program.isBuiltIn, isFalse);
    expect(detail.days, hasLength(1));
    expect(detail.days.single.dayName, 'Workout A');
    expect(detail.days.single.exercises, hasLength(2));
    expect(detail.days.single.exercises.first.exerciseId, 'bench');
    expect(detail.days.single.exercises.first.targetSets, 3);
  });

  test('editing an existing program replaces its days, not appends', () async {
    // Seed a program directly at the DAO level, then load it into the
    // editor and change it.
    final dao = container.read(programDaoProvider);
    final createNotifier =
        container.read(programEditorControllerProvider(null).notifier);
    await container.read(programEditorControllerProvider(null).future);
    createNotifier.setName('Push Pull');
    createNotifier.addDay();
    final firstDayId = container
        .read(programEditorControllerProvider(null))
        .value!
        .days
        .single
        .id;
    createNotifier.addExercise(firstDayId,
        exerciseId: 'bench', name: 'Bench Press');
    final programId = await createNotifier.save();

    // Now edit it: load, rename, replace the single day with a different one.
    final editNotifier =
        container.read(programEditorControllerProvider(programId).notifier);
    final loaded =
        await container.read(programEditorControllerProvider(programId).future);
    expect(loaded.name, 'Push Pull');
    expect(loaded.days.single.exercises.single.exerciseId, 'bench');

    editNotifier.setName('Push Pull v2');
    editNotifier.removeDay(loaded.days.single.id);
    editNotifier.addDay();
    final newDayId = container
        .read(programEditorControllerProvider(programId))
        .value!
        .days
        .single
        .id;
    editNotifier.addExercise(newDayId, exerciseId: 'squat', name: 'Back Squat');
    await editNotifier.save();

    final detail = await dao.getDetail(programId);
    expect(detail!.program.name, 'Push Pull v2');
    expect(detail.days, hasLength(1));
    expect(detail.days.single.exercises.single.exerciseId, 'squat');
  });

  test('deleting a program removes it', () async {
    final createNotifier =
        container.read(programEditorControllerProvider(null).notifier);
    await container.read(programEditorControllerProvider(null).future);
    createNotifier.setName('Temp');
    createNotifier.addDay();
    final dayId = container
        .read(programEditorControllerProvider(null))
        .value!
        .days
        .single
        .id;
    createNotifier.addExercise(dayId, exerciseId: 'bench', name: 'Bench Press');
    final programId = await createNotifier.save();

    final deleteNotifier =
        container.read(programEditorControllerProvider(programId).notifier);
    await container.read(programEditorControllerProvider(programId).future);
    await deleteNotifier.delete();

    final dao = container.read(programDaoProvider);
    expect(await dao.getDetail(programId), isNull);
  });

  test('clearing target reps stores null (AMRAP), not an empty string',
      () async {
    final notifier =
        container.read(programEditorControllerProvider(null).notifier);
    await container.read(programEditorControllerProvider(null).future);
    notifier.setName('AMRAP Day');
    notifier.addDay();
    final dayId = container
        .read(programEditorControllerProvider(null))
        .value!
        .days
        .single
        .id;
    notifier.addExercise(dayId, exerciseId: 'bench', name: 'Bench Press');
    final exerciseId = container
        .read(programEditorControllerProvider(null))
        .value!
        .days
        .single
        .exercises
        .single
        .id;
    notifier.setExerciseTargetReps(dayId, exerciseId, '8-10');
    notifier.setExerciseTargetReps(dayId, exerciseId, null);

    final programId = await notifier.save();
    final dao = container.read(programDaoProvider);
    final detail = await dao.getDetail(programId);
    expect(detail!.days.single.exercises.single.targetReps, isNull);
  });

  group('auto-save', () {
    test(
        'does not write a new program until it is structurally valid, '
        'then writes it without an explicit save()', () async {
      // Autodispose: without a live subscription this provider would tear
      // itself down the moment the delays below give Riverpod's GC a free
      // async gap — exactly what `ProgramEditorPage`'s own `ref.watch`
      // otherwise prevents while the screen is open.
      container.listen(programEditorControllerProvider(null), (_, __) {});
      final notifier =
          container.read(programEditorControllerProvider(null).notifier);
      await container.read(programEditorControllerProvider(null).future);
      final dao = container.read(programDaoProvider);

      notifier.setName('Solo');
      await Future<void>.delayed(
        AppDuration.autoSaveDebounce + const Duration(milliseconds: 200),
      );
      expect(
        await dao.watchPrograms().first,
        isEmpty,
        reason: 'a name with no days is not save-worthy yet',
      );

      notifier.addDay();
      final dayId = container
          .read(programEditorControllerProvider(null))
          .value!
          .days
          .single
          .id;
      notifier.addExercise(dayId, exerciseId: 'bench', name: 'Bench Press');
      await Future<void>.delayed(
        AppDuration.autoSaveDebounce + const Duration(milliseconds: 200),
      );

      final programs = await dao.watchPrograms().first;
      expect(programs, hasLength(1));
      expect(programs.single.name, 'Solo');
    });

    test('further edits after the first auto-save update the same row',
        () async {
      container.listen(programEditorControllerProvider(null), (_, __) {});
      final notifier =
          container.read(programEditorControllerProvider(null).notifier);
      await container.read(programEditorControllerProvider(null).future);
      final dao = container.read(programDaoProvider);

      notifier.setName('Solo');
      notifier.addDay();
      final dayId = container
          .read(programEditorControllerProvider(null))
          .value!
          .days
          .single
          .id;
      notifier.addExercise(dayId, exerciseId: 'bench', name: 'Bench Press');
      await Future<void>.delayed(
        AppDuration.autoSaveDebounce + const Duration(milliseconds: 200),
      );
      final firstId = (await dao.watchPrograms().first).single.id;

      notifier.setName('Solo v2');
      await Future<void>.delayed(
        AppDuration.autoSaveDebounce + const Duration(milliseconds: 200),
      );

      final programs = await dao.watchPrograms().first;
      expect(
        programs,
        hasLength(1),
        reason: 'a second auto-save must update the row, not insert another',
      );
      expect(programs.single.id, firstId);
      expect(programs.single.name, 'Solo v2');
    });

    test('disposing the provider flushes a pending valid auto-save',
        () async {
      container.listen(programEditorControllerProvider(null), (_, __) {});
      final notifier =
          container.read(programEditorControllerProvider(null).notifier);
      await container.read(programEditorControllerProvider(null).future);

      notifier.setName('Flushed');
      notifier.addDay();
      final dayId = container
          .read(programEditorControllerProvider(null))
          .value!
          .days
          .single
          .id;
      notifier.addExercise(dayId, exerciseId: 'bench', name: 'Bench Press');

      // Dispose before the debounce would have fired on its own.
      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final freshDao = ProgramDao(database);
      final programs = await freshDao.watchPrograms().first;
      expect(programs, hasLength(1));
      expect(programs.single.name, 'Flushed');
    });
  });
}
