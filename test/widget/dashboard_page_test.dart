import 'package:drift/drift.dart';
import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/daos/exercise_dao.dart';
import 'package:fittrack/core/database/daos/workout_dao.dart';
import 'package:fittrack/core/database/database_providers.dart';
import 'package:fittrack/features/dashboard/domain/dashboard_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

/// M6 exit criterion: cards read live data, and one card failing to load
/// never blanks the rest of the dashboard.
void main() {
  group('DashboardPage', () {
    late AppDatabase database;

    const Map<String, Object> seededPrefs = <String, Object>{
      'exercise_seed_version': 999999,
    };

    setUp(() async {
      database = AppDatabase.forTesting();
      final exerciseDao = ExerciseDao(database);
      final workoutDao = WorkoutDao(database);

      await exerciseDao.upsertExercises([
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

      await workoutDao.insertWorkout(
        WorkoutsTableCompanion.insert(
          id: 'w1',
          startedAt: DateTime.now().subtract(const Duration(hours: 1)),
          endedAt: Value(DateTime.now().subtract(const Duration(minutes: 30))),
          totalVolumeKg: const Value(300),
          durationSeconds: const Value(1800),
        ),
        [
          WorkoutExercisesTableCompanion.insert(
            id: 'w1_ex',
            workoutId: 'w1',
            exerciseId: 'bench',
            orderIndex: 0,
          ),
        ],
        [
          WorkoutSetsTableCompanion.insert(
            id: 'w1_set',
            workoutExerciseId: 'w1_ex',
            setIndex: 0,
            weightKg: 60,
            reps: 5,
            isCompleted: const Value(true),
          ),
        ],
      );
    });

    // Drift's `.watch()` streams schedule a zero-duration timer on
    // cancellation; disposing the widget tree (and letting that timer fire)
    // before closing the database avoids flutter_test's "Timer still
    // pending after widget tree disposed" assertion — same fix as
    // `progress_page_test.dart`'s `disposeApp`.
    Future<void> disposeApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      await database.close();
    }

    testWidgets('renders live values for the week and last-workout blocks',
        (tester) async {
      await pumpApp(
        tester,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        prefs: seededPrefs,
      );
      await tester.pumpAndSettle();

      // Shows in both the last-workout row and the "this week" card (the
      // seeded workout is this week's only one, so both agree).
      expect(find.text('300 kg'), findsWidgets);
      // "This week" derives its session count from the frequency query.
      expect(find.text('SESSIONS'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      // With no draft persisted, the primary action offers a fresh session.
      expect(find.text('Start workout'), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('one block failing to load does not blank the others',
        (tester) async {
      await pumpApp(
        tester,
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          dashboardLastWorkoutProvider.overrideWith(
            (ref) => Stream.error(Exception('boom')),
          ),
        ],
        prefs: seededPrefs,
      );
      await tester.pumpAndSettle();

      // The "this week" card sits above the fold and renders live data...
      expect(find.text('300 kg'), findsOneWidget);
      expect(find.text('SESSIONS'), findsOneWidget);

      // ...while the failing row, further down the page, shows its own
      // error state. Recent activity is lazily built, so scroll it in.
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load'), findsOneWidget);
      // The rest of the page survived the one failure.
      expect(find.text('Last timer'), findsOneWidget);

      await disposeApp(tester);
    });
  });
}
