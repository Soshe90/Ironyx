import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/timer_dao.dart';
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
      expect(find.text('1 / 3'), findsOneWidget);
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
      expect(find.text('1 / 3'), findsOneWidget);

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
    group('restyled home', () {
      Future<void> open(WidgetTester tester) async {
        await pumpApp(
          tester,
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          prefs: seededPrefs,
          surfaceSize: const Size(400, 1600),
        );
        await tester.pumpAndSettle();
      }

      Future<void> addWorkout(
        String id,
        DateTime startedAt, {
        required double weightKg,
        required double volumeKg,
      }) =>
          WorkoutDao(database).insertWorkout(
            WorkoutsTableCompanion.insert(
              id: id,
              startedAt: startedAt,
              endedAt: Value(startedAt.add(const Duration(minutes: 30))),
              totalVolumeKg: Value(volumeKg),
              durationSeconds: const Value(1800),
            ),
            [
              WorkoutExercisesTableCompanion.insert(
                id: '${id}_ex',
                workoutId: id,
                exerciseId: 'bench',
                orderIndex: 0,
              ),
            ],
            [
              WorkoutSetsTableCompanion.insert(
                id: '${id}_set',
                workoutExerciseId: '${id}_ex',
                setIndex: 0,
                weightKg: weightKg,
                reps: 5,
                isCompleted: const Value(true),
              ),
            ],
          );

      BoxDecoration markerOf(WidgetTester tester, String day) => tester
          .widget<Container>(
            find.byKey(ValueKey<String>('weekday-marker-$day')),
          )
          .decoration! as BoxDecoration;

      Color? segmentColour(WidgetTester tester, int index) => (tester
              .widget<AnimatedContainer>(
                find.byKey(ValueKey<String>('session-goal-segment-$index')),
              )
              .decoration! as BoxDecoration)
          .color;

      testWidgets('the start card says how long ago the last workout was',
          (tester) async {
        await open(tester);

        // The seeded workout started an hour ago: today, or yesterday if
        // this runs in the first hour of a day.
        expect(
          find.byWidgetPredicate(
            (Widget w) =>
                w is Text &&
                (w.data == 'Last workout: Today' ||
                    w.data == 'Last workout: Yesterday'),
          ),
          findsOneWidget,
        );
        expect(
          find.text('Start a session and log your sets as you go.'),
          findsNothing,
        );
        await disposeApp(tester);
      });

      testWidgets('starting from a program is a quiet second action',
          (tester) async {
        await open(tester);

        expect(
          find.widgetWithText(TextButton, 'Start from a program'),
          findsOneWidget,
        );
        expect(find.byType(OutlinedButton), findsNothing);
        expect(
          tester
              .getSize(find.widgetWithText(TextButton, 'Start from a program'))
              .height,
          greaterThanOrEqualTo(48),
        );
        await disposeApp(tester);
      });

      testWidgets('the goal is one segment per target session', (tester) async {
        await open(tester);

        final Color primary = Theme.of(
          tester.element(find.text('Weekly session goal')),
        ).colorScheme.primary;
        // Default target of three, one session done.
        expect(segmentColour(tester, 0), primary);
        expect(segmentColour(tester, 1), isNot(primary));
        expect(segmentColour(tester, 2), isNot(primary));
        expect(
          find.byKey(const ValueKey<String>('session-goal-segment-3')),
          findsNothing,
        );
        // The session count is stated once on the card, not three times.
        expect(find.text('1 / 3'), findsOneWidget);
        expect(find.text('SESSIONS'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        await disposeApp(tester);
      });

      testWidgets('more sessions than the target still fills only the target',
          (tester) async {
        final DateTime now = DateTime.now();
        for (int i = 2; i <= 5; i++) {
          await addWorkout(
            'w$i',
            now.subtract(Duration(minutes: i * 5)),
            weightKg: 60,
            volumeKg: 300,
          );
        }
        await open(tester);

        final Color primary = Theme.of(
          tester.element(find.text('Weekly session goal')),
        ).colorScheme.primary;
        expect(find.text('5 / 3'), findsOneWidget);
        for (int i = 0; i < 3; i++) {
          expect(segmentColour(tester, i), primary, reason: 'segment $i');
        }
        expect(
          find.byKey(const ValueKey<String>('session-goal-segment-3')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await disposeApp(tester);
      });

      testWidgets('the day strip tells today, past and future days apart',
          (tester) async {
        // Wednesday 4 November 2026, in a Monday-first week with nothing
        // logged: two past days, today, four to come. The group's seeded
        // database is closed first; this test wants an empty one, and two
        // open at once is what drift warns about.
        await database.close();
        final AppDatabase empty = AppDatabase.forTesting();
        await pumpApp(
          tester,
          overrides: [
            appDatabaseProvider.overrideWithValue(empty),
            clockProvider.overrideWithValue(() => DateTime(2026, 11, 4, 10)),
          ],
          prefs: seededPrefs,
          surfaceSize: const Size(400, 1600),
        );
        await tester.pumpAndSettle();
        final ColorScheme scheme = Theme.of(
          tester.element(find.text('Weekly session goal')),
        ).colorScheme;

        for (final String past in <String>['monday', 'tuesday']) {
          final BoxDecoration d = markerOf(tester, past);
          expect(d.color, scheme.surfaceContainerHighest, reason: past);
          expect(d.border, isNull, reason: past);
        }
        final BoxDecoration today = markerOf(tester, 'wednesday');
        expect(today.color, isNull);
        expect((today.border! as Border).top.color, scheme.primary);
        expect((today.border! as Border).top.width, 2);
        for (final String future in <String>[
          'thursday',
          'friday',
          'saturday',
          'sunday',
        ]) {
          final BoxDecoration d = markerOf(tester, future);
          expect(d.color, isNull, reason: future);
          expect(
            (d.border! as Border).top.color,
            scheme.outlineVariant,
            reason: future,
          );
        }

        // Only today's cell says so to a screen reader.
        expect(
          find.byWidgetPredicate(
            (Widget w) =>
                w is Semantics &&
                (w.properties.label?.endsWith('. Today') ?? false),
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (Widget w) =>
                w is Semantics &&
                (w.properties.label?.startsWith('Wednesday:') ?? false) &&
                (w.properties.label?.endsWith('. Today') ?? false),
          ),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(Duration.zero);
        await empty.close();
      });

      testWidgets('the estimate is rounded, as it is on Progress',
          (tester) async {
        // 62.5 kg x 5 is an Epley estimate of 72.92 kg.
        await addWorkout(
          'heavier',
          DateTime.now().subtract(const Duration(minutes: 10)),
          weightKg: 62.5,
          volumeKg: 312.5,
        );
        await open(tester);

        expect(find.text('73 kg'), findsOneWidget);
        expect(find.textContaining('72.9'), findsNothing);
        await disposeApp(tester);
      });

      testWidgets('last week sits under the volume it is compared with',
          (tester) async {
        await addWorkout(
          'lastWeek',
          DateTime.now().subtract(const Duration(days: 7)),
          weightKg: 40,
          volumeKg: 200,
        );
        await open(tester);

        expect(find.text('Last week 200 kg'), findsOneWidget);
        expect(find.text('LAST WEEK'), findsNothing);
        await disposeApp(tester);
      });

      testWidgets('progress is four tiles, the streak among them',
          (tester) async {
        await open(tester);

        for (final String title in <String>[
          'EST. 1RM',
          'BODY WEIGHT',
          'STREAK',
          'AVERAGE DURATION',
        ]) {
          expect(find.text(title), findsOneWidget, reason: title);
        }
        expect(find.text('1 wk'), findsOneWidget);
        // Two rows of two: the streak sits beside the average duration.
        expect(
          tester.getTopLeft(find.text('STREAK')).dy,
          tester.getTopLeft(find.text('AVERAGE DURATION')).dy,
        );
        expect(
          tester.getTopLeft(find.text('STREAK')).dy,
          greaterThan(tester.getTopLeft(find.text('EST. 1RM')).dy),
        );
        await disposeApp(tester);
      });

      testWidgets('a timer shorter than a minute shows its seconds',
          (tester) async {
        final DateTime started =
            DateTime.now().subtract(const Duration(minutes: 5));
        await TimerDao(database).insertSession(
          TimerSessionsTableCompanion.insert(
            id: 't1',
            startedAt: started,
            endedAt: Value(started.add(const Duration(seconds: 20))),
            plannedDurationSeconds: 240,
            actualDurationSeconds: const Value(20),
            presetName: 'Tabata',
            totalIntervals: 8,
          ),
          const <TimerIntervalsTableCompanion>[],
        );
        await open(tester);

        expect(find.text('Last timer'), findsOneWidget);
        expect(find.text('00:20'), findsOneWidget);
        expect(find.text('0m'), findsNothing);
        await disposeApp(tester);
      });
    });

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
      // With no workout to date, the start card keeps its invitation.
      expect(
        find.text('Start a session and log your sets as you go.'),
        findsOneWidget,
      );
      expect(find.textContaining('Last workout:'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      await database.close();
    });
  });
}
