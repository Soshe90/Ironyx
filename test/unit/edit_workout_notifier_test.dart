import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/theme/app_spacing.dart';
import 'package:ironyx/features/tracker/domain/edit_workout_notifier.dart';

void main() {
  group('EditWorkoutNotifier auto-save', () {
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
          id: 'squat',
          slug: 'squat',
          name: 'Back Squat',
          category: 'strength',
          difficulty: 'intermediate',
          movementPattern: 'kneeDominant',
          seedVersion: 1,
        ),
      ]);
      final workoutDao = WorkoutDao(database);
      await workoutDao.insertWorkout(
        WorkoutsTableCompanion.insert(
          id: 'w1',
          startedAt: DateTime.utc(2026, 1, 1),
        ),
        [
          WorkoutExercisesTableCompanion.insert(
            id: 'w1_ex1',
            workoutId: 'w1',
            exerciseId: 'squat',
            orderIndex: 0,
          ),
        ],
        [
          WorkoutSetsTableCompanion.insert(
            id: 'w1_ex1_set1',
            workoutExerciseId: 'w1_ex1',
            setIndex: 0,
            weightKg: 60,
            reps: 5,
          ),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      database.close();
    });

    test('writes the edit to the database on a debounce without save()',
        () async {
      // Autodispose: without a live subscription this provider would tear
      // itself down the moment the delay below gives Riverpod's GC a free
      // async gap — exactly what `WorkoutEditPage`'s own `ref.watch`
      // otherwise prevents while the screen is open.
      container.listen(editWorkoutProvider('w1'), (_, __) {});
      final notifier = container.read(editWorkoutProvider('w1').notifier);
      await container.read(editWorkoutProvider('w1').future);

      final setId = container
          .read(editWorkoutProvider('w1'))
          .value!
          .exercises
          .single
          .sets
          .single
          .id;
      await notifier.updateSet('w1_ex1', setId, weightKg: 100, reps: 3);

      // Not written yet: the debounce hasn't elapsed.
      final dao = container.read(workoutDaoProvider);
      var onDisk = await dao.getWithDetails('w1');
      expect(onDisk!.setsByExercise['w1_ex1']!.single.weightKg, 60);

      await Future<void>.delayed(
        AppDuration.autoSaveDebounce + const Duration(milliseconds: 200),
      );

      onDisk = await dao.getWithDetails('w1');
      expect(onDisk!.setsByExercise['w1_ex1']!.single.weightKg, 100);
      expect(onDisk.setsByExercise['w1_ex1']!.single.reps, 3);
    });

    test('disposing the provider flushes a pending auto-save immediately',
        () async {
      container.listen(editWorkoutProvider('w1'), (_, __) {});
      final notifier = container.read(editWorkoutProvider('w1').notifier);
      await container.read(editWorkoutProvider('w1').future);

      final setId = container
          .read(editWorkoutProvider('w1'))
          .value!
          .exercises
          .single
          .sets
          .single
          .id;
      await notifier.updateSet('w1_ex1', setId, weightKg: 80, reps: 8);

      // Dispose before the debounce would have fired on its own.
      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final dao = WorkoutDao(database);
      final onDisk = await dao.getWithDetails('w1');
      expect(onDisk!.setsByExercise['w1_ex1']!.single.weightKg, 80);
    });

    test('save() writes immediately, bypassing the debounce', () async {
      container.listen(editWorkoutProvider('w1'), (_, __) {});
      final notifier = container.read(editWorkoutProvider('w1').notifier);
      await container.read(editWorkoutProvider('w1').future);

      final setId = container
          .read(editWorkoutProvider('w1'))
          .value!
          .exercises
          .single
          .sets
          .single
          .id;
      await notifier.updateSet('w1_ex1', setId, weightKg: 42, reps: 10);
      await notifier.save();

      final dao = container.read(workoutDaoProvider);
      final onDisk = await dao.getWithDetails('w1');
      expect(onDisk!.setsByExercise['w1_ex1']!.single.weightKg, 42);
    });
  });
}
