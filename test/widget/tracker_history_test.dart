import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/program_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/formatters/week_start.dart';
import 'package:ironyx/core/router/routes.dart';
import 'package:ironyx/core/services/clock.dart';
import 'package:ironyx/core/services/program_import_service.dart';
import 'package:ironyx/core/widgets/app_card.dart';
import 'package:ironyx/features/programs/domain/program_providers.dart';
import 'package:ironyx/features/tracker/domain/active_workout_notifier.dart';
import 'package:ironyx/features/tracker/presentation/tracker_page.dart';
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
    DateTime Function()? clock,
    List<dynamic> overrides = const <dynamic>[],
  }) async {
    await pumpApp(
      tester,
      initialLocation: Routes.tracker,
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        if (clock != null) clockProvider.overrideWithValue(clock),
        ...overrides,
      ],
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

  // The tab stays alive in the shell, so the app can outlive the day and
  // month it was opened in (seen on a phone on 2026-11-03 on the dashboard,
  // which had the same pattern).
  group('across a day change', () {
    Future<void> resume(WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    }

    HistoryCalendar calendar(WidgetTester tester) =>
        tester.widget<HistoryCalendar>(find.byType(HistoryCalendar));

    testWidgets('the calendar moves on to the new month it was showing',
        (tester) async {
      DateTime fakeNow = DateTime(2026, 10, 31, 23);
      await pumpTracker(
        tester,
        surfaceSize: const Size(1400, 2000),
        clock: () => fakeNow,
      );
      await tester.tap(find.byTooltip('Show calendar'));
      await tester.pump();
      expect(calendar(tester).visibleMonth, DateTime(2026, 10));
      expect(calendar(tester).today, DateTime(2026, 10, 31));

      fakeNow = DateTime(2026, 11, 1, 8);
      await resume(tester);

      expect(calendar(tester).visibleMonth, DateTime(2026, 11));
      expect(calendar(tester).today, DateTime(2026, 11, 1));

      await disposeTracker(tester);
    });

    testWidgets('a month the user browsed back to stays put', (tester) async {
      DateTime fakeNow = DateTime(2026, 10, 31, 23);
      await pumpTracker(
        tester,
        surfaceSize: const Size(1400, 2000),
        clock: () => fakeNow,
      );
      await tester.tap(find.byTooltip('Show calendar'));
      await tester.pump();
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pump();
      expect(calendar(tester).visibleMonth, DateTime(2026, 9));

      fakeNow = DateTime(2026, 11, 1, 8);
      await resume(tester);

      expect(calendar(tester).visibleMonth, DateTime(2026, 9));
      expect(calendar(tester).today, DateTime(2026, 11, 1));

      await disposeTracker(tester);
    });

    testWidgets('the next-month limit follows the given today, not the clock',
        (tester) async {
      Future<IconButton> nextButton(DateTime visibleMonth) async {
        await pumpWidgetUnderTest(
          tester,
          HistoryCalendar(
            visibleMonth: visibleMonth,
            today: DateTime(2026, 11, 3),
            weekStart: WeekStart.monday,
            markedDates: const <DateTime>{},
            onMonthChanged: (_) {},
            onDayTap: (_) {},
          ),
        );
        return tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.chevron_right),
        );
      }

      expect((await nextButton(DateTime(2026, 11))).onPressed, isNull);
      expect((await nextButton(DateTime(2026, 10))).onPressed, isNotNull);

      // This test never boots the app, but setUp opened a database for it;
      // leaving it open makes Drift warn in every later test.
      await database.close();
    });

    testWidgets("yesterday's workout stops being highlighted as today",
        (tester) async {
      // A fixed past date, so the real clock can never make it "today".
      final DateTime start = DateTime(2026, 11, 2, 10);
      await WorkoutDao(database).insertWorkout(
        WorkoutsTableCompanion.insert(
          id: 'w-nov2',
          startedAt: start,
          endedAt: Value(start.add(const Duration(minutes: 40))),
          durationSeconds: const Value(2400),
          totalVolumeKg: const Value(500),
        ),
        [
          WorkoutExercisesTableCompanion.insert(
            id: 'w-nov2_a',
            workoutId: 'w-nov2',
            exerciseId: 'my-bench',
            orderIndex: 0,
          ),
        ],
        const [],
      );
      DateTime fakeNow = DateTime(2026, 11, 2, 18);
      await pumpTracker(
        tester,
        surfaceSize: const Size(1400, 2000),
        clock: () => fakeNow,
      );
      final Color primary =
          Theme.of(tester.element(find.byType(Scaffold).first))
              .colorScheme
              .primary;
      // The date tile's day number is primary-coloured only for today.
      int highlightedDayTwo() => tester
          .widgetList<Text>(find.text('2'))
          .where((Text t) => t.style?.color == primary)
          .length;

      expect(highlightedDayTwo(), 1);

      fakeNow = DateTime(2026, 11, 3, 7);
      await resume(tester);

      expect(highlightedDayTwo(), 0);

      await disposeTracker(tester);
    });
  });

  testWidgets('a workout with no load shows its sets, not 0 kg',
      (tester) async {
    final DateTime at = DateTime.now().subtract(const Duration(days: 2));
    await WorkoutDao(database).insertWorkout(
      WorkoutsTableCompanion.insert(
        id: 'bodyweight',
        startedAt: at,
        endedAt: Value(at.add(const Duration(minutes: 20))),
        totalVolumeKg: const Value(0),
      ),
      [
        WorkoutExercisesTableCompanion.insert(
          id: 'bw_a',
          workoutId: 'bodyweight',
          exerciseId: 'my-row',
          orderIndex: 0,
        ),
      ],
      [
        for (int i = 0; i < 4; i++)
          WorkoutSetsTableCompanion.insert(
            id: 'bw_s$i',
            workoutExerciseId: 'bw_a',
            setIndex: i,
            weightKg: 0,
            reps: 12,
            // One left unticked: only completed sets count.
            isCompleted: Value(i < 3),
          ),
      ],
    );
    await pumpTracker(tester);

    expect(find.text('3 sets'), findsOneWidget);
    expect(find.text('0 kg'), findsNothing);
    // The loaded workout keeps its kilograms.
    expect(find.text('1,200 kg'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (Widget w) =>
            w is Semantics &&
            (w.properties.label?.endsWith(', 3 sets') ?? false),
      ),
      findsOneWidget,
    );
    await disposeTracker(tester);
  });

  group('a calendar day', () {
    // Pinned to Tue 10 Nov 2026, so the calendar opens on November whatever
    // the real date; the seeded workout (three hours before the real now)
    // does not matter to these days.
    DateTime fakeNow() => DateTime(2026, 11, 10, 12);

    Future<void> add(String id, DateTime at, double kg, String exercise) =>
        WorkoutDao(database).insertWorkout(
          WorkoutsTableCompanion.insert(
            id: id,
            startedAt: at,
            endedAt: Value(at.add(const Duration(minutes: 30))),
            totalVolumeKg: Value(kg),
          ),
          [
            WorkoutExercisesTableCompanion.insert(
              id: '${id}_a',
              workoutId: id,
              exerciseId: exercise,
              orderIndex: 0,
            ),
          ],
          const [],
        );

    Future<void> tapDay(WidgetTester tester, int day) async {
      await tester.tap(find.byTooltip('Show calendar'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(HistoryCalendar),
          matching: find.text('$day'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('with one workout opens it', (tester) async {
      await add('nov6', DateTime(2026, 11, 6, 18), 700, 'my-row');
      await pumpTracker(tester, clock: fakeNow);
      await tapDay(tester, 6);

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(HistoryCalendar), findsNothing,
          reason: 'on the workout page now');
      expect(find.text('Chest-Supported Row'), findsWidgets);
      await disposeTracker(tester);
    });

    testWidgets('with several asks which, and opens the one chosen',
        (tester) async {
      await add('morning', DateTime(2026, 11, 5, 8), 1100, 'my-bench');
      await add('evening', DateTime(2026, 11, 5, 18), 800, 'my-row');
      await pumpTracker(tester, clock: fakeNow);
      await tapDay(tester, 5);

      final Finder sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(
            of: sheet, matching: find.textContaining('Workouts on')),
        findsOneWidget,
      );
      expect(find.descendant(of: sheet, matching: find.text('1,100 kg')),
          findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('800 kg')),
          findsOneWidget);

      // The morning one, which tapping the day could not reach before.
      await tester.tap(
        find.descendant(of: sheet, matching: find.text('1,100 kg')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(HistoryCalendar), findsNothing);
      expect(find.text('Incline Press'), findsWidgets);
      await disposeTracker(tester);
    });
  });

  testWidgets('both imports are in one app-bar menu', (tester) async {
    await pumpTracker(tester);

    expect(find.text('Import workouts from XLSX'), findsNothing);
    expect(find.byTooltip('History options'), findsNothing);
    expect(find.byTooltip('Program options'), findsNothing);
    final Finder menu = find.descendant(
      of: find.byType(AppBar),
      matching: find.byTooltip('Import'),
    );
    expect(menu, findsOneWidget);

    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('Import programs from CSV'), findsOneWidget);
    expect(find.text('Import workouts from XLSX'), findsOneWidget);

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

  testWidgets(
      'CSV program import is reachable when programs already exist, '
      'not only from the no-programs card', (tester) async {
    await const ProgramImportService().apply(
      database,
      await const ProgramImportService().parse(
        'program,day,exercise,sets\nStrength Block,Day 1,Incline Press,3\n',
        database,
      ),
    );
    await pumpTracker(tester);

    expect(find.text('Strength Block'), findsOneWidget);
    expect(find.text('Import programs from CSV'), findsNothing);
    await tester.tap(find.byTooltip('Import'));
    await tester.pumpAndSettle();
    expect(find.text('Import programs from CSV'), findsOneWidget);

    await disposeTracker(tester);
  });

  group('programs row', () {
    Future<void> importPrograms(int count) async {
      final StringBuffer csv = StringBuffer('program,day,exercise,sets\n');
      for (int i = 1; i <= count; i++) {
        csv.writeln('Block $i,Day 1,Incline Press,3');
        if (i.isEven) csv.writeln('Block $i,Day 2,Chest-Supported Row,3');
      }
      await const ProgramImportService().apply(
        database,
        await const ProgramImportService().parse(csv.toString(), database),
      );
    }

    testWidgets('programs sit side by side, so history stays near the top',
        (tester) async {
      await importPrograms(3);
      await pumpTracker(tester, surfaceSize: const Size(400, 800));

      final double first = tester.getTopLeft(find.text('Block 1')).dy;
      expect(tester.getTopLeft(find.text('Block 2')).dy, first);
      expect(tester.getTopLeft(find.text('Block 3')).dy, first);
      expect(
        tester.getTopLeft(find.text('Block 2')).dx,
        greaterThan(tester.getTopLeft(find.text('Block 1')).dx),
      );
      // As a column, three programs put this heading past the middle of a
      // phone screen; in a row it is in the upper half whatever the count.
      expect(tester.getTopLeft(find.text('History')).dy, lessThan(400));
      // The seeded workout's row is on the first screen. (At this width
      // its title may show one exercise and count the other.)
      expect(
        find.textContaining('Incline Press').hitTestable(),
        findsOneWidget,
      );

      await disposeTracker(tester);
    });

    testWidgets('more programs than fit are reached by swiping the row',
        (tester) async {
      await importPrograms(8);
      await pumpTracker(tester, surfaceSize: const Size(400, 800));
      final double historyBefore = tester.getTopLeft(find.text('History')).dy;

      // The row builds its cards as they come into view.
      expect(find.text('Block 8'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Block 8'),
        200,
        scrollable: find.descendant(
          of: find.byWidgetPredicate(
            (Widget w) => w is ListView && w.scrollDirection == Axis.horizontal,
          ),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Block 8').hitTestable(), findsOneWidget);
      // Sideways only: the page itself has not moved.
      expect(tester.getTopLeft(find.text('History')).dy, historyBefore);
      expect(tester.takeException(), isNull);

      await disposeTracker(tester);
    });

    testWidgets('a card names the program and its days, and opens it',
        (tester) async {
      await importPrograms(2);
      await pumpTracker(tester, surfaceSize: const Size(400, 800));

      // What each card is announced as.
      Finder announced(String label) => find.byWidgetPredicate(
            (Widget w) => w is Semantics && w.properties.label == label,
          );
      expect(announced('Block 1, 1 day'), findsOneWidget);
      expect(announced('Block 2, 2 days'), findsOneWidget);
      final Finder card = find.ancestor(
        of: find.text('Block 2'),
        matching: find.byType(AppCard),
      );
      expect(
        find.descendant(of: card, matching: find.text('2 days')),
        findsOneWidget,
      );

      await tester.tap(find.text('Block 2'));
      await tester.pumpAndSettle();
      // The program's own page: its two days are listed.
      expect(find.text('Day 1'), findsOneWidget);
      expect(find.text('Day 2'), findsOneWidget);

      await disposeTracker(tester);
    });

    testWidgets('programs that fail to load say so, with a retry',
        (tester) async {
      await pumpTracker(
        tester,
        overrides: [
          programSummariesProvider.overrideWith(
            (ref) => Stream<List<ProgramSummary>>.error(Exception('boom')),
          ),
        ],
      );
      // Riverpod retries a failed provider before reporting the error, and
      // the row shows nothing while it does. Let the retries run out.
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(find.text('Failed to load programs'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // Not taken for an empty list.
      expect(
        find.text('Reusable day templates to start a session from'),
        findsNothing,
      );
      expect(find.text('No programs yet'), findsNothing);
      // The rest of the tab is still there.
      expect(find.text('History'), findsOneWidget);
      await disposeTracker(tester);
    });

    testWidgets('a program that fails to load still opens, on its error',
        (tester) async {
      await importPrograms(1);
      await pumpTracker(
        tester,
        surfaceSize: const Size(400, 800),
        overrides: [
          programDetailProvider.overrideWith(
            (ref, String id) => Future<ProgramDetail?>.error(Exception('x')),
          ),
        ],
      );

      await tester.tap(find.text('Block 1'));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load program'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeTracker(tester);
    });

    testWidgets('a double tap on a card opens the program once',
        (tester) async {
      await importPrograms(1);
      await pumpTracker(tester, surfaceSize: const Size(400, 800));

      await tester.tap(find.text('Block 1'));
      await tester.tap(find.text('Block 1'));
      await tester.pumpAndSettle();
      expect(find.text('Day 1'), findsOneWidget);

      // One back is the Workouts tab again, not a second copy of the page.
      final NavigatorState navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('Day 1'), findsNothing);
      expect(find.text('Start workout'), findsOneWidget);
      await disposeTracker(tester);
    });

    testWidgets('the explanation shows only while there are no programs',
        (tester) async {
      const String explanation =
          'Reusable day templates to start a session from';
      await pumpTracker(tester);
      expect(find.text(explanation), findsOneWidget);
      await disposeTracker(tester);
    });

    testWidgets('with programs the heading has no second line', (tester) async {
      await importPrograms(1);
      await pumpTracker(tester);

      expect(
        find.text('Reusable day templates to start a session from'),
        findsNothing,
      );
      expect(find.text('Programs'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
      await disposeTracker(tester);
    });

    testWidgets('a long name wraps inside its card at a large text size',
        (tester) async {
      await const ProgramImportService().apply(
        database,
        await const ProgramImportService().parse(
          'program,day,exercise,sets\n'
          'Intermediate Upper Lower Hypertrophy Block Phase Two,Day 1,'
          'Incline Press,3\n',
          database,
        ),
      );
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpTracker(tester, surfaceSize: const Size(400, 800));

      expect(tester.takeException(), isNull);
      final Finder name = find.textContaining('Intermediate Upper Lower');
      final Rect card = tester.getRect(
        find.ancestor(of: name, matching: find.byType(AppCard)),
      );
      expect(tester.getRect(name).bottom, lessThan(card.bottom));
      expect(tester.getRect(find.text('1 day')).bottom, lessThan(card.bottom));

      // The month heading's summary used to run off the screen here; it
      // stays inside, on a line of its own if it has to.
      final Rect summary = tester.getRect(find.textContaining('1 workout'));
      expect(summary.left, greaterThanOrEqualTo(0));
      expect(summary.right, lessThanOrEqualTo(400));

      await disposeTracker(tester);
    });

    testWidgets('your programs come first, then the built-in, by name',
        (tester) async {
      final DateTime at = DateTime(2026, 1, 1);
      for (final (String id, String name) in <(String, String)>[
        ('builtin_ppl', 'Push / Pull / Legs'),
        ('builtin_full_body', 'Full Body'),
      ]) {
        await database.into(database.programsTable).insert(
              ProgramsTableCompanion.insert(
                id: id,
                name: name,
                createdAt: at,
                updatedAt: at,
                isBuiltIn: const Value(true),
              ),
            );
      }
      await const ProgramImportService().apply(
        database,
        await const ProgramImportService().parse(
          'program,day,exercise,sets\n'
          'Zeta,Day 1,Incline Press,3\n'
          'alpha,Day 1,Incline Press,3\n',
          database,
        ),
      );
      await pumpTracker(tester, surfaceSize: const Size(1400, 800));

      final List<String> order = <String>[
        'alpha',
        'Zeta',
        'Full Body',
        'Push / Pull / Legs',
      ];
      for (int i = 1; i < order.length; i++) {
        expect(
          tester.getCenter(find.text(order[i])).dx,
          greaterThan(tester.getCenter(find.text(order[i - 1])).dx),
          reason: '${order[i - 1]} before ${order[i]}',
        );
      }
      await disposeTracker(tester);
    });

    testWidgets('in Arabic the first program is on the right', (tester) async {
      await importPrograms(2);
      await pumpApp(
        tester,
        initialLocation: Routes.tracker,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        prefs: const <String, Object>{
          'exercise_seed_version': 999999,
          'program_seed_version': 999999,
          'app_locale': 'ar',
        },
        surfaceSize: const Size(400, 800),
        awaitDatabase: true,
      );
      await tester.pump();

      expect(
        tester.getCenter(find.text('Block 1')).dx,
        greaterThan(tester.getCenter(find.text('Block 2')).dx),
      );
      await disposeTracker(tester);
    });
  });

  testWidgets('typing in an open workout does not rebuild the tab',
      (tester) async {
    await pumpTracker(tester);
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(TrackerPage)),
    );
    final ActiveWorkoutNotifier notifier =
        container.read(activeWorkoutProvider.notifier);
    await tester.runAsync(() async {
      await notifier.start();
      await notifier.addExercise(exerciseId: 'my-bench', name: 'Incline Press');
    });
    await tester.pumpAndSettle();
    expect(find.text('Resume workout · 1 exercise'), findsOneWidget);

    final List<String> rebuilt = <String>[];
    debugOnRebuildDirtyWidget = (Element element, bool builtOnce) =>
        rebuilt.add(element.widget.runtimeType.toString());
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    final draft = container.read(activeWorkoutProvider)!;
    final String exerciseId = draft.exercises.single.id;
    final String setId = draft.exercises.single.sets.first.id;
    await tester.runAsync(() async {
      await notifier.updateSet(exerciseId, setId, weightKg: 60);
      await notifier.updateSet(exerciseId, setId, reps: 8);
    });
    await tester.pumpAndSettle();

    expect(rebuilt, isNot(contains('TrackerPage')),
        reason: 'every keystroke rebuilt the page and its history');
    expect(rebuilt, isNot(contains('_HistorySliverList')));

    // An exercise added does reach the banner.
    rebuilt.clear();
    await tester.runAsync(
      () => notifier.addExercise(exerciseId: 'my-row', name: 'Row'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Resume workout · 2 exercises'), findsOneWidget);
    expect(rebuilt, isNot(contains('TrackerPage')));

    await tester.runAsync(notifier.discard);
    await disposeTracker(tester);
  });

  testWidgets('an open workout is resumed from a filled button',
      (tester) async {
    await pumpTracker(tester);
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(TrackerPage)),
    );
    final ActiveWorkoutNotifier notifier =
        container.read(activeWorkoutProvider.notifier);
    await tester.runAsync(notifier.start);
    await tester.pumpAndSettle();

    // No exercises yet: the action alone.
    final Finder resume = find.widgetWithText(FilledButton, 'Resume workout');
    expect(resume, findsOneWidget);
    expect(
      find.descendant(of: resume, matching: find.byIcon(Icons.play_arrow)),
      findsOneWidget,
    );
    expect(find.text('Start workout'), findsNothing);
    expect(find.text('Workout in progress'), findsNothing);

    await tester.tap(resume);
    await tester.pumpAndSettle();
    expect(find.byType(TrackerPage), findsNothing, reason: 'on the workout');

    await tester.runAsync(notifier.discard);
    await disposeTracker(tester);
  });

  testWidgets('the start button carries the same plus as the dashboard',
      (tester) async {
    await pumpTracker(tester);

    final Finder start = find.widgetWithText(FilledButton, 'Start workout');
    expect(
      find.descendant(of: start, matching: find.byIcon(Icons.add)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: start, matching: find.byIcon(Icons.play_arrow)),
      findsNothing,
    );
    await disposeTracker(tester);
  });

  testWidgets('with no programs the empty card keeps its own import button',
      (tester) async {
    await pumpTracker(tester);

    expect(find.text('No programs yet'), findsOneWidget);
    expect(find.byTooltip('Import programs from CSV'), findsOneWidget);
    expect(find.byTooltip('Import'), findsOneWidget);

    await disposeTracker(tester);
  });

  testWidgets('with no history there is no calendar toggle, but import stays',
      (tester) async {
    await WorkoutDao(database).deleteWorkout('w1');
    await pumpTracker(tester);

    expect(find.text('No workouts yet'), findsOneWidget);
    expect(find.byTooltip('Show calendar'), findsNothing);
    expect(find.byTooltip('Import'), findsOneWidget);

    await disposeTracker(tester);
  });
}
