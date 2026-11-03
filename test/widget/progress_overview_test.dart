import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/muscle_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';

import '../helpers/pump_app.dart';

/// Behaviour introduced by the Progress restyle: the overview hero's
/// figures, the five-lift preview on Strength change, and hiding muscle
/// groups that only bodyweight work touched.
void main() {
  late AppDatabase database;

  /// Seven weighted lifts plus a bodyweight core movement, in three
  /// sessions over the last three weeks.
  const List<String> lifts = <String>[
    'Lift A',
    'Lift B',
    'Lift C',
    'Lift D',
    'Lift E',
    'Lift F',
    'Lift G',
  ];
  const int sessions = 3;
  const double sessionVolumeKg = 1000;

  setUp(() async {
    database = AppDatabase.forTesting();
    final MuscleDao muscles = MuscleDao(database);
    final ExerciseDao exercises = ExerciseDao(database);
    final WorkoutDao workouts = WorkoutDao(database);

    await muscles.upsertAll(<MusclesTableCompanion>[
      MusclesTableCompanion.insert(
          id: 'chest', name: 'chest', displayName: 'Chest'),
      MusclesTableCompanion.insert(
          id: 'core', name: 'core', displayName: 'Core'),
    ]);

    Future<void> seedExercise(String id, String name, String muscle) async {
      await exercises.upsertExercises(<ExercisesTableCompanion>[
        ExercisesTableCompanion.insert(
          id: id,
          slug: id,
          name: name,
          category: 'strength',
          difficulty: 'intermediate',
          movementPattern: 'horizontalPush',
          seedVersion: 1,
        ),
      ]);
      await exercises.replaceMuscleLinks(id, <ExerciseMusclesTableCompanion>[
        ExerciseMusclesTableCompanion.insert(
          id: '${id}_m',
          exerciseId: id,
          muscleId: muscle,
          role: 'primary',
        ),
      ]);
    }

    for (int i = 0; i < lifts.length; i++) {
      await seedExercise('lift_$i', lifts[i], 'chest');
    }
    await seedExercise('plank', 'Plank', 'core');

    final DateTime now = DateTime.now();
    for (int w = 0; w < sessions; w++) {
      final String wid = 'w$w';
      final DateTime startedAt = now.subtract(Duration(days: 7 * w + 1));
      final List<String> ids = <String>[
        for (int i = 0; i < lifts.length; i++) 'lift_$i',
        'plank',
      ];
      await workouts.insertWorkout(
        WorkoutsTableCompanion.insert(
          id: wid,
          startedAt: startedAt,
          endedAt: Value(startedAt.add(const Duration(minutes: 50))),
          totalVolumeKg: const Value(sessionVolumeKg),
        ),
        <WorkoutExercisesTableCompanion>[
          for (int e = 0; e < ids.length; e++)
            WorkoutExercisesTableCompanion.insert(
              id: '${wid}_$e',
              workoutId: wid,
              exerciseId: ids[e],
              orderIndex: e,
            ),
        ],
        <WorkoutSetsTableCompanion>[
          for (int e = 0; e < ids.length; e++)
            WorkoutSetsTableCompanion.insert(
              id: '${wid}_${e}_s',
              workoutExerciseId: '${wid}_$e',
              setIndex: 0,
              // The plank is bodyweight: logged, but 0 kg of volume.
              weightKg: ids[e] == 'plank' ? 0 : 20.0 + 5 * e,
              reps: 5,
              isCompleted: const Value(true),
            ),
        ],
      );
    }
  });

  Future<void> pumpProgress(WidgetTester tester) async {
    await pumpApp(
      tester,
      overrides: [appDatabaseProvider.overrideWithValue(database)],
      initialLocation: '/progress',
      prefs: const <String, Object>{'exercise_seed_version': 999999},
      surfaceSize: const Size(400, 9000),
    );
    await tester.pumpAndSettle();
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await database.close();
  }

  testWidgets('the overview hero summarises the selected window',
      (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpProgress(tester);

    expect(find.text('LAST 90 DAYS'), findsOneWidget);
    expect(find.text('Total volume lifted'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Total volume lifted: 3,000 kg'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Workouts: $sessions'), findsOneWidget);

    // Switching the range re-labels the hero; it follows the same control
    // every section below does.
    await tester.tap(find.text('2W'));
    await tester.pumpAndSettle();
    expect(find.text('LAST 14 DAYS'), findsOneWidget);
    expect(find.bySemanticsLabel('Workouts: 2'), findsOneWidget);

    semantics.dispose();
    await disposeApp(tester);
  });

  testWidgets('strength change previews five lifts and expands to all',
      (tester) async {
    await pumpProgress(tester);

    int visibleLifts() => lifts
        .where((String name) => find.text(name).evaluate().isNotEmpty)
        .length;

    expect(visibleLifts(), 5);
    final Finder more = find.textContaining('more lifts');
    expect(more, findsOneWidget);

    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(visibleLifts(), lifts.length);
    expect(find.text('Show fewer'), findsOneWidget);

    await tester.tap(find.text('Show fewer'));
    await tester.pumpAndSettle();
    expect(visibleLifts(), 5);

    await disposeApp(tester);
  });

  testWidgets('muscle groups with no weighted volume are left out',
      (tester) async {
    await pumpProgress(tester);

    // Chest carries all the load and leads the split…
    expect(find.text('Chest'), findsWidgets);
    // …while Core, touched only by the 0 kg plank, is neither a ranked bar
    // nor a row of zeros in the weekly list.
    expect(find.text('Core'), findsNothing);
    expect(find.text('0 kg'), findsNothing);

    await disposeApp(tester);
  });
}
