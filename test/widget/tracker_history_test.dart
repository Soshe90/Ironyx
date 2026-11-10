import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/router/routes.dart';
import 'package:ironyx/core/widgets/app_card.dart';
import 'package:ironyx/features/tracker/presentation/widgets/history_calendar.dart';

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
      // Wide: the test font draws every letter as a full square, so at phone
      // width the fitted title would drop to one name (see the "+N" tests).
      surfaceSize: const Size(1400, 2000),
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

  Future<void> pumpTracker(
    WidgetTester tester, {
    Size surfaceSize = const Size(400, 2000),
  }) async {
    await pumpApp(
      tester,
      initialLocation: Routes.tracker,
      overrides: [appDatabaseProvider.overrideWithValue(database)],
      prefs: const <String, Object>{
        'exercise_seed_version': 999999,
        'program_seed_version': 999999,
      },
      surfaceSize: surfaceSize,
      awaitDatabase: true,
    );
    await tester.pump();
  }

  Future<void> disposeTracker(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await database.close();
  }

  testWidgets(
      'starting a workout is a plain button, not a copy of the dashboard hero',
      (tester) async {
    await pumpTracker(tester);

    final Finder start = find.widgetWithText(FilledButton, 'Start workout');
    expect(start, findsOneWidget);
    expect(
        find.ancestor(of: start, matching: find.byType(AppCard)), findsNothing);
    expect(find.text('Ready to train'), findsNothing);

    await disposeTracker(tester);
  });

  testWidgets('the calendar is hidden until asked for and the list stays',
      (tester) async {
    // Wide enough for the two-name title in the square-glyph test font.
    await pumpTracker(tester, surfaceSize: const Size(1400, 2000));
    final Finder workout = find.text('Incline Press, Chest-Supported Row');

    expect(find.byType(HistoryCalendar), findsNothing);
    expect(workout, findsOneWidget);

    await tester.tap(find.byTooltip('Show calendar'));
    await tester.pump();
    expect(find.byType(HistoryCalendar), findsOneWidget);
    expect(workout, findsOneWidget);

    await tester.tap(find.byTooltip('Hide calendar'));
    await tester.pump();
    expect(find.byType(HistoryCalendar), findsNothing);

    await disposeTracker(tester);
  });

  testWidgets('XLSX import moved into the history menu', (tester) async {
    await pumpTracker(tester);

    expect(find.text('Import XLSX'), findsNothing);
    await tester.tap(find.byTooltip('History options'));
    await tester.pumpAndSettle();
    expect(find.text('Import XLSX'), findsOneWidget);

    await disposeTracker(tester);
  });

  testWidgets(
      'history is grouped under one month heading, and a long title ends '
      'with "+N" instead of being cut mid-word', (tester) async {
    await ExerciseDao(database).upsertExercises([
      for (final (String id, String name) in <(String, String)>[
        ('my-dl', 'Deadlift'),
        ('my-curl', 'Curl'),
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
    final w1 = await (database.select(database.workoutsTable)
          ..where((t) => t.id.equals('w1')))
        .getSingle();
    // A minute before w1, so both always fall in the same month.
    final DateTime start = w1.startedAt.subtract(const Duration(minutes: 1));
    await WorkoutDao(database).insertWorkout(
      WorkoutsTableCompanion.insert(
        id: 'w2',
        startedAt: start,
        endedAt: Value(start.add(const Duration(minutes: 30))),
        durationSeconds: const Value(1800),
        totalVolumeKg: const Value(800),
      ),
      [
        for (final (int i, String ex) in <(int, String)>[
          (0, 'my-dl'),
          (1, 'my-bench'),
          (2, 'my-row'),
          (3, 'my-curl'),
        ])
          WorkoutExercisesTableCompanion.insert(
            id: 'w2_$i',
            workoutId: 'w2',
            exerciseId: ex,
            orderIndex: i,
          ),
      ],
      const [],
    );
    // Wide enough for two names in the square-glyph test font.
    await pumpTracker(tester, surfaceSize: const Size(1400, 2000));

    // One heading for the month with its totals, not one per day.
    expect(
      find.text(DateFormat('MMMM yyyy').format(start).toUpperCase()),
      findsOneWidget,
    );
    expect(find.text('2 workouts · 2,000 kg'), findsOneWidget);
    expect(find.text('TODAY'), findsNothing);

    expect(find.text('Deadlift, Incline Press'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    expect(find.text('Incline Press, Chest-Supported Row'), findsOneWidget);

    await disposeTracker(tester);
  });

  testWidgets(
      'long names drop to one plus a "+N" pill that stays fully visible',
      (tester) async {
    await ExerciseDao(database).upsertExercises([
      for (final (String id, String name) in <(String, String)>[
        ('my-long', 'Single-Arm Landmine Rotational Press With A Long Pause'),
        ('my-long2', 'Bulgarian Split Squat With Front Rack Hold'),
        ('my-curl', 'Curl'),
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
    await WorkoutDao(database).deleteWorkout('w1');
    final DateTime start = DateTime.now().subtract(const Duration(hours: 2));
    await WorkoutDao(database).insertWorkout(
      WorkoutsTableCompanion.insert(
        id: 'w3',
        startedAt: start,
        endedAt: Value(start.add(const Duration(minutes: 30))),
        durationSeconds: const Value(1800),
        totalVolumeKg: const Value(500),
      ),
      [
        for (final (int i, String ex) in <(int, String)>[
          (0, 'my-long'),
          (1, 'my-long2'),
          (2, 'my-curl'),
        ])
          WorkoutExercisesTableCompanion.insert(
            id: 'w3_$i',
            workoutId: 'w3',
            exerciseId: ex,
            orderIndex: i,
          ),
      ],
      const [],
    );
    await pumpTracker(tester);

    // Two long names do not fit beside the pill, so the second is dropped
    // and counted rather than cut mid-word.
    expect(
      find.text('Single-Arm Landmine Rotational Press With A Long Pause'),
      findsOneWidget,
    );
    expect(find.textContaining('Bulgarian'), findsNothing);
    final Rect pill = tester.getRect(find.text('+2'));
    final Rect volume = tester.getRect(find.text('500 kg'));
    // Entirely on screen and clear of the volume, however long the names.
    expect(pill.left, greaterThan(0));
    expect(pill.right, lessThanOrEqualTo(volume.left));

    await disposeTracker(tester);
  });

  testWidgets('with no history there is no calendar toggle, but import stays',
      (tester) async {
    await WorkoutDao(database).deleteWorkout('w1');
    await pumpTracker(tester);

    expect(find.text('No workouts yet'), findsOneWidget);
    expect(find.byTooltip('Show calendar'), findsNothing);
    expect(find.byTooltip('History options'), findsOneWidget);

    await disposeTracker(tester);
  });
}
