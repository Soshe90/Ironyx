import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/muscle_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';

import '../helpers/pump_app.dart';

/// Guards the Progress page against the scroll trap fixed on 2026-08-24.
///
/// The page used to be a `ListView`. A lazy sliver does not know how tall
/// the children it has not built yet are, so it estimates: `remaining
/// children x average height of the built ones`. That works when children
/// are roughly uniform. This page's are not — a hidden section is a 0px
/// `SizedBox.shrink`, a heading is ~40px, a chart card is ~300px — so the
/// average of whichever handful was on screen mispredicted the rest badly
/// and `maxScrollExtent` swung by 3000px while scrolling.
///
/// The user-visible symptom was specific and awful: scrolling back up
/// built the short top sections, which collapsed the estimate, and the
/// position was then clamped against it. A flick upward moved the page
/// *down*, and the top of the page could not be reached by dragging at
/// all.
///
/// Both tests below fail on a `ListView` and pass on the current
/// `SingleChildScrollView`. The extent one is the direct cause; the
/// gesture one is what the user actually felt.
void main() {
  group('ProgressPage scrolling', () {
    late AppDatabase database;

    // Skips the exercise seeder; this test seeds its own catalogue.
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

      // Enough history that every chart has something to draw. The bug
      // needs real data: with an empty database most sections collapse to
      // similar-sized empty states, and the height variance that breaks
      // the estimate never appears.
      final now = DateTime.now();
      for (var i = 0; i <= 11; i++) {
        final startedAt = now.subtract(Duration(days: (11 - i) * 7));
        final benchWeight = 40.0 + i * 2;
        await workoutDao.insertWorkout(
          WorkoutsTableCompanion.insert(
            id: 'workout_$i',
            startedAt: startedAt,
            endedAt: Value(startedAt.add(const Duration(minutes: 45))),
            totalVolumeKg: Value(benchWeight * 5 + 100),
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
              reps: 5,
              isCompleted: const Value(true),
            ),
            WorkoutSetsTableCompanion.insert(
              id: 'set_${i}_row',
              workoutExerciseId: 'we_${i}_row',
              setIndex: 0,
              weightKg: 20,
              reps: 5,
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

    // Phone-sized on purpose. progress_page_test.dart uses an 8000px
    // surface so every section is in the viewport at once — which is
    // exactly the condition under which this bug cannot happen.
    Future<void> pumpProgress(WidgetTester tester) async {
      await pumpApp(
        tester,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        initialLocation: '/progress',
        prefs: seededPrefs,
        surfaceSize: const Size(400, 800),
      );
      await tester.pumpAndSettle();
    }

    ScrollController controllerOf(WidgetTester tester) =>
        tester.widget<Scrollable>(find.byType(Scrollable).first).controller!;

    testWidgets('reports the same scroll extent from every position',
        (tester) async {
      await pumpProgress(tester);
      final ScrollController controller = controllerOf(tester);
      final double atTop = controller.position.maxScrollExtent;

      expect(
        atTop,
        greaterThan(800),
        reason: 'the page must be taller than the viewport to test anything',
      );

      for (final double target in <double>[500, 1500, 3000, 4000]) {
        if (target > controller.position.maxScrollExtent) continue;
        controller.jumpTo(target);
        await tester.pumpAndSettle();
        expect(
          controller.position.maxScrollExtent,
          atTop,
          reason: 'scroll extent changed at offset $target — the page is '
              'estimating its height again, which is what let the position '
              'be clamped mid-drag',
        );
      }

      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(controller.position.maxScrollExtent, atTop);

      await disposeApp(tester);
    });

    testWidgets('can be dragged back to the top after scrolling down',
        (tester) async {
      await pumpProgress(tester);
      final ScrollController controller = controllerOf(tester);

      // Small per-frame steps, like a real finger.
      Future<void> flick(double dy) async {
        final TestGesture gesture =
            await tester.startGesture(const Offset(200, 400));
        await tester.pump(const Duration(milliseconds: 16));
        for (int i = 0; i < dy.abs() ~/ 10; i++) {
          await gesture.moveBy(Offset(0, dy.isNegative ? -10 : 10));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await tester.pumpAndSettle();
      }

      for (int i = 0; i < 12; i++) {
        await flick(-600);
      }
      expect(
        controller.offset,
        greaterThan(1000),
        reason: 'the page should have scrolled well down by now',
      );

      // Every upward flick must make progress. The old failure was not
      // "slower than expected" — the offset increased while dragging up.
      double previous = controller.offset;
      for (int i = 0; i < 12; i++) {
        await flick(600);
        expect(
          controller.offset,
          lessThanOrEqualTo(previous),
          reason: 'dragging up moved the page down, from $previous to '
              '${controller.offset}',
        );
        previous = controller.offset;
      }

      expect(
        controller.offset,
        0,
        reason: 'the top of the page was never reached by dragging',
      );

      await disposeApp(tester);
    });
  });
}
