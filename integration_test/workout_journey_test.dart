import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/features/library/presentation/exercise_picker_sheet.dart';
import 'package:ironyx/features/tracker/domain/active_workout_notifier.dart';
import 'package:ironyx/features/tracker/domain/workout_draft.dart';
import 'package:ironyx/features/tracker/presentation/widgets/draft_editor_widgets.dart';

import 'helpers/e2e_harness.dart';

const String _exercise = 'Barbell Bench Press';

/// Logging a workout on a real device: the app's most frequent journey.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<E2eApp> launchOnDashboard(
    WidgetTester tester, {
    List<dynamic> overrides = const <dynamic>[],
  }) async {
    final E2eApp app =
        await E2eApp.install(prefs: {'onboarding_complete': true});
    await app.launch(tester, overrides: overrides);
    await pumpUntilFound(tester, find.text('Start workout'));
    return app;
  }

  /// Start workout, then pick [_exercise] from the real seeded catalogue.
  Future<void> startWithBenchPress(WidgetTester tester) async {
    await tester.tap(find.text('Start workout'));
    await pumpUntilFound(tester, find.text('Add your first exercise'));
    // Finish is disabled until there is something to finish.
    final FilledButton finish = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Finish workout'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(finish.onPressed, isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Add exercise').first);
    await pumpUntilFound(tester, find.byType(ExercisePickerSheet));
    await tester.enterText(
      find.descendant(
        of: find.byType(ExercisePickerSheet),
        matching: find.byType(TextField),
      ),
      'bench press',
    );
    final Finder row = find.descendant(
      of: find.byType(ExercisePickerSheet),
      matching: find.widgetWithText(ListTile, _exercise),
    );
    await pumpUntilFound(tester, row);
    await tester.tap(row.first);
    await pumpUntilFound(tester, find.byType(DraftSetRow));
  }

  Finder setField(int setIndex, int column) => find
      .descendant(
        of: find.byType(DraftSetRow).at(setIndex),
        matching: find.byType(TextField),
      )
      .at(column);

  Future<void> typeInto(WidgetTester tester, Finder field, String text) async {
    await tester.enterText(field, text);
    // Past the 300 ms input debounce, so the value reaches the draft.
    await pumpFor(tester, const Duration(milliseconds: 600));
  }

  WorkoutDraft? draftOf(WidgetTester tester, E2eApp app) =>
      app.container(tester).read(activeWorkoutProvider);

  testWidgets(
      'log a set, finish, and find the workout in history with the right '
      'volume', (tester) async {
    final E2eApp app = await launchOnDashboard(tester);
    await startWithBenchPress(tester);

    await typeInto(tester, setField(0, 0), '60');
    await typeInto(tester, setField(0, 1), '8');
    await tester.tap(semanticsLabelled('Set 1 complete'));
    await pumpFor(tester, const Duration(milliseconds: 300));

    // Live totals reflect the completed set before it is saved.
    expect(find.textContaining('480'), findsWidgets);

    await tester.tap(find.text('Finish workout'));
    await pumpUntilFound(tester, find.text('Workout saved'));
    expect(draftOf(tester, app), isNull);

    final List<WorkoutsTableData> workouts =
        await io(tester, () => app.db.select(app.db.workoutsTable).get());
    expect(workouts, hasLength(1));
    expect(workouts.single.totalVolumeKg, 480);
    expect(workouts.single.endedAt, isNotNull);
    final List<WorkoutSetsTableData> sets =
        await io(tester, () => app.db.select(app.db.workoutSetsTable).get());
    expect(sets.single.weightKg, 60);
    expect(sets.single.reps, 8);
    expect(sets.single.isCompleted, isTrue);

    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Workouts'),
    ));
    // History sits below the calendar and programs, and is built lazily.
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.scrollUntilVisible(
      find.textContaining(_exercise),
      300,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(find.textContaining(_exercise), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a workout in progress survives the app being killed',
      (tester) async {
    final E2eApp app = await launchOnDashboard(tester);
    await startWithBenchPress(tester);
    await typeInto(tester, setField(0, 0), '102.5');
    await typeInto(tester, setField(0, 1), '5');
    await tester.tap(semanticsLabelled('Set 1 complete'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    final WorkoutDraft before = draftOf(tester, app)!;

    await app.kill(tester);
    await app.launch(tester);

    // The dashboard offers to resume rather than start over.
    await pumpUntilFound(tester, find.text('Resume workout'));
    expect(find.text('Start workout'), findsNothing);
    await tester.tap(find.text('Resume workout'));
    await pumpUntilFound(tester, find.byType(DraftSetRow));

    expect(draftOf(tester, app), before);
    expect(tester.widget<TextField>(setField(0, 0)).controller!.text, '102.5');
    expect(tester.widget<TextField>(setField(0, 1)).controller!.text, '5');
  });

  testWidgets('invalid set input is filtered or ignored, never saved',
      (tester) async {
    final E2eApp app = await launchOnDashboard(tester);
    await startWithBenchPress(tester);
    DraftSet set() => draftOf(tester, app)!.exercises.single.sets.single;
    String text(Finder f) => tester.widget<TextField>(f).controller!.text;

    // A valid baseline to fall back to.
    await typeInto(tester, setField(0, 0), '80');
    await typeInto(tester, setField(0, 1), '10');
    expect(set().weightKg, 80);
    expect(set().reps, 10);

    // Characters that are not digits never reach the field.
    await typeInto(tester, setField(0, 0), '-5');
    expect(text(setField(0, 0)), '5');
    await typeInto(tester, setField(0, 0), 'abc');
    expect(text(setField(0, 0)), isEmpty);
    await typeInto(tester, setField(0, 1), '1e3');
    expect(text(setField(0, 1)), '13');

    // Well-formed but out of range: shown, but not written to the draft.
    await typeInto(tester, setField(0, 0), '80');
    await typeInto(tester, setField(0, 0), '1000.5');
    expect(set().weightKg, 80, reason: 'over the 1000 kg ceiling');
    await typeInto(tester, setField(0, 0), '1.2.3');
    expect(set().weightKg, 80, reason: 'not a number');
    await typeInto(tester, setField(0, 1), '10');
    await typeInto(tester, setField(0, 1), '101');
    expect(set().reps, 10, reason: 'over the 100 rep ceiling');

    // The boundaries themselves are accepted.
    await typeInto(tester, setField(0, 0), '1000');
    expect(set().weightKg, 1000);
    await typeInto(tester, setField(0, 1), '100');
    expect(set().reps, 100);
    await typeInto(tester, setField(0, 0), '0');
    expect(set().weightKg, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an exercise search with no match says so', (tester) async {
    await launchOnDashboard(tester);
    await tester.tap(find.text('Start workout'));
    await pumpUntilFound(tester, find.text('Add your first exercise'));
    await tester.tap(find.widgetWithText(FilledButton, 'Add exercise').first);
    await pumpUntilFound(tester, find.byType(ExercisePickerSheet));

    final Finder search = find.descendant(
      of: find.byType(ExercisePickerSheet),
      matching: find.byType(TextField),
    );
    // Hostile text is a search term like any other: the query is bound, not
    // spliced into SQL, so this finds nothing and harms nothing.
    for (final String query in <String>[
      'zzzzqqqq',
      "'; DROP TABLE exercises_table; --",
    ]) {
      await tester.enterText(search, query);
      await pumpUntilFound(tester, find.text('No exercises found'));
    }

    // And the catalogue is intact afterwards.
    await tester.enterText(search, 'bench press');
    await pumpUntilFound(
      tester,
      find.descendant(
        of: find.byType(ExercisePickerSheet),
        matching: find.widgetWithText(ListTile, _exercise),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('discarding can be undone, and otherwise really discards',
      (tester) async {
    final E2eApp app = await launchOnDashboard(tester);
    await startWithBenchPress(tester);
    final String draftId = draftOf(tester, app)!.id;

    Future<void> discard() async {
      await tester.tap(find.byTooltip('Workout options'));
      await pumpUntilFound(tester, find.text('Discard workout'));
      await tester.tap(find.text('Discard workout'));
      await pumpUntilFound(tester, find.text('Discard workout?'));
      await tester.tap(find.text('Discard'));
      await pumpUntilFound(tester, find.text('Workout discarded'));
      // Found as soon as it starts sliding in; let it arrive before tapping.
      await pumpFor(tester, const Duration(seconds: 1));
    }

    // Cancel in the confirmation dialog changes nothing.
    await tester.tap(find.byTooltip('Workout options'));
    await pumpUntilFound(tester, find.text('Discard workout'));
    await tester.tap(find.text('Discard workout'));
    await pumpUntilFound(tester, find.text('Discard workout?'));
    await tester.tap(find.text('Cancel'));
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(draftOf(tester, app)?.id, draftId);

    await discard();
    await tester.tap(find.text('Undo'));
    await pumpUntilFound(tester, find.byType(DraftSetRow));
    expect(draftOf(tester, app)?.id, draftId);

    await discard();
    // The undo window is 12 s; the draft stays restorable until it closes.
    expect(draftOf(tester, app), isNotNull);
    await pumpFor(tester, const Duration(seconds: 13));
    expect(draftOf(tester, app), isNull);
    await pumpUntilFound(tester, find.text('Start workout'));
    expect(
      await io(tester, () => app.db.select(app.db.workoutsTable).get()),
      isEmpty,
    );
  });

  testWidgets('a save that fails tells the user and keeps every set on screen',
      (tester) async {
    final E2eApp app = await launchOnDashboard(
      tester,
      overrides: <dynamic>[
        workoutDaoProvider.overrideWith(
          (ref) => _FailingWorkoutDao(ref.watch(appDatabaseProvider)),
        ),
      ],
    );
    await startWithBenchPress(tester);
    await typeInto(tester, setField(0, 0), '70');
    await typeInto(tester, setField(0, 1), '6');
    final WorkoutDraft before = draftOf(tester, app)!;

    await tester.tap(find.text('Finish workout'));
    await pumpUntilFound(
      tester,
      find.textContaining("Couldn't save your workout"),
    );

    // Still on the workout, nothing lost, nothing half-written.
    expect(find.byType(DraftSetRow), findsOneWidget);
    expect(draftOf(tester, app), before);
    expect(
      await io(tester, () => app.db.select(app.db.workoutsTable).get()),
      isEmpty,
    );
  });

  testWidgets('a corrupted stored draft does not stop the app launching',
      (tester) async {
    final E2eApp app = await E2eApp.install(prefs: {
      'onboarding_complete': true,
      'active_workout_draft': '{"id": "d1", "exercises": [',
    });
    await app.launch(tester);

    await pumpUntilFound(tester, find.text('Start workout'));
    expect(find.text('Resume workout'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// A DAO whose save fails the way a full disk or a locked database does.
class _FailingWorkoutDao extends WorkoutDao {
  _FailingWorkoutDao(super.db);

  @override
  Future<String> insertWorkout(
    WorkoutsTableCompanion workout,
    List<WorkoutExercisesTableCompanion> exercises,
    List<WorkoutSetsTableCompanion> sets,
  ) async {
    throw const _DiskFull();
  }
}

class _DiskFull implements Exception {
  const _DiskFull();

  @override
  String toString() => 'SqliteException(13): database or disk is full';
}
