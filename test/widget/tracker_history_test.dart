import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/router/routes.dart';
import 'package:ironyx/core/widgets/app_card.dart';

import '../helpers/pump_app.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting();
    await ExerciseDao(database).upsertExercises([
      for (final (String id, String name) in <(String, String)>[
        ('my-bench', 'Incline Press'),
        ('my-row', 'Chest-Supported Row'),
      ])
        ExercisesTableCompanion.insert(
          id: id,
          slug: id,
          name: name,
          category: 'strength',
          difficulty: 'intermediate',
          movementPattern: 'other',
          seedVersion: 1,
        ),
    ]);
    final DateTime start = DateTime.now().subtract(const Duration(hours: 3));
    await WorkoutDao(database).insertWorkout(
      WorkoutsTableCompanion.insert(
        id: 'w1',
        startedAt: start,
        endedAt: Value(start.add(const Duration(minutes: 45))),
        durationSeconds: const Value(2700),
        totalVolumeKg: const Value(1200),
      ),
      [
        WorkoutExercisesTableCompanion.insert(
          id: 'w1_a',
          workoutId: 'w1',
          exerciseId: 'my-bench',
          orderIndex: 0,
        ),
        WorkoutExercisesTableCompanion.insert(
          id: 'w1_b',
          workoutId: 'w1',
          exerciseId: 'my-row',
          orderIndex: 1,
        ),
      ],
      const [],
    );
  });

  testWidgets('a history row is titled by what was trained', (tester) async {
    await pumpApp(
      tester,
      initialLocation: Routes.tracker,
      overrides: [appDatabaseProvider.overrideWithValue(database)],
      prefs: const <String, Object>{
        'exercise_seed_version': 999999,
        'program_seed_version': 999999,
      },
      surfaceSize: const Size(400, 2000),
      awaitDatabase: true,
    );
    await tester.pump();

    final Finder workoutTitle = find.text('Incline Press, Chest-Supported Row');
    expect(workoutTitle, findsOneWidget);
    expect(
      find.ancestor(of: workoutTitle, matching: find.byType(AppCard)),
      findsNothing,
    );
    // Time and duration move to the secondary line.
    expect(find.textContaining('45m'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await database.close();
  });
}
