import 'package:drift/drift.dart' show Value;
import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/daos/equipment_dao.dart';
import 'package:fittrack/core/database/daos/exercise_dao.dart';
import 'package:fittrack/core/database/daos/muscle_dao.dart';
import 'package:fittrack/core/database/tables/exercise_muscles.dart';
import 'package:fittrack/core/database/tables/exercises.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late ExerciseDao dao;
  late MuscleDao muscleDao;
  late EquipmentDao equipmentDao;

  setUp(() async {
    database = AppDatabase.forTesting();
    dao = ExerciseDao(database);
    muscleDao = MuscleDao(database);
    equipmentDao = EquipmentDao(database);

    await muscleDao.upsertAll([
      MusclesTableCompanion.insert(
          id: 'chest', name: 'chest', displayName: 'Chest'),
      MusclesTableCompanion.insert(
          id: 'back', name: 'back', displayName: 'Back'),
      MusclesTableCompanion.insert(
          id: 'legs', name: 'legs', displayName: 'Legs'),
    ]);
    await equipmentDao.upsertAll([
      EquipmentTableCompanion.insert(id: 'barbell', name: 'Barbell'),
      EquipmentTableCompanion.insert(id: 'bodyweight', name: 'Bodyweight'),
    ]);
  });

  tearDown(() async {
    await database.close();
  });

  /// Inserts a fully-formed exercise the way the real seeder does: the
  /// scalar row plus its muscle/equipment/instruction child rows.
  Future<void> seedExercise({
    required String id,
    required String name,
    required String primaryMuscleId,
    String? secondaryMuscleId,
    required String equipmentId,
    String movementPattern = 'horizontalPush',
    List<String> aliases = const [],
    List<String> instructions = const ['Do the movement.'],
  }) async {
    await dao.upsertExercises([
      ExercisesTableCompanion.insert(
        id: id,
        slug: id,
        name: name,
        category: 'strength',
        difficulty: 'intermediate',
        movementPattern: movementPattern,
        seedVersion: 1,
      ),
    ]);
    await dao.replaceMuscleLinks(id, [
      ExerciseMusclesTableCompanion.insert(
        id: '${id}_m_primary',
        exerciseId: id,
        muscleId: primaryMuscleId,
        role: 'primary',
      ),
      if (secondaryMuscleId != null)
        ExerciseMusclesTableCompanion.insert(
          id: '${id}_m_secondary',
          exerciseId: id,
          muscleId: secondaryMuscleId,
          role: 'secondary',
        ),
    ]);
    await dao.replaceEquipmentLinks(id, [
      ExerciseEquipmentTableCompanion.insert(
        id: '${id}_eq',
        exerciseId: id,
        equipmentId: equipmentId,
      ),
    ]);
    await dao.replaceInstructions(id, [
      for (var i = 0; i < instructions.length; i++)
        ExerciseInstructionsTableCompanion.insert(
          id: '${id}_step_$i',
          exerciseId: id,
          stepNumber: i + 1,
          instruction: instructions[i],
        ),
    ]);
    await dao.replaceAliases(id, [
      for (final alias in aliases)
        ExerciseAliasesTableCompanion.insert(
          id: '${id}_alias_$alias',
          exerciseId: id,
          alias: alias,
        ),
    ]);
  }

  group('ExerciseDao list/search/filter', () {
    test('watchAll returns exercises ordered by name with primary muscle',
        () async {
      await seedExercise(
        id: 'squat',
        name: 'Back Squat',
        primaryMuscleId: 'legs',
        equipmentId: 'barbell',
      );
      await seedExercise(
        id: 'pushup',
        name: 'Push-Up',
        primaryMuscleId: 'chest',
        equipmentId: 'bodyweight',
      );

      final all = await dao.watchAll().first;
      expect(all.map((s) => s.exercise.name), ['Back Squat', 'Push-Up']);
      expect(all.first.primaryMuscle?.displayName, 'Legs');
      expect(all.first.equipmentNames, ['Barbell']);
    });

    test('searchByName matches the name case-insensitively', () async {
      await seedExercise(
        id: 'squat',
        name: 'Back Squat',
        primaryMuscleId: 'legs',
        equipmentId: 'barbell',
      );
      await seedExercise(
        id: 'pushup',
        name: 'Push-Up',
        primaryMuscleId: 'chest',
        equipmentId: 'bodyweight',
      );

      final results = await dao.searchByName('squat').first;
      expect(results.map((s) => s.exercise.id), ['squat']);
    });

    test('searchByName also matches aliases', () async {
      await seedExercise(
        id: 'row',
        name: 'Dumbbell Incline Row',
        primaryMuscleId: 'back',
        equipmentId: 'barbell',
        aliases: ['Chest Supported Row'],
      );

      final results = await dao.searchByName('chest supported').first;
      expect(results.map((s) => s.exercise.id), ['row']);
    });

    test(
        'filterBy muscleId returns only exercises with that primary or '
        'secondary muscle', () async {
      await seedExercise(
        id: 'row',
        name: 'Dumbbell Row',
        primaryMuscleId: 'back',
        secondaryMuscleId: 'chest',
        equipmentId: 'barbell',
      );
      await seedExercise(
        id: 'squat',
        name: 'Back Squat',
        primaryMuscleId: 'legs',
        equipmentId: 'barbell',
      );

      final results = await dao.filterBy(muscleId: 'chest').first;
      expect(results.map((s) => s.exercise.id), ['row']);
    });

    test('filterBy equipmentId and movement pattern combine as AND', () async {
      await seedExercise(
        id: 'squat',
        name: 'Back Squat',
        primaryMuscleId: 'legs',
        equipmentId: 'barbell',
        movementPattern: 'kneeDominant',
      );
      await seedExercise(
        id: 'pushup',
        name: 'Push-Up',
        primaryMuscleId: 'chest',
        equipmentId: 'bodyweight',
        movementPattern: 'horizontalPush',
      );

      final results = await dao
          .filterBy(
            equipmentId: 'barbell',
            pattern: MovementPattern.kneeDominant,
          )
          .first;
      expect(results.map((s) => s.exercise.id), ['squat']);

      final noMatch = await dao
          .filterBy(
            equipmentId: 'bodyweight',
            pattern: MovementPattern.kneeDominant,
          )
          .first;
      expect(noMatch, isEmpty);
    });
  });

  group('ExerciseDao.getWithDetails', () {
    test('assembles muscles by role, equipment, and ordered instructions',
        () async {
      await seedExercise(
        id: 'row',
        name: 'Dumbbell Row',
        primaryMuscleId: 'back',
        secondaryMuscleId: 'chest',
        equipmentId: 'barbell',
        instructions: ['Hinge at hips.', 'Pull to hip.', 'Lower with control.'],
      );

      final detail = await dao.getWithDetails('row');

      expect(detail, isNotNull);
      expect(detail!.muscles, hasLength(2));
      expect(
        detail.muscles
            .firstWhere((m) => m.role == MuscleRole.primary)
            .muscle
            .id,
        'back',
      );
      expect(detail.equipment.single.equipment.id, 'barbell');
      expect(
        detail.instructions.map((i) => i.instruction),
        ['Hinge at hips.', 'Pull to hip.', 'Lower with control.'],
      );
    });

    test('returns null for an unknown id', () async {
      expect(await dao.getWithDetails('nope'), isNull);
    });
  });

  group('ExerciseDao.upsertExercises', () {
    test('updates an existing row in place rather than duplicating', () async {
      await seedExercise(
        id: 'squat',
        name: 'Back Squat',
        primaryMuscleId: 'legs',
        equipmentId: 'barbell',
      );

      await dao.upsertExercises([
        const ExercisesTableCompanion(
          id: Value('squat'),
          slug: Value('squat'),
          name: Value('Back Squat (updated)'),
          category: Value('strength'),
          difficulty: Value('intermediate'),
          movementPattern: Value('kneeDominant'),
          seedVersion: Value(2),
        ),
      ]);

      final all = await dao.watchAll().first;
      expect(all, hasLength(1));
      expect(all.single.exercise.name, 'Back Squat (updated)');
      expect(all.single.exercise.seedVersion, 2);
    });
  });
}
