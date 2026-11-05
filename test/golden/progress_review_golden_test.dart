@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/body_metrics_dao.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/router/routes.dart';
import 'package:ironyx/core/widgets/segmented_pills.dart';

import '../helpers/golden_fonts.dart';
import '../helpers/pump_app.dart';
import '../helpers/stub_seeders.dart';

/// Renders the whole Progress page, top to bottom, for review.
///
/// `screens_golden_test.dart` shoots every screen at phone height, which
/// shows the first two cards of this one. Here the surface is tall enough
/// for the entire page, in light and dark, with the alternate chart views
/// selected, and in Arabic for the mirrored layout.
///
/// A review harness like its sibling: skipped by default, and its pictures
/// go to `build/progress_review/` (not committed). Refresh them with:
///
///   flutter test test/golden/progress_review_golden_test.dart \
///     --update-goldens --run-skipped
///
/// Arabic text draws as boxes: the test environment has no Arabic font.
/// Use that picture for layout and direction only, and a device for text.
void main() {
  setUpAll(loadGoldenFonts);

  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting();
    await _seed(database);
  });

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await database.close();
  }

  // Tall enough that nothing is left below the fold.
  const Size page = Size(390, 5200);

  Future<void> open(
    WidgetTester tester, {
    Map<String, Object> prefs = const <String, Object>{},
    Size size = page,
  }) async {
    await pumpApp(
      tester,
      initialLocation: Routes.progress,
      surfaceSize: size,
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        ...stubSeeders(),
      ],
      prefs: <String, Object>{'exercise_seed_version': 999999, ...prefs},
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    Directory('build/progress_review').createSync(recursive: true);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../build/progress_review/$name.png'),
    );
  }

  testWidgets('light', (tester) async {
    await open(tester, prefs: <String, Object>{'theme_mode': 'light'});
    await shoot(tester, 'light');
    await disposeApp(tester);
  });

  testWidgets('dark', (tester) async {
    await open(tester, prefs: <String, Object>{'theme_mode': 'dark'});
    await shoot(tester, 'dark');
    await disposeApp(tester);
  });

  testWidgets('alternate chart views', (tester) async {
    await open(tester, prefs: <String, Object>{'theme_mode': 'light'});
    // Second segment of each in-card switch, and the second muscle group.
    for (final String label in <String>['Volume', 'Rest']) {
      await tester.tap(
        find.descendant(
          of: find.byWidgetPredicate(
            (Widget w) => w is SegmentedPills && w.segments.length == 2,
          ),
          matching: find.text(label),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.tap(find.text('Legs'));
    // Twice: the first frame starts the chart's change of bars, the second
    // lands after it has finished.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await shoot(tester, 'light_alternate');
    await disposeApp(tester);
  });

  testWidgets('arabic', (tester) async {
    await open(
      tester,
      prefs: <String, Object>{'app_locale': 'ar', 'theme_mode': 'light'},
    );
    await shoot(tester, 'arabic_layout');
    await disposeApp(tester);
  });

  testWidgets('phone height, scrolled into a chapter', (tester) async {
    await open(
      tester,
      size: const Size(390, 844),
      prefs: <String, Object>{'theme_mode': 'light'},
    );
    await tester.tap(find.text('Habits').first);
    await tester.pumpAndSettle();
    await shoot(tester, 'phone_habits');
    await disposeApp(tester);
  });
}

/// Fourteen weeks of training with gaps, effort and rest recorded, four
/// muscle groups and a few weigh-ins: enough for every card to draw.
Future<void> _seed(AppDatabase db) async {
  final ExerciseDao exercises = ExerciseDao(db);
  final WorkoutDao workouts = WorkoutDao(db);
  final BodyMetricsDao metrics = BodyMetricsDao(db);

  // Real catalogue slugs, so their Arabic names resolve. The catalogue
  // seed itself is stubbed out (`stubSeeders`): left to run at app start it
  // replaces every muscle mapping, and these lifts would lose theirs.
  const List<(String, String, String, String, String)> lifts =
      <(String, String, String, String, String)>[
    (
      'ex_088',
      'incline-dumbbell-press',
      'Incline Dumbbell Press',
      'horizontalPush',
      'chest'
    ),
    (
      'ex_012',
      'seated-cable-row',
      'Seated Cable Row',
      'horizontalPull',
      'back'
    ),
    ('ex_011', 'lat-pulldown', 'Lat Pulldown', 'verticalPull', 'back'),
    ('ex_025', 'back-squat', 'Back Squat', 'kneeDominant', 'legs'),
    ('ex_014', 'overhead-press', 'Overhead Press', 'verticalPush', 'shoulders'),
  ];

  for (final String id in <String>['chest', 'back', 'legs', 'shoulders']) {
    await db.into(db.musclesTable).insert(
          MusclesTableCompanion.insert(
            id: id,
            name: id,
            displayName: '${id[0].toUpperCase()}${id.substring(1)}',
          ),
        );
  }
  await exercises.upsertExercises(<ExercisesTableCompanion>[
    for (final (String id, String slug, String name, String pattern, _)
        in lifts)
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
  for (final (String id, _, _, _, String muscle) in lifts) {
    await db.into(db.exerciseMusclesTable).insert(
          ExerciseMusclesTableCompanion.insert(
            id: '${id}_primary',
            exerciseId: id,
            muscleId: muscle,
            role: 'primary',
          ),
        );
  }

  final DateTime now = DateTime.now();
  // Days ago, oldest last. Two quiet stretches so untrained weeks show.
  const List<int> daysAgo = <int>[
    0, 2, 5, 9, 12, 16, 19, 23, 37, 40, 44, 47, 51, 68, 72, 75, 79, 82, //
    120, 127, 134,
  ];
  for (int n = 0; n < daysAgo.length; n++) {
    final DateTime started = now.subtract(Duration(days: daysAgo[n], hours: 2));
    final String wid = 'w$n';
    // Later sessions (smaller n) are a little heavier: progress to plot.
    final double gain = (daysAgo.length - n) * 0.75;
    final List<int> picked = <int>[n % 5, (n + 1) % 5, (n + 3) % 5];
    double weightOf(int lift, int set) => 40 + lift * 12 + gain + set * 2.5;
    int repsOf(int lift, int set) => 10 - set * 2 - (lift == 3 ? 3 : 0);
    // Derived from the sets below, as saving a workout does.
    double totalVolumeKg = 0;
    for (final int lift in picked) {
      for (int set = 0; set < 3; set++) {
        totalVolumeKg += weightOf(lift, set) * repsOf(lift, set);
      }
    }
    await workouts.insertWorkout(
      WorkoutsTableCompanion.insert(
        id: wid,
        startedAt: started,
        endedAt: Value(started.add(const Duration(minutes: 55))),
        totalVolumeKg: Value(totalVolumeKg),
        durationSeconds: const Value(3300),
      ),
      <WorkoutExercisesTableCompanion>[
        for (int e = 0; e < picked.length; e++)
          WorkoutExercisesTableCompanion.insert(
            id: '${wid}_e$e',
            workoutId: wid,
            exerciseId: lifts[picked[e]].$1,
            orderIndex: e,
          ),
      ],
      <WorkoutSetsTableCompanion>[
        for (int e = 0; e < picked.length; e++)
          for (int s = 0; s < 3; s++)
            WorkoutSetsTableCompanion.insert(
              id: '${wid}_e${e}_s$s',
              workoutExerciseId: '${wid}_e$e',
              setIndex: s,
              weightKg: weightOf(picked[e], s),
              reps: repsOf(picked[e], s),
              isCompleted: const Value(true),
              rpeTimes10: Value(60 + ((n * 7 + s * 5) % 30)),
              restSeconds: Value(s == 0 ? null : 60 + ((n * 13 + s * 9) % 60)),
            ),
      ],
    );
  }

  for (int i = 0; i < 6; i++) {
    await metrics.upsert(
      BodyMetricsTableCompanion.insert(
        id: 'bm$i',
        date: now.subtract(Duration(days: i * 12)),
        weightKg: 82.5 + i * 0.4,
        bodyFatPercentage: Value(17.5 + i * 0.2),
      ),
    );
  }
}
