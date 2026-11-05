import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/router/routes.dart';
import 'package:ironyx/features/tracker/domain/active_workout_notifier.dart';
import 'package:ironyx/features/tracker/presentation/active_workout_page.dart';
import 'package:ironyx/features/tracker/presentation/workout_edit_page.dart';

import '../helpers/pump_app.dart';

/// Saving a workout through the real screens: the last value typed is the
/// one stored, and a double-tapped save does one save and one pop.
void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting();
    await database.into(database.exercisesTable).insert(
          ExercisesTableCompanion.insert(
            id: 'bench',
            slug: 'bench',
            name: 'Bench Press',
            category: 'strength',
            difficulty: 'intermediate',
            movementPattern: 'other',
            seedVersion: 1,
          ),
        );
  });

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await database.close();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

  /// No seeding, so the catalogue holds only `bench`.
  const Map<String, Object> skipSeeding = <String, Object>{
    'exercise_seed_version': 999999,
    'program_seed_version': 999999,
  };

  /// Each set row has a weight field then a reps field.
  Finder repsField(int setNumber) =>
      find.byType(TextField).at((setNumber - 1) * 2 + 1);

  /// Opens a live workout holding one bench press with one empty set.
  Future<void> openWorkout(WidgetTester tester) async {
    await pumpApp(
      tester,
      overrides: [appDatabaseProvider.overrideWithValue(database)],
      prefs: skipSeeding,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    await containerOf(tester)
        .read(activeWorkoutProvider.notifier)
        .addExercise(exerciseId: 'bench', name: 'Bench Press');
    await tester.pumpAndSettle();
  }

  Future<List<WorkoutSetsTableData>> savedSets() =>
      database.select(database.workoutSetsTable).get();

  testWidgets(
      'reps typed just before Finish are saved, not the value held back by '
      'the input debounce', (tester) async {
    await openWorkout(tester);

    await tester.enterText(repsField(1), '8');
    // No pump past the 300 ms debounce: Finish straight away.
    await tester.tap(find.text('Finish workout'));
    await tester.pumpAndSettle();

    expect(find.byType(ActiveWorkoutPage), findsNothing);
    expect((await savedSets()).single.reps, 8);

    await disposeApp(tester);
  });

  testWidgets('moving to another field keeps the value just typed',
      (tester) async {
    await openWorkout(tester);
    final String exerciseId =
        containerOf(tester).read(activeWorkoutProvider)!.exercises.single.id;
    await containerOf(tester)
        .read(activeWorkoutProvider.notifier)
        .addSet(exerciseId);
    await tester.pumpAndSettle();

    await tester.enterText(repsField(1), '5');
    // Leaving the row pushes the edit without waiting out the debounce.
    await tester.showKeyboard(repsField(2));
    await tester.pump();

    final draft = containerOf(tester).read(activeWorkoutProvider)!;
    expect(draft.exercises.single.sets.first.reps, 5);

    await disposeApp(tester);
  });

  testWidgets(
      'a double-tapped Finish saves once, pops once and reports success',
      (tester) async {
    await openWorkout(tester);

    // Two taps inside one frame: the second lands before the button has
    // rebuilt as disabled.
    await tester.tap(find.text('Finish workout'));
    await tester.tap(find.text('Finish workout'));
    await tester.pumpAndSettle();

    expect(await database.select(database.workoutsTable).get(), hasLength(1));
    // Back on Home, not popped past it.
    expect(find.text('Start workout'), findsOneWidget);
    expect(find.text('Workout saved'), findsOneWidget);

    // Unguarded, the second tap popped again ("nothing to pop") and queued a
    // "Couldn't save" snackbar behind the success one, for a workout that
    // was saved. Let the queue run to see it.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't save"), findsNothing);
    }

    await disposeApp(tester);
  });

  testWidgets('editing a saved workout keeps reps typed just before Save',
      (tester) async {
    final DateTime start = DateTime.now().subtract(const Duration(hours: 2));
    await WorkoutDao(database).insertWorkout(
      WorkoutsTableCompanion.insert(
        id: 'w1',
        startedAt: start,
        endedAt: Value(start.add(const Duration(minutes: 40))),
      ),
      [
        WorkoutExercisesTableCompanion.insert(
          id: 'w1_e',
          workoutId: 'w1',
          exerciseId: 'bench',
          orderIndex: 0,
        ),
      ],
      [
        WorkoutSetsTableCompanion.insert(
          id: 'w1_s',
          workoutExerciseId: 'w1_e',
          setIndex: 0,
          weightKg: 60,
          reps: 5,
          isCompleted: const Value(true),
        ),
      ],
    );
    await pumpApp(
      tester,
      overrides: [appDatabaseProvider.overrideWithValue(database)],
      prefs: skipSeeding,
    );
    await tester.pumpAndSettle();
    // Pushed over Home, as the app does, so Save has a screen to return to.
    unawaited(
      GoRouter.of(tester.element(find.byType(Scaffold).first)).pushNamed(
        Routes.workoutEditName,
        pathParameters: <String, String>{'id': 'w1'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutEditPage), findsOneWidget);

    await tester.enterText(repsField(1), '9');
    await tester.tap(find.text('Save changes'));
    // Well inside the 300 ms debounce: the save itself must carry the 9.
    // Checked here because the editor also auto-saves, so a late push would
    // still reach the database after "Workout updated" had been shown.
    await tester.pump(const Duration(milliseconds: 50));
    expect((await savedSets()).single.reps, 9);

    await tester.pumpAndSettle();
    expect(find.text('Workout updated'), findsOneWidget);

    await disposeApp(tester);
  });
}
