import 'package:drift/drift.dart' show Value;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';

import '../helpers/pump_app.dart';
import '../helpers/stub_seeders.dart';

/// Progress for someone who trained, stopped, and has logged nothing in the
/// selected range: a record of the break, not a new user's invitation.
void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting();
    await ExerciseDao(database).upsertExercises([
      ExercisesTableCompanion.insert(
        id: 'bench',
        slug: 'bench',
        name: 'Bench Press',
        category: 'strength',
        difficulty: 'intermediate',
        movementPattern: 'horizontalPush',
        seedVersion: 1,
      ),
    ]);
    // One workout, 200 days ago: before every range but "1Y" and "All".
    final DateTime startedAt =
        DateTime.now().subtract(const Duration(days: 200));
    await WorkoutDao(database).insertWorkout(
      WorkoutsTableCompanion.insert(
        id: 'old',
        startedAt: startedAt,
        endedAt: Value(startedAt.add(const Duration(minutes: 45))),
        totalVolumeKg: const Value(500),
      ),
      [
        WorkoutExercisesTableCompanion.insert(
          id: 'old_bench',
          workoutId: 'old',
          exerciseId: 'bench',
          orderIndex: 0,
        ),
      ],
      [
        WorkoutSetsTableCompanion.insert(
          id: 'old_set',
          workoutExerciseId: 'old_bench',
          setIndex: 0,
          weightKg: 100,
          reps: 5,
          isCompleted: const Value(true),
        ),
      ],
    );
  });

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await database.close();
  }

  testWidgets('a range after a break reads as zeros, with the last workout',
      (tester) async {
    await pumpApp(
      tester,
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        ...stubSeeders(),
      ],
      initialLocation: '/progress',
      surfaceSize: const Size(400, 800),
    );
    await tester.pumpAndSettle();

    // The hero explains the zeros.
    expect(find.textContaining('Last workout:'), findsOneWidget);
    // The weekly cards draw the empty weeks instead of an invitation.
    expect(find.text('0.0 / week'), findsOneWidget);
    expect(find.textContaining('trained in 0 of'), findsOneWidget);
    expect(find.text('Complete a workout to see volume.'), findsNothing);
    expect(find.byType(BarChart), findsWidgets);
    for (final BarChart chart
        in tester.widgetList<BarChart>(find.byType(BarChart))) {
      expect(chart.data.maxY, greaterThan(0), reason: 'all-zero axis');
    }
    // Adherence is a real 0%, not "—".
    expect(find.text('0%'), findsWidgets);
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });
}
