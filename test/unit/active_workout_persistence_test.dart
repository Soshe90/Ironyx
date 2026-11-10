import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/features/tracker/domain/active_workout_notifier.dart';
import 'package:ironyx/features/tracker/domain/workout_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The preferences key [ActiveWorkoutNotifier] stores its draft under.
///
/// Duplicated rather than exposed: these tests pin the on-disk contract, and a
/// silent rename of the key would strand every in-progress workout on update.
const String _draftKey = 'active_workout_draft';

/// Persistence, recovery and save-failure behaviour of the workout draft.
///
/// `active_workout_notifier_test.dart` covers in-memory editing. This file
/// covers what happens at the edges of the process: what a relaunch reads
/// back, what a damaged preferences file does to launch, and what a failed
/// save leaves behind.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting();
  });

  tearDown(() => db.close());

  Future<ProviderContainer> containerWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final SharedPreferences instance = await SharedPreferences.getInstance();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(instance),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// A new container over the same preferences: what the app sees after
  /// being killed and relaunched.
  Future<ProviderContainer> relaunch() async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider
            .overrideWithValue(await SharedPreferences.getInstance()),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> insertExercise(String id) => db.into(db.exercisesTable).insert(
        ExercisesTableCompanion.insert(
          id: id,
          slug: id,
          name: id,
          category: 'strength',
          difficulty: 'intermediate',
          movementPattern: 'other',
          seedVersion: 1,
        ),
      );

  group('reading a stored draft on launch', () {
    test('no stored draft means no workout in progress', () async {
      final ProviderContainer container = await containerWith({});
      expect(container.read(activeWorkoutProvider), isNull);
    });

    // Each of these is a draft the app could plausibly find on disk after a
    // crash mid-write, a downgrade, or a hand-edited backup of preferences.
    // None may stop the app from launching.
    final Map<String, String> damaged = <String, String>{
      'empty string': '',
      'not JSON': 'this is not json',
      'truncated JSON': '{"id":"d1","startedAt":"2026-09-01T10:00:00.000Z",',
      'a JSON list instead of an object': '[1, 2, 3]',
      'a JSON string instead of an object': '"draft"',
      'JSON null': 'null',
      'missing id': jsonEncode(<String, Object>{
        'startedAt': '2026-09-01T10:00:00.000Z',
        'exercises': <Object>[],
      }),
      'unparseable startedAt': jsonEncode(<String, Object>{
        'id': 'd1',
        'startedAt': 'yesterday-ish',
        'exercises': <Object>[],
      }),
      'exercises is not a list': jsonEncode(<String, Object>{
        'id': 'd1',
        'startedAt': '2026-09-01T10:00:00.000Z',
        'exercises': 'bench',
      }),
      'a set with a string for reps': jsonEncode(<String, Object>{
        'id': 'd1',
        'startedAt': '2026-09-01T10:00:00.000Z',
        'exercises': <Object>[
          <String, Object>{
            'id': 'e1',
            'exerciseId': 'bench',
            'name': 'Bench',
            'sets': <Object>[
              <String, Object>{'id': 's1', 'reps': 'eight'},
            ],
          },
        ],
      }),
    };

    for (final MapEntry<String, String> entry in damaged.entries) {
      test('a stored draft with ${entry.key} is dropped, not thrown', () async {
        final ProviderContainer container =
            await containerWith({_draftKey: entry.value});
        expect(container.read(activeWorkoutProvider), isNull);
      });
    }

    test('a damaged draft does not block starting a fresh workout', () async {
      final ProviderContainer container =
          await containerWith({_draftKey: '{broken'});
      final ActiveWorkoutNotifier notifier =
          container.read(activeWorkoutProvider.notifier);

      await notifier.start();

      final WorkoutDraft? draft = container.read(activeWorkoutProvider);
      expect(draft, isNotNull);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      // The broken value was overwritten by a readable one.
      expect(
        () => jsonDecode(prefs.getString(_draftKey)!),
        returnsNormally,
      );
    });

    test('a draft written before optional fields existed still loads',
        () async {
      // Shape of a draft from before warm-ups, time-based sets, supersets and
      // RPE/rest were added. An app update must not throw these away.
      final String legacy = jsonEncode(<String, Object>{
        'id': 'd1',
        'startedAt': '2026-09-01T10:00:00.000Z',
        'exercises': <Object>[
          <String, Object>{
            'id': 'e1',
            'exerciseId': 'bench',
            'name': 'Bench press',
            'sets': <Object>[
              <String, Object>{'id': 's1'},
              // An integer weight, as JSON writes 100.0 on some platforms.
              <String, Object>{'id': 's2', 'weightKg': 100, 'reps': 5},
            ],
          },
        ],
      });

      final ProviderContainer container =
          await containerWith({_draftKey: legacy});
      final WorkoutDraft draft = container.read(activeWorkoutProvider)!;

      final DraftExercise exercise = draft.exercises.single;
      expect(exercise.isWarmup, isFalse);
      expect(exercise.isTimeBased, isFalse);
      expect(exercise.supersetGroupId, isNull);
      expect(exercise.sets.first.weightKg, 0);
      expect(exercise.sets.first.reps, 0);
      expect(exercise.sets.first.isCompleted, isFalse);
      expect(exercise.sets.last.weightKg, 100.0);
      expect(exercise.sets.last.weightKg, isA<double>());
      expect(exercise.sets.last.reps, 5);
      expect(draft.startedAt, DateTime.utc(2026, 9, 1, 10));
    });
  });

  group('round trip through a relaunch', () {
    test('every field of every set survives exactly', () async {
      final ProviderContainer first = await containerWith({});
      final ActiveWorkoutNotifier notifier =
          first.read(activeWorkoutProvider.notifier);
      await notifier.start();
      await notifier.addExercise(
        exerciseId: 'plank',
        name: 'Plank',
        isTimeBased: true,
      );
      await notifier.addExercise(exerciseId: 'bench', name: 'Bench');
      WorkoutDraft draft = first.read(activeWorkoutProvider)!;
      final String plankId = draft.exercises[0].id;
      final String benchId = draft.exercises[1].id;
      await notifier.groupWithPrevious(benchId);
      await notifier.updateSet(
        plankId,
        draft.exercises[0].sets.single.id,
        durationSeconds: 90,
        isCompleted: true,
      );
      await notifier.updateSet(
        benchId,
        draft.exercises[1].sets.single.id,
        // Deliberately not representable exactly in binary: a pound
        // conversion produces values like this.
        weightKg: 102.0582,
        reps: 7,
        rpeTimes10: 85,
        restSeconds: 150,
        isWarmup: true,
        isCompleted: true,
      );
      draft = first.read(activeWorkoutProvider)!;
      first.dispose();

      final ProviderContainer second = await relaunch();
      expect(second.read(activeWorkoutProvider), draft);
    });

    test('Unicode and quote characters in names survive encoding', () async {
      final ProviderContainer first = await containerWith({});
      final ActiveWorkoutNotifier notifier =
          first.read(activeWorkoutProvider.notifier);
      await notifier.start();
      const String name = 'ضغط "بنش" \\ 🏋️ \n';
      await notifier.addExercise(exerciseId: 'bench', name: name);
      first.dispose();

      final ProviderContainer second = await relaunch();
      expect(
        second.read(activeWorkoutProvider)!.exercises.single.name,
        name,
      );
    });
  });

  group('saving', () {
    test('an empty draft is not saved and is kept', () async {
      final ProviderContainer container = await containerWith({});
      final ActiveWorkoutNotifier notifier =
          container.read(activeWorkoutProvider.notifier);
      await notifier.start();

      await notifier.save();

      expect(container.read(activeWorkoutProvider), isNotNull);
      expect(await db.select(db.workoutsTable).get(), isEmpty);
    });

    test('saving with no draft at all is a no-op', () async {
      final ProviderContainer container = await containerWith({});

      await container.read(activeWorkoutProvider.notifier).save();

      expect(await db.select(db.workoutsTable).get(), isEmpty);
    });

    test(
        'a successful save writes the workout, counts only completed working '
        'sets toward volume, and clears the stored draft', () async {
      await insertExercise('bench');
      final ProviderContainer container = await containerWith({});
      final ActiveWorkoutNotifier notifier =
          container.read(activeWorkoutProvider.notifier);
      await notifier.start();
      await notifier.addExercise(exerciseId: 'bench', name: 'Bench');
      final String exerciseId =
          container.read(activeWorkoutProvider)!.exercises.single.id;
      await notifier.addSet(exerciseId);
      await notifier.addSet(exerciseId);
      final List<DraftSet> sets =
          container.read(activeWorkoutProvider)!.exercises.single.sets;
      // Counted: 100 x 5.
      await notifier.updateSet(
        exerciseId,
        sets[0].id,
        weightKg: 100,
        reps: 5,
        isCompleted: true,
      );
      // Not counted: a warm-up.
      await notifier.updateSet(
        exerciseId,
        sets[1].id,
        weightKg: 60,
        reps: 10,
        isCompleted: true,
        isWarmup: true,
      );
      // Not counted: entered but never ticked off.
      await notifier.updateSet(exerciseId, sets[2].id, weightKg: 100, reps: 5);

      await notifier.save();

      final List<WorkoutsTableData> workouts =
          await db.select(db.workoutsTable).get();
      expect(workouts, hasLength(1));
      expect(workouts.single.totalVolumeKg, 500);
      expect(await db.select(db.workoutSetsTable).get(), hasLength(3));
      expect(container.read(activeWorkoutProvider), isNull);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(_draftKey), isFalse);
    });

    test(
        'a save that fails in the database keeps the draft in memory and on '
        'disk, and writes nothing', () async {
      // `bench` exists, `ghost` does not: the second workout-exercise row
      // violates its foreign key. This is what happens when the catalogue
      // changes under an open draft, e.g. an import in replace mode.
      await insertExercise('bench');
      final ProviderContainer container = await containerWith({});
      final ActiveWorkoutNotifier notifier =
          container.read(activeWorkoutProvider.notifier);
      await notifier.start();
      await notifier.addExercise(exerciseId: 'bench', name: 'Bench');
      await notifier.addExercise(exerciseId: 'ghost', name: 'Deleted lift');
      final WorkoutDraft before = container.read(activeWorkoutProvider)!;

      await expectLater(notifier.save(), throwsA(anything));

      expect(container.read(activeWorkoutProvider), before);
      // The transaction rolled back: no orphaned workout header or sets.
      expect(await db.select(db.workoutsTable).get(), isEmpty);
      expect(await db.select(db.workoutExercisesTable).get(), isEmpty);
      expect(await db.select(db.workoutSetsTable).get(), isEmpty);
      container.dispose();

      // And the draft is still there after a relaunch, so nothing typed
      // during the session is lost.
      final ProviderContainer after = await relaunch();
      expect(after.read(activeWorkoutProvider), before);
    });

    test('saving the same draft twice does not create a duplicate', () async {
      await insertExercise('bench');
      final ProviderContainer container = await containerWith({});
      final ActiveWorkoutNotifier notifier =
          container.read(activeWorkoutProvider.notifier);
      await notifier.start();
      await notifier.addExercise(exerciseId: 'bench', name: 'Bench');

      // A double tap on Finish: both calls start before either finishes.
      final List<Object?> errors = <Object?>[];
      await Future.wait(<Future<void>>[
        notifier.save().catchError((Object e) => errors.add(e)),
        notifier.save().catchError((Object e) => errors.add(e)),
      ]);

      expect(await db.select(db.workoutsTable).get(), hasLength(1));
      expect(container.read(activeWorkoutProvider), isNull);
      // The loser may fail on the primary key; it must not have left the
      // draft behind to be saved a third time.
      expect(errors.length, lessThanOrEqualTo(1));
    });
  });

  group('edits addressed to things that are not there', () {
    late ProviderContainer container;
    late ActiveWorkoutNotifier notifier;

    setUp(() async {
      container = await containerWith({});
      notifier = container.read(activeWorkoutProvider.notifier);
    });

    test('every mutation is a no-op when no workout is in progress', () async {
      await notifier.addExercise(exerciseId: 'bench', name: 'Bench');
      await notifier.addSet('x');
      await notifier.updateSet('x', 'y', reps: 5);
      await notifier.removeExercise('x');
      await notifier.reorderExercise('x', 0);
      await notifier.groupWithPrevious('x');
      await notifier.ungroupFromSuperset('x');

      expect(container.read(activeWorkoutProvider), isNull);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(_draftKey), isFalse);
    });

    test('unknown exercise and set ids leave the draft unchanged', () async {
      await notifier.start();
      await notifier.addExercise(exerciseId: 'bench', name: 'Bench');
      final WorkoutDraft before = container.read(activeWorkoutProvider)!;
      final String exerciseId = before.exercises.single.id;

      await notifier.updateSet('no-such-exercise', 'no-such-set', reps: 5);
      await notifier.updateSet(exerciseId, 'no-such-set', reps: 5);
      await notifier.duplicateSet(exerciseId, 'no-such-set');
      await notifier.removeExercise('no-such-exercise');

      expect(container.read(activeWorkoutProvider), before);
    });

    test('the last set of an exercise cannot be removed', () async {
      await notifier.start();
      await notifier.addExercise(exerciseId: 'bench', name: 'Bench');
      final DraftExercise exercise =
          container.read(activeWorkoutProvider)!.exercises.single;

      await notifier.removeSet(exercise.id, exercise.sets.single.id);

      expect(
        container.read(activeWorkoutProvider)!.exercises.single.sets,
        hasLength(1),
      );
    });

    test('reordering to an out-of-range position is ignored', () async {
      await notifier.start();
      await notifier.addExercise(exerciseId: 'a', name: 'A');
      await notifier.addExercise(exerciseId: 'b', name: 'B');
      final WorkoutDraft before = container.read(activeWorkoutProvider)!;
      final String firstId = before.exercises.first.id;

      await notifier.reorderExercise(firstId, -1);
      await notifier.reorderExercise(firstId, 2);
      await notifier.reorderExercise(firstId, 999);

      expect(container.read(activeWorkoutProvider), before);
    });

    test('the first exercise cannot be grouped with a previous one', () async {
      await notifier.start();
      await notifier.addExercise(exerciseId: 'a', name: 'A');
      final WorkoutDraft before = container.read(activeWorkoutProvider)!;

      await notifier.groupWithPrevious(before.exercises.single.id);
      await notifier.ungroupFromSuperset(before.exercises.single.id);

      expect(container.read(activeWorkoutProvider), before);
    });

    test('a template with zero or negative target sets still gets one row',
        () async {
      await notifier.startFromTemplate(const <TemplateExerciseInput>[
        TemplateExerciseInput(exerciseId: 'a', name: 'A', targetSets: 0),
        TemplateExerciseInput(exerciseId: 'b', name: 'B', targetSets: -3),
      ]);

      final WorkoutDraft draft = container.read(activeWorkoutProvider)!;
      expect(draft.exercises.map((e) => e.sets.length), <int>[1, 1]);
    });

    test('an empty template starts an empty workout', () async {
      await notifier.startFromTemplate(const <TemplateExerciseInput>[]);

      expect(container.read(activeWorkoutProvider)!.exercises, isEmpty);
    });
  });

  test('starting a new workout replaces an unsaved one', () async {
    final ProviderContainer container = await containerWith({});
    final ActiveWorkoutNotifier notifier =
        container.read(activeWorkoutProvider.notifier);
    await notifier.start();
    await notifier.addExercise(exerciseId: 'a', name: 'A');
    final String firstId = container.read(activeWorkoutProvider)!.id;

    await notifier.start();

    final WorkoutDraft draft = container.read(activeWorkoutProvider)!;
    expect(draft.id, isNot(firstId));
    expect(draft.exercises, isEmpty);
    // Documents current behaviour: `start` does not guard against this. The
    // UI only calls it when no draft exists (ActiveWorkoutPage.initState).
  });
}
