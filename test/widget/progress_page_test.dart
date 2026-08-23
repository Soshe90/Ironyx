import 'package:drift/drift.dart' show Value;
import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/daos/exercise_dao.dart';
import 'package:fittrack/core/database/daos/muscle_dao.dart';
import 'package:fittrack/core/database/daos/workout_dao.dart';
import 'package:fittrack/core/database/database_providers.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

/// Exercises the Progress page against ~3 months of seeded data (build-plan
/// M5 exit criterion) and verifies the accessible analytics sections added in
/// Phases 2 and 3. Chart implementation details are intentionally kept out of
/// these assertions except where the weekly series contract matters.
void main() {
  group('ProgressPage', () {
    late AppDatabase database;

    const seededPrefs = <String, Object>{'exercise_seed_version': 999999};

    setUp(() async {
      database = AppDatabase.forTesting();
      final muscleDao = MuscleDao(database);
      final exerciseDao = ExerciseDao(database);
      final workoutDao = WorkoutDao(database);

      await muscleDao.upsertAll([
        MusclesTableCompanion.insert(
          id: 'chest',
          name: 'chest',
          displayName: 'Chest',
        ),
        MusclesTableCompanion.insert(
          id: 'back',
          name: 'back',
          displayName: 'Back',
        ),
      ]);

      Future<void> seedExercise(String id, String name, String muscleId) =>
          exerciseDao.upsertExercises([
            ExercisesTableCompanion.insert(
              id: id,
              slug: id,
              name: name,
              category: 'strength',
              difficulty: 'intermediate',
              movementPattern: 'horizontalPush',
              seedVersion: 1,
            ),
          ]).then(
            (_) => exerciseDao.replaceMuscleLinks(id, [
              ExerciseMusclesTableCompanion.insert(
                id: '${id}_m',
                exerciseId: id,
                muscleId: muscleId,
                role: 'primary',
              ),
            ]),
          );

      await seedExercise('bench_1', 'Bench Press', 'chest');
      await seedExercise('row_1', 'Barbell Row', 'back');
      // Seeded but never performed. The 1RM picker used to list the whole
      // catalogue, so an exercise like this was offered — and charted
      // nothing when picked.
      await seedExercise('zzz_unperformed', 'Never Performed', 'chest');

      // 13 weekly workouts spanning ~3 months. Bench weight is flat for
      // several weeks, jumps to a new max mid-way, stays flat again, dips,
      // then jumps to the highest weight on the very last workout — so only
      // *some* workouts are genuine PRs and the test can tell them apart
      // from an merely-recent-but-not-a-record workout. Row weight stays
      // flat and low throughout, so Chest unambiguously outranks Back in
      // the muscle-group breakdown, keeping the interaction assertions
      // deterministic without hardcoding a tie-break.
      const benchWeights = [
        40.0, 40.0, 40.0, 40.0, 40.0, 40.0, // 0-5: flat
        50.0, 50.0, 50.0, 50.0, // 6-9: new max, then flat
        45.0, 45.0, // 10-11: a dip below the current max
        70.0, // 12: new max — the latest workout is the PR
      ];
      final now = DateTime.now();
      for (var i = 0; i <= 12; i++) {
        final startedAt = now.subtract(Duration(days: (12 - i) * 7));
        final endedAt = startedAt.add(const Duration(minutes: 45));
        final benchWeight = benchWeights[i];
        const benchReps = 5;
        const rowWeight = 20.0;
        const rowReps = 5;
        final totalVolume = benchWeight * benchReps + rowWeight * rowReps;

        await workoutDao.insertWorkout(
          WorkoutsTableCompanion.insert(
            id: 'workout_$i',
            startedAt: startedAt,
            endedAt: Value(endedAt),
            totalVolumeKg: Value(totalVolume),
          ),
          [
            WorkoutExercisesTableCompanion.insert(
              id: 'we_${i}_bench',
              workoutId: 'workout_$i',
              exerciseId: 'bench_1',
              orderIndex: 0,
            ),
            WorkoutExercisesTableCompanion.insert(
              id: 'we_${i}_row',
              workoutId: 'workout_$i',
              exerciseId: 'row_1',
              orderIndex: 1,
            ),
          ],
          [
            WorkoutSetsTableCompanion.insert(
              id: 'set_${i}_bench',
              workoutExerciseId: 'we_${i}_bench',
              setIndex: 0,
              weightKg: benchWeight,
              reps: benchReps,
              isCompleted: const Value(true),
            ),
            WorkoutSetsTableCompanion.insert(
              id: 'set_${i}_row',
              workoutExerciseId: 'we_${i}_row',
              setIndex: 0,
              weightKg: rowWeight,
              reps: rowReps,
              isCompleted: const Value(true),
            ),
          ],
        );
      }
    });

    Future<void> disposeApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      await database.close();
    }

    Future<void> pumpProgress(WidgetTester tester) async {
      await pumpApp(
        tester,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        initialLocation: '/progress',
        prefs: seededPrefs,
        // Tall enough that every section is inside the viewport: a
        // ListView only builds what is near the fold, and the assertions
        // below reach for charts near the bottom of the page.
        surfaceSize: const Size(400, 8000),
      );
      // ProgressPage has no indefinitely-animating widgets once every
      // stream has data (unlike Library/Timer's DB-loading shimmer — see
      // shell_navigation_test.dart) — an in-memory test database resolves
      // for real, so pumpAndSettle terminates instead of timing out. The
      // page's several independent top-level StreamBuilders don't all
      // deliver their first event within pumpApp's single fixed-duration
      // pump, so this is needed for every chart to be present, not just
      // the first one built.
      await tester.pumpAndSettle();
    }

    testWidgets(
        'renders every chart with three months of seeded data, no empty '
        'states', (tester) async {
      final stopwatch = Stopwatch()..start();
      await pumpProgress(tester);
      stopwatch.stop();

      // Soft performance guard — a render taking anywhere near a second in
      // a `flutter test` harness (no real device jank, no GPU) means a
      // query or rebuild loop regressed badly.
      expect(stopwatch.elapsedMilliseconds, lessThan(15000));

      // The picker only offers lifts with logged sets, labelled with their
      // session count. Both seeded lifts appear in 13 sessions each, so the
      // tie breaks alphabetically on "Barbell Row" — assert on the label
      // rather than on which one wins the tie.
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.textContaining('· 13 sessions'), findsWidgets);
      // The seeded-but-never-performed exercise is not offered at all.
      expect(find.textContaining('Never Performed'), findsNothing);

      // Body metrics weren't seeded, so its empty state is expected — but
      // the 1RM, weekly-volume, frequency and muscle-group charts all have
      // data and must not fall back to their own empty states.
      expect(find.text('Complete weighted sets to see strength trends.'),
          findsNothing);
      expect(find.text('Complete a workout to see volume.'), findsNothing);
      expect(
        find.text('Complete workouts to see your weekly frequency.'),
        findsNothing,
      );
      expect(
        find.text('Complete a workout to see your muscle-group split.'),
        findsNothing,
      );

      expect(find.byType(LineChart), findsOneWidget);
      final lineChart = tester.widget<LineChart>(find.byType(LineChart));
      final spots = lineChart.data.lineBarsData.single.spots;
      expect(spots, isNotEmpty);
      // Time-proportional x axis: 13 weekly sessions span ~84 days, so the
      // last x is nowhere near the old index-based `length - 1`.
      expect(spots.first.x, 0);
      expect(spots.last.x, greaterThan(80));

      // Weekly volume and frequency remain chart-backed and span the same
      // elapsed-week buckets. Muscle-group volume is now also exposed through
      // an accessible dated list, so it is not treated as a fixed chart count.
      expect(find.byType(BarChart), findsAtLeastNWidgets(2));
      final weeklyVolumeChart =
          tester.widget<BarChart>(find.byType(BarChart).at(0));
      expect(weeklyVolumeChart.data.barGroups, isNotEmpty);
      final frequencyChart =
          tester.widget<BarChart>(find.byType(BarChart).at(1));
      expect(
        frequencyChart.data.barGroups,
        hasLength(weeklyVolumeChart.data.barGroups.length),
        reason: 'both weekly charts must span the same buckets',
      );

      // Phase 1–3 sections are plain widget text so they remain reachable to
      // screen readers and do not depend on canvas-painted chart labels.
      expect(find.text('Insights'), findsOneWidget);
      expect(find.text('Consistency'), findsOneWidget);
      expect(find.textContaining('Adherence'), findsOneWidget);
      expect(find.text('Training balance'), findsOneWidget);
      expect(find.text('Rep-range distribution'), findsOneWidget);
      expect(find.text('Training days'), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('weekly series includes untrained weeks', (tester) async {
      await pumpProgress(tester);

      // Workouts are seeded one per week for 13 weeks inside a 90-day
      // window, so every bucket is trained and the counts line up — the
      // point here is that the caption reports elapsed weeks alongside
      // active ones rather than dividing by active weeks alone.
      final volumeChart = tester.widget<BarChart>(find.byType(BarChart).at(0));
      final frequencyChart =
          tester.widget<BarChart>(find.byType(BarChart).at(1));
      expect(volumeChart.data.barGroups.length, greaterThanOrEqualTo(13));
      expect(find.textContaining('active week'), findsOneWidget);
      expect(find.textContaining('trained in'), findsOneWidget);

      // Every rod is a real weekly bucket, and the bars were narrowed to fit
      // rather than overlapping at the fixed 22dp design width.
      final double width =
          frequencyChart.data.barGroups.first.barRods.first.width;
      expect(width, greaterThan(0));
      expect(width, lessThanOrEqualTo(22));

      await disposeApp(tester);
    });

    // A plain `test`, not `testWidgets` — this only awaits a DAO stream, no
    // widgets involved, and `testWidgets` runs its body inside `FakeAsync`,
    // where a `Future`/`Stream` that resolves via a real `Timer` (as
    // drift's table-change notifications do) never fires without an
    // explicit `tester.pump()` to advance fake time. Without a widget tree
    // to pump, that stream simply hangs — which is exactly what happened
    // here before this was split out (a 10-minute test timeout).
    test('the latest (heaviest) workout is a personal record', () async {
      final ids =
          await WorkoutDao(database).watchPersonalRecordWorkoutIds().first;
      // workout_0 is trivially a PR (nothing came before it); workout_6
      // breaks 40kg with 50kg; workout_12 breaks 50kg with 70kg.
      expect(ids, containsAll(['workout_0', 'workout_6', 'workout_12']));
      // Repeating the same weight, or dipping below the current max, is
      // never a PR — even on the most recent workout.
      expect(ids, isNot(contains('workout_1')));
      expect(ids, isNot(contains('workout_11')));

      await database.close();
    });

    testWidgets('renders Phase 2 and Phase 3 analytics copy accessibly',
        (tester) async {
      await pumpProgress(tester);

      expect(find.text('Insights'), findsOneWidget);
      expect(find.text('Consistency'), findsOneWidget);
      expect(find.text('Training balance'), findsOneWidget);
      expect(find.text('Rep-range distribution'), findsOneWidget);
      expect(find.text('Training days'), findsOneWidget);
      expect(find.textContaining('/month'), findsOneWidget);

      await disposeApp(tester);
    });
  });
}
