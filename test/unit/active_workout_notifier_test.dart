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

    test('replaceSetDetails sets, replaces and clears RPE and rest time',
        () async {
      final notifier = container.read(activeWorkoutProvider.notifier);
      await notifier.start();
      await notifier.addExercise(exerciseId: 'bench', name: 'Bench Press');
      await notifier.addSet(
        container.read(activeWorkoutProvider)!.exercises.single.id,
      );
      DraftExercise exercise() =>
          container.read(activeWorkoutProvider)!.exercises.single;
      final String exerciseId = exercise().id;
      final String first = exercise().sets[0].id;
      final String second = exercise().sets[1].id;
      await notifier.updateSet(exerciseId, first, weightKg: 100, reps: 5);

      await notifier.replaceSetDetails(
        exerciseId,
        first,
        rpeTimes10: 85,
        restSeconds: 120,
      );
      expect(exercise().sets[0].rpeTimes10, 85);
      expect(exercise().sets[0].restSeconds, 120);

      // `updateSet` cannot clear: null there means "unchanged".
      await notifier.updateSet(exerciseId, first, isCompleted: true);
      expect(exercise().sets[0].rpeTimes10, 85);

      await notifier.replaceSetDetails(
        exerciseId,
        first,
        rpeTimes10: null,
        restSeconds: 60,
      );
      expect(exercise().sets[0].rpeTimes10, isNull);
      expect(exercise().sets[0].restSeconds, 60);
      // Nothing else on the set, and no other set, is touched.
      expect(exercise().sets[0].weightKg, 100);
      expect(exercise().sets[0].reps, 5);
      expect(exercise().sets[0].isCompleted, isTrue);
      expect(exercise().sets[1].id, second);
      expect(exercise().sets[1].restSeconds, isNull);

      // An id that matches nothing changes nothing.
      final WorkoutDraft before = container.read(activeWorkoutProvider)!;
      await notifier.replaceSetDetails(
        exerciseId,
        'no-such-set',
        rpeTimes10: 70,
        restSeconds: 30,
      );
      await notifier.replaceSetDetails(
        'no-such-exercise',
        first,
        rpeTimes10: 70,
        restSeconds: 30,
      );
      expect(container.read(activeWorkoutProvider), before);

      // The cleared value is what a relaunch reads back.
      final restored = ProviderContainer(
        overrides: [
          sharedPreferencesProvider
              .overrideWithValue(await SharedPreferences.getInstance()),
        ],
      );
      addTearDown(restored.dispose);
      expect(restored.read(activeWorkoutProvider), before);
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

    Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

    test('discardWithUndo clears the draft at once, in memory and on disk',
        () async {
      final notifier = container.read(activeWorkoutProvider.notifier);
      await notifier.start();
      await notifier.addExercise(exerciseId: 'squat', name: 'Squat');

      await notifier.discardWithUndo();

      expect(container.read(activeWorkoutProvider), isNull,
          reason: 'every screen must stop showing the workout immediately');
      expect((await prefs()).getString('active_workout_draft'), isNull,
          reason: 'a kill inside the undo window must not keep the draft');
    });

    test('undoDiscard inside the window restores the same draft', () async {
      final notifier = container.read(activeWorkoutProvider.notifier);
      await notifier.start();
      await notifier.addExercise(exerciseId: 'squat', name: 'Squat');
      final before = container.read(activeWorkoutProvider)!;

      await notifier.discardWithUndo();
      expect(await notifier.undoDiscard(), isTrue);

      final after = container.read(activeWorkoutProvider)!;
      expect(after.id, before.id);
      expect(after.exercises.single.id, before.exercises.single.id);
      expect((await prefs()).getString('active_workout_draft'), isNotNull,
          reason: 'the restored draft is persisted again');

      expect(await notifier.undoDiscard(), isFalse,
          reason: 'one discard can be undone once');
    });

    test('undoDiscard never replaces a workout started since', () async {
      final notifier = container.read(activeWorkoutProvider.notifier);
      await notifier.start();
      await notifier.discardWithUndo();
      await notifier.start();
      final fresh = container.read(activeWorkoutProvider)!;

      expect(await notifier.undoDiscard(), isFalse);
      expect(container.read(activeWorkoutProvider)!.id, fresh.id);
    });

    test('undoDiscard with nothing discarded does nothing', () async {
      final notifier = container.read(activeWorkoutProvider.notifier);
      expect(await notifier.undoDiscard(), isFalse);
      expect(container.read(activeWorkoutProvider), isNull);
    });

    test('a plain discard closes any open undo window', () async {
      final notifier = container.read(activeWorkoutProvider.notifier);
      await notifier.start();
      await notifier.discardWithUndo();
      await notifier.discard();
      expect(await notifier.undoDiscard(), isFalse);
    });

    test(
      'undoDiscard after the window has closed does nothing',
      () async {
        final notifier = container.read(activeWorkoutProvider.notifier);
        await notifier.start();
        await notifier.discardWithUndo();
        await Future<void>.delayed(
          AppDuration.undoWindow + const Duration(seconds: 1),
        );

        expect(await notifier.undoDiscard(), isFalse,
            reason: 'a stale Undo must not resurrect the workout');
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
