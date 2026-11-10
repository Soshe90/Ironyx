import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/widgets/error_view.dart';
import 'package:ironyx/core/widgets/trend_badge.dart';
import 'package:ironyx/features/progress/domain/progress_providers.dart';
import 'package:ironyx/features/progress/domain/strength_analytics.dart';

import '../helpers/pump_app.dart';
import '../helpers/stub_seeders.dart';

/// The Strength chapter's rows and the relative-strength card under them.
void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting();
    await ExerciseDao(database).upsertExercises([
      for (final (String id, String name) in <(String, String)>[
        ('bench', 'Bench Press'),
        ('squat', 'Back Squat'),
        ('row', 'Cable Row'),
      ])
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

    final WorkoutDao workouts = WorkoutDao(database);
    final DateTime now = DateTime.now();
    Future<void> session(String id, int daysAgo, Map<String, double> kg) {
      final DateTime startedAt = now.subtract(Duration(days: daysAgo));
      return workouts.insertWorkout(
        WorkoutsTableCompanion.insert(
          id: id,
          startedAt: startedAt,
          endedAt: Value(startedAt.add(const Duration(minutes: 45))),
        ),
        [
          for (final (int i, String lift) in kg.keys.indexed)
            WorkoutExercisesTableCompanion.insert(
              id: '${id}_$lift',
              workoutId: id,
              exerciseId: lift,
              orderIndex: i,
            ),
        ],
        [
          for (final MapEntry<String, double> e in kg.entries)
            WorkoutSetsTableCompanion.insert(
              id: '${id}_${e.key}_s',
              workoutExerciseId: '${id}_${e.key}',
              setIndex: 0,
              weightKg: e.value,
              reps: 1,
              isCompleted: const Value(true),
            ),
        ],
      );
    }

    // Single reps, so the estimate is the weight: bench exactly level,
    // squat up 4%, row up 0.3% (which prints as 0%).
    await session('first', 30, {'bench': 100, 'squat': 100, 'row': 100});
    await session('second', 5, {'bench': 100, 'squat': 104, 'row': 100.3});
  });

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await database.close();
  }

  Future<void> pumpProgress(
    WidgetTester tester, {
    List<dynamic> overrides = const [],
  }) async {
    await pumpApp(
      tester,
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        ...stubSeeders(),
        ...overrides,
      ],
      initialLocation: '/progress',
      surfaceSize: const Size(400, 800),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a change that prints as 0% is unchanged, to sight and sound',
      (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpProgress(tester);

    expect(find.bySemanticsLabel('Bench Press, 100 kg, unchanged'),
        findsOneWidget);
    expect(
        find.bySemanticsLabel('Cable Row, 100 kg, unchanged'), findsOneWidget);
    expect(find.bySemanticsLabel('Back Squat, 104 kg, up 4 percent'),
        findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'(up|down) 0 percent')), findsNothing);

    final List<TrendBadge> badges =
        tester.widgetList<TrendBadge>(find.byType(TrendBadge)).toList();
    final List<TrendBadge> flat = <TrendBadge>[
      for (final TrendBadge b in badges)
        if (b.label == '0%') b,
    ];
    expect(flat, hasLength(2));
    expect(
      flat.map((TrendBadge b) => b.direction),
      everyElement(TrendDirection.flat),
    );

    semantics.dispose();
    await disposeApp(tester);
  });

  testWidgets('with nothing before the range, the baseline is named',
      (tester) async {
    // Both sessions are inside the default range, so each lift is compared
    // with its first session. "was 100 kg" and "up 4%" alone read as a
    // strength change against an established best.
    await pumpProgress(tester);

    expect(find.text('first session: 100 kg'), findsNWidgets(3));
    expect(find.textContaining(RegExp(r'^was ')), findsNothing);
    expect(
      find.text('Back Squat is up 4% since your first session'),
      findsOneWidget,
    );
    await disposeApp(tester);
  });

  testWidgets('relative strength says when it failed, and can retry',
      (tester) async {
    int calls = 0;
    await pumpProgress(
      tester,
      overrides: [
        relativeStrengthsProvider(ProgressRange.quarter).overrideWith((ref) {
          calls++;
          return Future<List<RelativeStrength>>.error(StateError('boom'));
        }),
      ],
    );

    // The strength list loaded; the card under it failed and says so.
    expect(find.text('Bench Press'), findsOneWidget);
    final Finder failure = find.text('Could not load this chart');
    expect(failure, findsOneWidget);

    final int before = calls;
    final Finder retry = find.descendant(
      of: find.ancestor(of: failure, matching: find.byType(ErrorView)),
      matching: find.byWidgetPredicate((Widget w) => w is ButtonStyleButton),
    );
    expect(retry, findsOneWidget);
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(calls, greaterThan(before), reason: 'retry reloads the card');
    await disposeApp(tester);
  });
}
