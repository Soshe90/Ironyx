import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/services/clock.dart';
import 'package:ironyx/features/dashboard/domain/dashboard_providers.dart';
import 'package:ironyx/l10n/app_localizations.dart';

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

    testWidgets('shows session goal progress and the trained weekday',
        (tester) async {
      await pumpApp(
        tester,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        prefs: seededPrefs,
      );
      await tester.pumpAndSettle();

      // No profile target is set, so the default of 3 applies.
      expect(find.text('Weekly session goal'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
      // One completed workout marks exactly one day of the Mon-Sun strip.
      expect(find.byIcon(Icons.check), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('expanded width lays the sections out in columns',
        (tester) async {
      await pumpApp(
        tester,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        prefs: seededPrefs,
        surfaceSize: const Size(1440, 900),
      );
      await tester.pumpAndSettle();

      // A stretched Row under a sliver throws on layout; assert it does not.
      expect(tester.takeException(), isNull);
      expect(find.text('Start workout'), findsOneWidget);
      expect(find.text('Weekly session goal'), findsOneWidget);
      // Progress and Recent sit side by side, so both are on screen at once.
      expect(find.text('Progress'), findsWidgets);
      expect(find.text('Recent'), findsOneWidget);

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
      // The rest of the page survived the one failure. (Not the "Last
      // timer" row: it is hidden until a timer has been used.)
      expect(find.text('Recent'), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('the last-timer row stays hidden until a timer has been used',
        (tester) async {
      await pumpApp(
        tester,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        prefs: seededPrefs,
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Last timer'), findsNothing);

      await disposeApp(tester);
    });

    testWidgets('the week card shows its own error when the snapshot fails',
        (tester) async {
      await pumpApp(
        tester,
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          dashboardWeekSnapshotProvider.overrideWith(
            (ref) => throw Exception('boom'),
          ),
        ],
        prefs: seededPrefs,
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load this week'), findsOneWidget);
      // The card failing must not take the hero, or the goal bar's absence,
      // down with anything else on the page.
      expect(find.text('Start workout'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await disposeApp(tester);
    });

    testWidgets('lays the weekday strip out right-to-left in Arabic',
        (tester) async {
      await pumpApp(
        tester,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        prefs: <String, Object>{...seededPrefs, 'app_locale': 'ar'},
      );
      await tester.pumpAndSettle();

      final AppLocalizations ar = await AppLocalizations.delegate.load(
        const Locale('ar'),
      );
      final Finder monday = find.text(ar.progressWeekdayShort('monday'));
      final Finder sunday = find.text(ar.progressWeekdayShort('sunday'));
      expect(monday, findsOneWidget);
      expect(sunday, findsOneWidget);
      // Monday leads the week, so in RTL it sits to the right of Sunday.
      expect(
        tester.getCenter(monday).dx,
        greaterThan(tester.getCenter(sunday).dx),
      );
      expect(tester.takeException(), isNull);

      await disposeApp(tester);
    });
    testWidgets('the weekday strip starts on the day chosen in Settings',
        (tester) async {
      await pumpApp(
        tester,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        prefs: <String, Object>{...seededPrefs, 'week_start': 'saturday'},
      );
      await tester.pumpAndSettle();

      // The short labels repeat (S, S, T, T), so the cells are found by
      // the full day name each one announces.
      double xOf(String day) => tester
          .getCenter(
            find.byWidgetPredicate(
              (Widget widget) =>
                  widget is Semantics &&
                  (widget.properties.label?.startsWith('$day:') ?? false),
            ),
          )
          .dx;
      final List<double> xs = <double>[
        for (final String day in <String>[
          'Saturday',
          'Sunday',
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
        ])
          xOf(day),
      ];
      for (int i = 1; i < xs.length; i++) {
        expect(xs[i], greaterThan(xs[i - 1]), reason: 'cell $i');
      }
      expect(tester.takeException(), isNull);

      await disposeApp(tester);
    });

    testWidgets('right to left, the chosen first day is the rightmost cell',
        (tester) async {
      await pumpApp(
        tester,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        prefs: <String, Object>{
          ...seededPrefs,
          'app_locale': 'ar',
          'week_start': 'sunday',
        },
      );
      await tester.pumpAndSettle();

      final AppLocalizations ar = await AppLocalizations.delegate.load(
        const Locale('ar'),
      );
      double xOf(String day) =>
          tester.getCenter(find.text(ar.progressWeekdayShort(day))).dx;
      // Sunday leads, Saturday closes: right to left.
      expect(xOf('sunday'), greaterThan(xOf('monday')));
      expect(xOf('monday'), greaterThan(xOf('friday')));
      expect(xOf('friday'), greaterThan(xOf('saturday')));
      expect(tester.takeException(), isNull);

      await disposeApp(tester);
    });

    // Regression, found on a phone on 2026-11-03: the dashboard read the
    // clock in build() and stayed alive in the shell, so after days in the
    // background it greeted "Good evening" with Friday's date on a Tuesday
    // morning.
    testWidgets('greeting and date refresh when the app resumes on a new day',
        (tester) async {
      DateTime fakeNow = DateTime(2026, 10, 30, 19, 50);
      await pumpApp(
        tester,
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(() => fakeNow),
        ],
        prefs: seededPrefs,
      );
      await tester.pumpAndSettle();

      expect(find.text('Good evening'), findsOneWidget);
      expect(find.text('FRIDAY, 30 OCT'), findsOneWidget);

      fakeNow = DateTime(2026, 11, 3, 11, 37);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Good morning'), findsOneWidget);
      expect(find.text('TUESDAY, 3 NOV'), findsOneWidget);
      expect(find.text('FRIDAY, 30 OCT'), findsNothing);

      await disposeApp(tester);
    });

    testWidgets('greeting changes at noon while the app stays open',
        (tester) async {
      DateTime fakeNow = DateTime(2026, 11, 3, 11, 59, 30);
      await pumpApp(
        tester,
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(() => fakeNow),
        ],
        prefs: seededPrefs,
      );
      await tester.pumpAndSettle();
      expect(find.text('Good morning'), findsOneWidget);

      // No resume: only LocalNow's boundary timer can notice noon.
      fakeNow = DateTime(2026, 11, 3, 12, 0, 1);
      await tester.pump(const Duration(seconds: 40));
      await tester.pumpAndSettle();

      expect(find.text('Good afternoon'), findsOneWidget);
      expect(find.text('TUESDAY, 3 NOV'), findsOneWidget);

      await disposeApp(tester);
    });
  });

  group('DashboardPage with no history', () {
    late AppDatabase database;

    setUp(() => database = AppDatabase.forTesting());

    testWidgets('a new user still sees the goal at 0 and an empty strip',
        (tester) async {
      await pumpApp(
        tester,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        prefs: const <String, Object>{'exercise_seed_version': 999999},
      );
      await tester.pumpAndSettle();

      expect(find.text('Weekly session goal'), findsOneWidget);
      expect(find.text('0 / 3'), findsOneWidget);
      // Nothing trained, so no day carries a check mark.
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.text('Start workout'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      await database.close();
    });
  });
}
