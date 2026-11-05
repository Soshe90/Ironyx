import 'package:drift/drift.dart' show Value;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/body_metrics_dao.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/muscle_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/widgets/app_card.dart';
import 'package:ironyx/core/widgets/segmented_pills.dart';
import 'package:ironyx/features/progress/domain/progress_providers.dart';
import 'package:ironyx/features/progress/presentation/widgets/progress_visuals.dart';

import '../helpers/pump_app.dart';
import '../helpers/stub_seeders.dart';

/// The Progress page's pinned controls and its chart cards.
///
/// Twelve weekly sessions are seeded on purpose. The effort, rest, session
/// volume and weekly-by-muscle sections used to be tables that printed the
/// first eight (or twelve) rows of an oldest-first query, so with more than
/// eight sessions the newest never appeared. Every "newest" assertion below
/// fails against that.
void main() {
  late AppDatabase database;

  /// How many weekly sessions are inside the default three-month range.
  const int sessions = 12;

  setUp(() async {
    database = AppDatabase.forTesting();
    await MuscleDao(database).upsertAll([
      MusclesTableCompanion.insert(
          id: 'chest', name: 'chest', displayName: 'Chest'),
      MusclesTableCompanion.insert(
          id: 'back', name: 'back', displayName: 'Back'),
    ]);
    final ExerciseDao exercises = ExerciseDao(database);
    // Real catalogue slugs, so the Arabic names resolve.
    for (final (
          String id,
          String slug,
          String name,
          String pattern,
          String muscle
        ) in <(String, String, String, String, String)>[
      (
        'bench',
        'barbell-bench-press',
        'Barbell Bench Press',
        'horizontalPush',
        'chest'
      ),
      ('row', 'seated-cable-row', 'Seated Cable Row', 'horizontalPull', 'back'),
    ]) {
      await exercises.upsertExercises([
        ExercisesTableCompanion.insert(
          id: id,
          slug: slug,
          name: name,
          category: 'strength',
          difficulty: 'intermediate',
          movementPattern: pattern,
          seedVersion: 1,
        ),
      ]);
      await exercises.replaceMuscleLinks(id, [
        ExerciseMusclesTableCompanion.insert(
          id: '${id}_m',
          exerciseId: id,
          muscleId: muscle,
          role: 'primary',
        ),
      ]);
    }

    final WorkoutDao workouts = WorkoutDao(database);
    final DateTime now = DateTime.now();

    Future<void> session(
      String id,
      DateTime startedAt, {
      required double benchKg,
      required double rowKg,
      int? rpeTimes10,
      int? restSeconds,
    }) =>
        workouts.insertWorkout(
          WorkoutsTableCompanion.insert(
            id: id,
            startedAt: startedAt,
            endedAt: Value(startedAt.add(const Duration(minutes: 45))),
            totalVolumeKg: Value(benchKg * 5 + rowKg * 10),
          ),
          [
            WorkoutExercisesTableCompanion.insert(
              id: '${id}_bench',
              workoutId: id,
              exerciseId: 'bench',
              orderIndex: 0,
            ),
            WorkoutExercisesTableCompanion.insert(
              id: '${id}_row',
              workoutId: id,
              exerciseId: 'row',
              orderIndex: 1,
            ),
          ],
          [
            WorkoutSetsTableCompanion.insert(
              id: '${id}_bench_s',
              workoutExerciseId: '${id}_bench',
              setIndex: 0,
              weightKg: benchKg,
              reps: 5,
              isCompleted: const Value(true),
              rpeTimes10: Value(rpeTimes10),
              restSeconds: Value(restSeconds),
            ),
            WorkoutSetsTableCompanion.insert(
              id: '${id}_row_s',
              workoutExerciseId: '${id}_row',
              setIndex: 0,
              weightKg: rowKg,
              reps: 10,
              isCompleted: const Value(true),
            ),
          ],
        );

    // Oldest first; the newest (i = 11) is an hour old and the heaviest.
    for (int i = 0; i < sessions; i++) {
      await session(
        'w$i',
        now.subtract(Duration(days: (sessions - 1 - i) * 7, hours: 1)),
        benchKg: 40.0 + i * 2,
        rowKg: 30.0 + i,
        rpeTimes10: 60 + i,
        restSeconds: 60 + i * 5,
      );
    }
    // Two lighter sessions in the three months before, so both lifts have
    // a previous best and the strength insight has something to say.
    for (final int daysAgo in <int>[100, 107]) {
      await session(
        'old$daysAgo',
        now.subtract(Duration(days: daysAgo)),
        benchKg: 35,
        rowKg: 25,
      );
    }

    // Two identical weigh-ins: a series with no spread at all.
    final BodyMetricsDao metrics = BodyMetricsDao(database);
    for (final int daysAgo in <int>[10, 3]) {
      await metrics.upsert(
        BodyMetricsTableCompanion.insert(
          id: 'bm$daysAgo',
          date: now.subtract(Duration(days: daysAgo)),
          weightKg: 80,
        ),
      );
    }
  });

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await database.close();
  }

  Future<void> pumpProgress(
    WidgetTester tester, {
    Map<String, Object> prefs = const <String, Object>{},
  }) async {
    await pumpApp(
      tester,
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        ...stubSeeders(),
      ],
      initialLocation: '/progress',
      prefs: prefs,
      surfaceSize: const Size(400, 800),
    );
    await tester.pumpAndSettle();
  }

  /// A few frames: enough for a switch, a query and the chart's own
  /// animation, without `pumpAndSettle` waiting on a loading shimmer.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  ScrollController controllerOf(WidgetTester tester) =>
      tester.widget<Scrollable>(find.byType(Scrollable).first).controller!;

  final Finder tabs =
      find.byWidgetPredicate((Widget w) => w is ProgressChapterTabs);
  Finder tab(String label) =>
      find.descendant(of: tabs, matching: find.text(label));
  Finder heading(String label) => find.descendant(
        of: find.byType(ProgressChapter),
        matching: find.text(label),
      );
  String? activeChapter(WidgetTester tester) {
    final Object? active =
        (tester.widget(tabs) as ProgressChapterTabs<Object?>).active;
    return active?.toString().split('.').last;
  }

  /// The in-card switch that offers [label], and the card around it.
  Finder switchOption(String label) => find.descendant(
        of: find.byWidgetPredicate(
          (Widget w) => w is SegmentedPills && w.segments.length == 2,
        ),
        matching: find.text(label),
      );
  Finder cardOf(Finder inside) =>
      find.ancestor(of: inside, matching: find.byType(AppCard));

  Future<void> tapInPage(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await settle(tester);
    await tester.tap(finder);
    await settle(tester);
  }

  group('pinned controls', () {
    testWidgets('the range stays in reach after scrolling, and still works',
        (tester) async {
      await pumpProgress(tester);
      controllerOf(tester).jumpTo(1500);
      await tester.pump();

      final Finder oneMonth = find.descendant(
        of: find.byType(SegmentedPills<ProgressRange>),
        matching: find.text('1M'),
      );
      expect(oneMonth.hitTestable(), findsOneWidget);

      await tester.tap(oneMonth);
      await settle(tester);

      expect(find.text('LAST 30 DAYS'), findsOneWidget);
      expect(find.text('LAST 90 DAYS'), findsNothing);
      await disposeApp(tester);
    });

    testWidgets('no chapter is marked at the top of the page', (tester) async {
      await pumpProgress(tester);

      expect(activeChapter(tester), isNull);
      for (final String label in <String>[
        'Strength',
        'Volume',
        'Habits',
        'Body',
      ]) {
        expect(tab(label), findsOneWidget);
      }
      await disposeApp(tester);
    });

    testWidgets('tapping a tab scrolls its chapter to the top and marks it',
        (tester) async {
      await pumpProgress(tester);

      await tester.tap(tab('Habits'));
      await tester.pumpAndSettle();

      expect(activeChapter(tester), 'habits');
      final double belowTabs = tester.getBottomLeft(tabs).dy;
      final double headingTop = tester.getTopLeft(heading('Habits')).dy;
      expect(headingTop, greaterThanOrEqualTo(belowTabs));
      expect(headingTop - belowTabs, lessThan(80));
      await disposeApp(tester);
    });

    testWidgets('the tabs follow the reader down and back up', (tester) async {
      await pumpProgress(tester);
      final ScrollController controller = controllerOf(tester);

      // Bring the Volume heading to the top of the scroll view.
      final double viewportTop = tester.getBottomLeft(tabs).dy;
      controller.jumpTo(
        tester.getTopLeft(heading('Volume')).dy - viewportTop,
      );
      await tester.pump();
      expect(activeChapter(tester), 'volume');

      // The last chapter is short; the end of the page counts as reading it.
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(activeChapter(tester), 'body');

      controller.jumpTo(0);
      await tester.pump();
      expect(activeChapter(tester), isNull);
      await disposeApp(tester);
    });

    testWidgets('a tab says whether it is the chapter being read',
        (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpProgress(tester);
      await tester.tap(tab('Volume'));
      await tester.pumpAndSettle();

      SemanticsNode node(String label) => tester.getSemantics(
            find.descendant(of: tabs, matching: find.bySemanticsLabel(label)),
          );
      expect(
        node('Volume'),
        matchesSemantics(
          label: 'Volume',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      expect(
        node('Body'),
        matchesSemantics(
          label: 'Body',
          isButton: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
      await disposeApp(tester);
    });
  });

  group('lift chart', () {
    testWidgets('switching to volume plots every session, newest included',
        (tester) async {
      await pumpProgress(tester);
      await tapInPage(tester, switchOption('Volume'));

      final Finder card = cardOf(switchOption('Volume'));
      // The newest session: (40 + 11 x 2) kg x 5 reps.
      expect(
        find.descendant(of: card, matching: find.text('310 kg')),
        findsOneWidget,
      );
      final LineChart chart = tester.widget<LineChart>(
        find.descendant(of: card, matching: find.byType(LineChart)),
      );
      final List<FlSpot> spots = chart.data.lineBarsData.single.spots;
      expect(spots, hasLength(sessions));
      expect(spots.first.y, 200);
      expect(spots.last.y, 310);

      // And back again: the switch is a view of the same card, not a route.
      await tapInPage(tester, switchOption('Est. 1RM'));
      expect(
        find.descendant(of: card, matching: find.textContaining('/month')),
        findsOneWidget,
      );
      await disposeApp(tester);
    });
  });

  group('effort and recovery', () {
    testWidgets('effort is a chart of every session with its average',
        (tester) async {
      await pumpProgress(tester);
      await tester.ensureVisible(switchOption('Effort'));
      await settle(tester);

      final Finder card = cardOf(switchOption('Effort'));
      // Mean of 6.0 to 7.1.
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining(RegExp(r'^RPE 6\.[56] average$')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('12 sessions')),
        findsOneWidget,
      );
      final List<FlSpot> spots = tester
          .widget<LineChart>(
            find.descendant(of: card, matching: find.byType(LineChart)),
          )
          .data
          .lineBarsData
          .single
          .spots;
      expect(spots, hasLength(sessions));
      expect(spots.last.y, moreOrLessEquals(7.1, epsilon: 0.001));
      await disposeApp(tester);
    });

    testWidgets('a screen reader gets the chart as a sentence', (tester) async {
      // The tables this chart replaced were text. Its points are drawn on
      // a canvas, so the range and the extremes are said in words.
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpProgress(tester);
      // The chart itself has to be on screen: what is scrolled out of view
      // is not in the semantics tree.
      await tester.ensureVisible(
        find.descendant(
          of: cardOf(switchOption('Effort')),
          matching: find.byType(LineChart),
        ),
      );
      await settle(tester);

      expect(
        find.bySemanticsLabel(
          RegExp(
            r'^Chart from .+ to .+\. Latest: RPE 7\.1 · 720 kg\. '
            r'Lowest: RPE 6\.0 · 500 kg\. Highest: RPE 7\.1 · 720 kg\.$',
          ),
        ),
        findsOneWidget,
      );
      semantics.dispose();
      await disposeApp(tester);
    });

    testWidgets('rest shows its average and how many sets it stands on',
        (tester) async {
      await pumpProgress(tester);
      await tapInPage(tester, switchOption('Rest'));

      final Finder card = cardOf(switchOption('Rest'));
      // 60 to 115 seconds in steps of five: mean 87.5.
      expect(
        find.descendant(of: card, matching: find.text('88 sec average')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('12 sessions · from 12 sets'),
        ),
        findsOneWidget,
      );
      final List<FlSpot> spots = tester
          .widget<LineChart>(
            find.descendant(of: card, matching: find.byType(LineChart)),
          )
          .data
          .lineBarsData
          .single
          .spots;
      expect(spots, hasLength(sessions));
      expect(spots.last.y, 115);
      await disposeApp(tester);
    });
  });

  group('line charts', () {
    testWidgets('never draw below or above the values they plot',
        (tester) async {
      await pumpProgress(tester);

      final Iterable<LineChart> charts =
          tester.widgetList<LineChart>(find.byType(LineChart));
      // Est. 1RM, effort and body weight.
      expect(charts, hasLength(3));
      for (final LineChart chart in charts) {
        final LineChartBarData line = chart.data.lineBarsData.single;
        expect(line.preventCurveOverShooting, isTrue);
        final Iterable<double> values = line.spots.map((FlSpot s) => s.y);
        final double low = values.reduce((a, b) => a < b ? a : b);
        final double high = values.reduce((a, b) => a > b ? a : b);
        expect(chart.data.minY, lessThan(low));
        expect(chart.data.maxY, greaterThan(high));
        expect(chart.data.minY, greaterThanOrEqualTo(0));
      }
      await disposeApp(tester);
    });

    testWidgets('a series of equal values is drawn mid-chart, not on its edge',
        (tester) async {
      await pumpProgress(tester);

      final LineChart weight = tester
          .widgetList<LineChart>(
            find.byType(LineChart),
          )
          .firstWhere(
            (LineChart c) =>
                c.data.lineBarsData.single.spots.every((FlSpot s) => s.y == 80),
          );
      expect(weight.data.minY, lessThan(80));
      expect(weight.data.maxY, greaterThan(80));
      expect(
        weight.data.maxY - 80,
        moreOrLessEquals(80 - weight.data.minY, epsilon: 0.001),
      );
      await disposeApp(tester);
    });
  });

  group('muscle groups', () {
    testWidgets('tapping a group shows its share and its weeks',
        (tester) async {
      await pumpProgress(tester);
      final Finder back = find.widgetWithText(ShareBarRow, 'Back');
      final Finder chest = find.widgetWithText(ShareBarRow, 'Chest');
      await tester.ensureVisible(chest);
      await settle(tester);

      // The largest group is shown until another is picked.
      expect(tester.widget<ShareBarRow>(back).selected, isTrue);
      expect(tester.widget<ShareBarRow>(chest).selected, isFalse);
      final Finder card = cardOf(chest);
      expect(
        find.descendant(
            of: card, matching: find.textContaining('Most trained')),
        findsOneWidget,
      );

      await tester.tap(chest);
      await settle(tester);

      expect(tester.widget<ShareBarRow>(chest).selected, isTrue);
      expect(tester.widget<ShareBarRow>(back).selected, isFalse);
      // 3,060 kg of bench against 4,260 kg of rows.
      expect(
        find.descendant(
          of: card,
          matching: find.text('3,060 kg · 42% of volume'),
        ),
        findsOneWidget,
      );
      final BarChart weeks = tester.widget<BarChart>(
        find.descendant(of: card, matching: find.byType(BarChart)),
      );
      final List<double> bars = <double>[
        for (final BarChartGroupData group in weeks.data.barGroups)
          group.barRods.single.toY,
      ];
      expect(bars.length, greaterThanOrEqualTo(sessions));
      expect(bars.reduce((a, b) => a + b), 3060);
      // The newest week is the last bar, and it is the heaviest.
      expect(bars.last, 310);
      await disposeApp(tester);
    });
  });

  group('body', () {
    testWidgets('logging is one quiet action in the heading', (tester) async {
      await pumpProgress(tester);

      expect(
          find.widgetWithText(TextButton, 'Log measurement'), findsOneWidget);
      expect(
          find.widgetWithText(FilledButton, 'Log measurement'), findsNothing);

      await tapInPage(tester, find.text('Log measurement'));
      expect(find.byType(AlertDialog), findsOneWidget);
      await disposeApp(tester);
    });
  });

  group('in Arabic', () {
    testWidgets('muscle groups and the insight name the lift in Arabic',
        (tester) async {
      await pumpProgress(
        tester,
        prefs: const <String, Object>{'app_locale': 'ar'},
      );

      // Muscle rows, and the card's headline for the largest group.
      expect(find.widgetWithText(ShareBarRow, 'الظهر'), findsOneWidget);
      expect(find.widgetWithText(ShareBarRow, 'الصدر'), findsOneWidget);
      expect(find.text('Back'), findsNothing);
      expect(find.text('Chest'), findsNothing);

      // The strength insight used to print the stored English name while
      // the strength rows two cards below showed the Arabic one.
      expect(find.textContaining('Barbell Bench Press'), findsNothing);
      expect(
        find.textContaining('ضغط بار على مقعد مستوٍ'),
        findsAtLeastNWidgets(2),
      );
      await disposeApp(tester);
    });

    testWidgets('the first range and the first chapter sit on the right',
        (tester) async {
      await pumpProgress(
        tester,
        prefs: const <String, Object>{'app_locale': 'ar'},
      );

      final Finder range = find.byType(SegmentedPills<ProgressRange>);
      Finder option(String label) =>
          find.descendant(of: range, matching: find.text(label));
      expect(
        tester.getCenter(option('أسبوعان')).dx,
        greaterThan(tester.getCenter(option('الكل')).dx),
      );
      expect(
        tester.getCenter(tab('القوة')).dx,
        greaterThan(tester.getCenter(tab('الجسم')).dx),
      );
      await disposeApp(tester);
    });
  });
}
