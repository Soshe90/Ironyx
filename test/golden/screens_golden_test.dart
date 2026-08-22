@Tags(<String>['golden'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/daos/body_metrics_dao.dart';
import 'package:fittrack/core/database/daos/exercise_dao.dart';
import 'package:fittrack/core/database/daos/program_dao.dart';
import 'package:fittrack/core/database/daos/workout_dao.dart';
import 'package:fittrack/core/database/database_providers.dart';
import 'package:fittrack/core/router/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

/// Renders each screen against seeded data and writes a PNG per screen.
///
/// This is a review harness, not an assertion suite. It is skipped by
/// default (see dart_test.yaml); refresh the PNGs with:
///
///   flutter test --tags golden --update-goldens --run-skipped
///
/// The `--run-skipped` is required: selecting a tag does not override the
/// skip configured for it.
///
/// Without real fonts every glyph renders as a filled box, so Roboto and
/// MaterialIcons are loaded from the Flutter cache before anything pumps.
void main() {
  setUpAll(_loadFonts);

  group('screens', () {
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

    const Size phone = Size(390, 1000);

    Future<void> shoot(
      WidgetTester tester,
      String name,
      String location, {
      Size size = phone,
      Map<String, Object> extraPrefs = const <String, Object>{},
    }) async {
      await pumpApp(
        tester,
        initialLocation: location,
        surfaceSize: size,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        prefs: <String, Object>{
          'exercise_seed_version': 999999,
          ...extraPrefs,
        },
      );
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('$name.png'),
      );
      await disposeApp(tester);
    }

    testWidgets('dashboard', (t) => shoot(t, 'dashboard', Routes.home));
    testWidgets('tracker', (t) => shoot(t, 'tracker', Routes.tracker));
    testWidgets('library', (t) => shoot(t, 'library', Routes.library));
    testWidgets('timer', (t) => shoot(t, 'timer', Routes.timer));
    testWidgets('progress', (t) => shoot(t, 'progress', Routes.progress));
    testWidgets('settings', (t) => shoot(t, 'settings', Routes.settings));

    testWidgets(
      'active workout',
      (t) => shoot(
        t,
        'active_workout',
        Routes.activeWorkout,
        extraPrefs: <String, Object>{'active_workout_draft': _draftJson()},
      ),
    );

    testWidgets(
      'workout detail',
      (t) => shoot(t, 'workout_detail', '/workout/w1'),
    );

    testWidgets(
      'program detail',
      (t) => shoot(t, 'program_detail', '/program/p1'),
    );

    testWidgets(
      'program editor',
      (t) => shoot(t, 'program_editor', '/program/p1/edit'),
    );

    testWidgets(
      'dashboard tablet',
      (t) => shoot(t, 'dashboard_tablet', Routes.home,
          size: const Size(900, 1000)),
    );

    testWidgets(
      'library tablet',
      (t) => shoot(t, 'library_tablet', Routes.library,
          size: const Size(900, 1000)),
    );
  });
}

/// A draft with a part-logged exercise, so the active-workout screen shows
/// its table rather than its empty state.
String _draftJson() => jsonEncode(<String, dynamic>{
      'id': 'draft1',
      'startedAt': DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 23))
          .toIso8601String(),
      'exercises': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'de1',
          'exerciseId': 'bench',
          'name': 'Barbell Bench Press',
          'isWarmup': false,
          'sets': <Map<String, dynamic>>[
            for (final (String id, double w, int r, bool done) in <
                (String, double, int, bool)>[
              ('s1', 60, 10, true),
              ('s2', 80, 8, true),
              ('s3', 90, 6, false),
            ])
              <String, dynamic>{
                'id': id,
                'weightKg': w,
                'reps': r,
                'isCompleted': done,
                'isWarmup': false,
              },
          ],
        },
        <String, dynamic>{
          'id': 'de2',
          'exerciseId': 'squat',
          'name': 'Back Squat',
          'isWarmup': false,
          'sets': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 's4',
              'weightKg': 100.0,
              'reps': 5,
              'isCompleted': false,
              'isWarmup': false,
            },
          ],
        },
      ],
    });

/// Loads the real Roboto and MaterialIcons faces so the screenshots show
/// text and icons instead of the test font's filled boxes.
Future<void> _loadFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final String? root = _flutterRoot();
  if (root == null) return;
  final Directory dir =
      Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;

  Future<void> load(String family, List<String> files) async {
    final FontLoader loader = FontLoader(family);
    var any = false;
    for (final String file in files) {
      final File f = File('${dir.path}/$file');
      if (!f.existsSync()) continue;
      loader.addFont(Future<ByteData>.value(
        ByteData.sublistView(f.readAsBytesSync()),
      ));
      any = true;
    }
    if (any) await loader.load();
  }

  await load('Roboto', <String>[
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await load('MaterialIcons', <String>['MaterialIcons-Regular.otf']);
}

String? _flutterRoot() {
  // `which flutter` resolves through the snap wrapper, so derive the root
  // from the running Dart executable instead.
  final String exe = Platform.resolvedExecutable;
  final int i = exe.indexOf('/bin/cache/dart-sdk');
  return i < 0 ? Platform.environment['FLUTTER_ROOT'] : exe.substring(0, i);
}

Future<void> _seed(AppDatabase db) async {
  final ExerciseDao exercises = ExerciseDao(db);
  final WorkoutDao workouts = WorkoutDao(db);
  final ProgramDao programs = ProgramDao(db);
  final BodyMetricsDao metrics = BodyMetricsDao(db);

  await exercises.upsertExercises(<ExercisesTableCompanion>[
    for (final (String id, String name, String pattern) in <
        (String, String, String)>[
      ('bench', 'Barbell Bench Press', 'horizontalPush'),
      ('squat', 'Back Squat', 'kneeDominant'),
      ('row', 'Seated Cable Row', 'horizontalPull'),
      ('ohp', 'Overhead Press', 'verticalPush'),
      ('pullup', 'Pull-Up', 'verticalPull'),
      ('dead', 'Deadlift', 'hipDominant'),
    ])
      ExercisesTableCompanion.insert(
        id: id,
        slug: id,
        name: name,
        category: 'strength',
        difficulty: 'intermediate',
        movementPattern: pattern,
        seedVersion: 1,
      ),
  ]);

  // Several weeks of workouts so the charts and streak have something to
  // draw, with the most recent one today.
  final DateTime now = DateTime.now();
  for (var i = 0; i < 8; i++) {
    final DateTime started = now.subtract(Duration(days: i * 3));
    final String wid = 'w${i + 1}';
    // Derived from the sets below, exactly as `save` does. A made-up
    // total here would put a figure on the detail screen that its own
    // per-exercise rows contradict.
    var totalVolumeKg = 0.0;
    for (var s = 0; s < 3; s++) {
      totalVolumeKg += (80 + s * 5 - i) * (8 - s);
      totalVolumeKg += (100 + s * 10 - i) * 5;
    }
    await workouts.insertWorkout(
      WorkoutsTableCompanion.insert(
        id: wid,
        startedAt: started,
        endedAt: Value(started.add(const Duration(minutes: 58))),
        totalVolumeKg: Value(totalVolumeKg),
        durationSeconds: const Value(3480),
      ),
      <WorkoutExercisesTableCompanion>[
        WorkoutExercisesTableCompanion.insert(
          id: '${wid}_e1',
          workoutId: wid,
          exerciseId: 'bench',
          orderIndex: 0,
        ),
        WorkoutExercisesTableCompanion.insert(
          id: '${wid}_e2',
          workoutId: wid,
          exerciseId: 'squat',
          orderIndex: 1,
        ),
      ],
      <WorkoutSetsTableCompanion>[
        for (var s = 0; s < 3; s++)
          WorkoutSetsTableCompanion.insert(
            id: '${wid}_e1_s$s',
            workoutExerciseId: '${wid}_e1',
            setIndex: s,
            weightKg: 80 + s * 5 - i.toDouble(),
            reps: 8 - s,
            isCompleted: const Value(true),
          ),
        for (var s = 0; s < 3; s++)
          WorkoutSetsTableCompanion.insert(
            id: '${wid}_e2_s$s',
            workoutExerciseId: '${wid}_e2',
            setIndex: s,
            weightKg: 100 + s * 10 - i.toDouble(),
            reps: 5,
            isCompleted: const Value(true),
          ),
      ],
    );
  }

  // A handful of lighter sessions in the *previous* quarter, so the
  // strength-change section has something to compare the current window
  // against instead of reporting every lift as new.
  for (var i = 0; i < 4; i++) {
    final DateTime started = now.subtract(Duration(days: 120 + i * 7));
    final String wid = 'old${i + 1}';
    var totalVolumeKg = 0.0;
    for (var s = 0; s < 3; s++) {
      totalVolumeKg += (65 + s * 5) * (8 - s);
      totalVolumeKg += (85 + s * 10) * 5;
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
        WorkoutExercisesTableCompanion.insert(
          id: '${wid}_e1',
          workoutId: wid,
          exerciseId: 'bench',
          orderIndex: 0,
        ),
        WorkoutExercisesTableCompanion.insert(
          id: '${wid}_e2',
          workoutId: wid,
          exerciseId: 'squat',
          orderIndex: 1,
        ),
      ],
      <WorkoutSetsTableCompanion>[
        for (var s = 0; s < 3; s++)
          WorkoutSetsTableCompanion.insert(
            id: '${wid}_e1_s$s',
            workoutExerciseId: '${wid}_e1',
            setIndex: s,
            weightKg: 65 + s * 5,
            reps: 8 - s,
            isCompleted: const Value(true),
          ),
        for (var s = 0; s < 3; s++)
          WorkoutSetsTableCompanion.insert(
            id: '${wid}_e2_s$s',
            workoutExerciseId: '${wid}_e2',
            setIndex: s,
            weightKg: 85 + s * 10,
            reps: 5,
            isCompleted: const Value(true),
          ),
      ],
    );
  }

  final DateTime utc = now.toUtc();
  await programs.insertProgram(
    ProgramsTableCompanion.insert(
      id: 'p1',
      name: 'Upper / Lower Split',
      description: const Value('Four days a week, alternating focus'),
      splitType: const Value('upperLower'),
      createdAt: utc,
      updatedAt: utc,
      isBuiltIn: const Value(false),
    ),
    <ProgramDayInsert>[
      ProgramDayInsert(
        id: 'p1_day_0',
        dayName: 'Upper A',
        orderIndex: 0,
        template: TemplatesTableCompanion.insert(
          id: 'p1_tpl_a',
          name: 'Upper A',
          createdAt: utc,
          updatedAt: utc,
        ),
        exercises: <TemplateExercisesTableCompanion>[
          TemplateExercisesTableCompanion.insert(
            id: 'p1_tpl_a_e0',
            templateId: 'p1_tpl_a',
            exerciseId: 'bench',
            orderIndex: 0,
            targetSets: 4,
            targetReps: const Value('6-8'),
          ),
          TemplateExercisesTableCompanion.insert(
            id: 'p1_tpl_a_e1',
            templateId: 'p1_tpl_a',
            exerciseId: 'row',
            orderIndex: 1,
            targetSets: 3,
            targetReps: const Value('10'),
          ),
        ],
      ),
      ProgramDayInsert(
        id: 'p1_day_1',
        dayName: 'Lower A',
        orderIndex: 1,
        template: TemplatesTableCompanion.insert(
          id: 'p1_tpl_b',
          name: 'Lower A',
          createdAt: utc,
          updatedAt: utc,
        ),
        exercises: <TemplateExercisesTableCompanion>[
          TemplateExercisesTableCompanion.insert(
            id: 'p1_tpl_b_e0',
            templateId: 'p1_tpl_b',
            exerciseId: 'squat',
            orderIndex: 0,
            targetSets: 5,
            targetReps: const Value('5'),
          ),
        ],
      ),
    ],
  );

  for (var i = 0; i < 6; i++) {
    await metrics.upsert(
      BodyMetricsTableCompanion.insert(
        id: 'bm$i',
        date: now.subtract(Duration(days: i * 7)),
        weightKg: 82.5 + i * 0.4,
        bodyFatPercentage: Value(17.5 + i * 0.2),
      ),
    );
  }
}
