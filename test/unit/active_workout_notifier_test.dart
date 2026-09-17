import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/core/theme/app_spacing.dart';
import 'package:ironyx/features/tracker/domain/active_workout_notifier.dart';
import 'package:ironyx/features/tracker/domain/workout_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ActiveWorkoutNotifier', () {
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
    });

    tearDown(() => container.dispose());

    test('mutates nested entities by UUID without shifting values', () async {
      final notifier = container.read(activeWorkoutProvider.notifier);
      await notifier.start();
      await notifier.addExercise(exerciseId: 'squat', name: 'Squat');
      await notifier.addExercise(exerciseId: 'press', name: 'Press');

      var draft = container.read(activeWorkoutProvider)!;
      final squatId = draft.exercises.first.id;
      final pressId = draft.exercises.last.id;
      final squatSetId = draft.exercises.first.sets.first.id;

      await notifier.addSet(squatId);
      await notifier.updateSet(squatId, squatSetId, weightKg: 100, reps: 5);
      await notifier.removeExercise(pressId);

      draft = container.read(activeWorkoutProvider)!;
      expect(draft.exercises, hasLength(1));
      expect(draft.exercises.single.id, squatId);
      expect(draft.exercises.single.sets.first.id, squatSetId);
      expect(draft.exercises.single.sets.first.weightKg, 100);
      expect(draft.exercises.single.sets.first.reps, 5);
    });

    test('reorders exercises by stable ID and persists the new order',
        () async {
      final notifier = container.read(activeWorkoutProvider.notifier);
      await notifier.start();
      await notifier.addExercise(exerciseId: 'squat', name: 'Squat');
      await notifier.addExercise(exerciseId: 'press', name: 'Press');
      await notifier.addExercise(exerciseId: 'row', name: 'Row');

      var draft = container.read(activeWorkoutProvider)!;
      final firstId = draft.exercises[0].id;
      final middleId = draft.exercises[1].id;
      final lastId = draft.exercises[2].id;
      await notifier.reorderExercise(firstId, 2);

      draft = container.read(activeWorkoutProvider)!;
      expect(
        draft.exercises.map((exercise) => exercise.id),
        [middleId, lastId, firstId],
      );
      expect(draft.exercises.last.id, firstId);

      final restored = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(restored.dispose);
      expect(restored.read(activeWorkoutProvider)!.exercises.last.id, firstId);
    });

    test('deleting a middle set does not corrupt neighbouring sets', () async {
      final notifier = container.read(activeWorkoutProvider.notifier);
      await notifier.start();
      await notifier.addExercise(exerciseId: 'squat', name: 'Squat');
      final exerciseId =
          container.read(activeWorkoutProvider)!.exercises.single.id;

      // 1 set already exists from addExercise; add 3 more (4 total) and
      // give each a distinct weight so corruption is easy to detect.
      for (var i = 0; i < 3; i++) {
        await notifier.addSet(exerciseId);
      }
      var sets = container.read(activeWorkoutProvider)!.exercises.single.sets;
      expect(sets, hasLength(4));
      for (var i = 0; i < sets.length; i++) {
        await notifier.updateSet(exerciseId, sets[i].id, weightKg: 10.0 * i);
      }

      sets = container.read(activeWorkoutProvider)!.exercises.single.sets;
      final ids = sets.map((s) => s.id).toList();
      final middleId = ids[1];
      await notifier.removeSet(exerciseId, middleId);

      sets = container.read(activeWorkoutProvider)!.exercises.single.sets;
      expect(sets, hasLength(3));
      expect(sets.map((s) => s.id), [ids[0], ids[2], ids[3]]);
      expect(sets.map((s) => s.weightKg), [0.0, 20.0, 30.0]);
    });

    test('scheduleDiscard keeps the draft until the undo window elapses',
        () async {
      final notifier = container.read(activeWorkoutProvider.notifier);
      await notifier.start();
      await notifier.addExercise(exerciseId: 'squat', name: 'Squat');

      notifier.scheduleDiscard();
      expect(container.read(activeWorkoutProvider), isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        container.read(activeWorkoutProvider),
        isNotNull,
        reason: 'draft must survive until the undo window elapses',
      );

      notifier.cancelScheduledDiscard();
      await Future<void>.delayed(
        AppDuration.undoWindow + const Duration(seconds: 1),
      );
      expect(
        container.read(activeWorkoutProvider),
        isNotNull,
        reason: 'cancelScheduledDiscard must prevent the eventual discard',
      );
    });

    test(
      'scheduleDiscard clears the draft once the window elapses',
      () async {
        final notifier = container.read(activeWorkoutProvider.notifier);
        await notifier.start();

        notifier.scheduleDiscard();
        await Future<void>.delayed(
          AppDuration.undoWindow + const Duration(seconds: 1),
        );

        expect(container.read(activeWorkoutProvider), isNull);
      },
      // Must exceed the undo window plus the buffer above.
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('persists and restores a draft', () async {
      final prefs = await SharedPreferences.getInstance();
      final first = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      final firstNotifier = first.read(activeWorkoutProvider.notifier);
      await firstNotifier.start();
      await firstNotifier.addExercise(exerciseId: 'bench', name: 'Bench Press');
      final id = first.read(activeWorkoutProvider)!.id;
      first.dispose();

      final restored = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      expect(restored.read(activeWorkoutProvider)!.id, id);
      expect(
        restored.read(activeWorkoutProvider)!.exercises.single.name,
        'Bench Press',
      );
      restored.dispose();
    });

    test(
        'concurrent unawaited mutations converge to a persisted state '
        'matching the final in-memory draft', () async {
      final notifier = container.read(activeWorkoutProvider.notifier);
      await notifier.start();
      await notifier.addExercise(exerciseId: 'squat', name: 'Squat');
      final exerciseId =
          container.read(activeWorkoutProvider)!.exercises.single.id;
      final setId = container
          .read(activeWorkoutProvider)!
          .exercises
          .single
          .sets
          .single
          .id;

      // Fire a burst of mutations without awaiting each one individually —
      // e.g. two debounced row edits landing back to back. Every call
      // queues a write of *whatever `state` is when that write actually
      // runs*, so even though these persists overlap, the one that runs
      // last must always reflect the truly final state.
      final futures = <Future<void>>[];
      for (var weight = 1; weight <= 10; weight++) {
        futures.add(
          notifier.updateSet(exerciseId, setId, weightKg: weight.toDouble()),
        );
      }
      await Future.wait(futures);

      final finalWeight = container
          .read(activeWorkoutProvider)!
          .exercises
          .single
          .sets
          .single
          .weightKg;
      expect(finalWeight, 10.0);

      final restored = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(restored.dispose);
      expect(
        restored
            .read(activeWorkoutProvider)!
            .exercises
            .single
            .sets
            .single
            .weightKg,
        finalWeight,
        reason: 'the persisted draft must match the final in-memory state, '
            'not an earlier write that happened to complete last',
      );
    });

    test('a discard racing an in-flight edit is never resurrected', () async {
      final notifier = container.read(activeWorkoutProvider.notifier);
      await notifier.start();
      await notifier.addExercise(exerciseId: 'squat', name: 'Squat');
      final exerciseId =
          container.read(activeWorkoutProvider)!.exercises.single.id;
      final setId = container
          .read(activeWorkoutProvider)!
          .exercises
          .single
          .sets
          .single
          .id;

      // An edit's write is still in flight when discard fires — discard's
      // null write must be the one that lands last, not the edit's.
      final editFuture = notifier.updateSet(exerciseId, setId, weightKg: 42);
      final discardFuture = notifier.discard();
      await Future.wait([editFuture, discardFuture]);

      expect(container.read(activeWorkoutProvider), isNull);

      final restored = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(restored.dispose);
      expect(
        restored.read(activeWorkoutProvider),
        isNull,
        reason: 'a discarded draft must not reappear from a stale edit write',
      );
    });

    test('startFromTemplate preloads exercises with empty set rows', () async {
      final notifier = container.read(activeWorkoutProvider.notifier);
      await notifier.startFromTemplate(const [
        TemplateExerciseInput(
            exerciseId: 'squat', name: 'Back Squat', targetSets: 3),
        TemplateExerciseInput(
            exerciseId: 'bench', name: 'Bench Press', targetSets: 2),
      ]);

      final draft = container.read(activeWorkoutProvider)!;
      expect(draft.exercises, hasLength(2));
      expect(draft.exercises[0].name, 'Back Squat');
      expect(draft.exercises[0].sets, hasLength(3));
      expect(draft.exercises[1].sets, hasLength(2));
    });

    test('startFromTemplate carries superset groups into the draft', () async {
      final notifier = container.read(activeWorkoutProvider.notifier);
      await notifier.startFromTemplate(const [
        TemplateExerciseInput(
          exerciseId: 'squat',
          name: 'Back Squat',
          targetSets: 3,
          supersetGroupId: 'g1',
        ),
        TemplateExerciseInput(
          exerciseId: 'bench',
          name: 'Bench Press',
          targetSets: 3,
          supersetGroupId: 'g1',
        ),
      ]);

      final draft = container.read(activeWorkoutProvider)!;
      expect(draft.exercises[0].supersetGroupId, 'g1');
      expect(draft.exercises[1].supersetGroupId, 'g1');
    });

    test('grouping and ungrouping exercises persists across restore', () async {
      final notifier = container.read(activeWorkoutProvider.notifier);
      await notifier.start();
      await notifier.addExercise(exerciseId: 'squat', name: 'Squat');
      await notifier.addExercise(exerciseId: 'press', name: 'Press');
      final exercises = container.read(activeWorkoutProvider)!.exercises;

      await notifier.groupWithPrevious(exercises[1].id);
      var draft = container.read(activeWorkoutProvider)!;
      final groupId = draft.exercises[0].supersetGroupId;
      expect(groupId, isNotNull);
      expect(draft.exercises[1].supersetGroupId, groupId);

      final restored = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(restored.dispose);
      expect(
        restored.read(activeWorkoutProvider)!.exercises[0].supersetGroupId,
        groupId,
      );
      expect(
        restored.read(activeWorkoutProvider)!.exercises[1].supersetGroupId,
        groupId,
      );

      await notifier.ungroupFromSuperset(exercises[1].id);
      draft = container.read(activeWorkoutProvider)!;
      expect(draft.exercises[0].supersetGroupId, isNull);
      expect(draft.exercises[1].supersetGroupId, isNull);
    });
  });
}
