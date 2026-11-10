import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/program_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/features/library/presentation/widgets/exercise_detail_sheet.dart';

import '../helpers/pump_app.dart';
import '../helpers/stub_seeders.dart';

/// "How to do it" from outside the Library: a program day and a saved
/// workout both open the same exercise sheet the Library does, end to end
/// through the real routes and an in-memory database.
void main() {
  group('exercise how-to sheet', () {
    late AppDatabase database;

    const Map<String, Object> seededPrefs = <String, Object>{
      'exercise_seed_version': 999999,
      'program_seed_version': 999999,
    };

    setUp(() async {
      database = AppDatabase.forTesting();
      final ExerciseDao exercises = ExerciseDao(database);
      for (final (String id, String name) in <(String, String)>[
        ('bench', 'Bench Press'),
        ('row', 'Barbell Row'),
      ]) {
        await exercises.upsertExercises([
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
      }
      // Inserted out of order on purpose: the sheet must show steps by
      // step number, not by insertion order.
      await exercises.replaceInstructions('bench', [
        ExerciseInstructionsTableCompanion.insert(
          id: 'bench_s2',
          exerciseId: 'bench',
          stepNumber: 2,
          instruction: 'Press the bar back up.',
        ),
        ExerciseInstructionsTableCompanion.insert(
          id: 'bench_s1',
          exerciseId: 'bench',
          stepNumber: 1,
          instruction: 'Lower the bar to your chest.',
        ),
      ]);

      final DateTime utc = DateTime.now().toUtc();
      await ProgramDao(database).insertProgram(
        ProgramsTableCompanion.insert(
          id: 'p1',
          name: 'Full Body',
          createdAt: utc,
          updatedAt: utc,
          isBuiltIn: const Value(false),
        ),
        <ProgramDayInsert>[
          ProgramDayInsert(
            id: 'p1_day_a',
            dayName: 'Workout A',
            orderIndex: 0,
            template: TemplatesTableCompanion.insert(
              id: 'p1_tpl_a',
              name: 'Workout A',
              createdAt: utc,
              updatedAt: utc,
            ),
            exercises: <TemplateExercisesTableCompanion>[
              TemplateExercisesTableCompanion.insert(
                id: 'p1_tpl_a_e0',
                templateId: 'p1_tpl_a',
                exerciseId: 'bench',
                orderIndex: 0,
                targetSets: 3,
                targetReps: const Value('8'),
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
        ],
      );

      await WorkoutDao(database).insertWorkout(
        WorkoutsTableCompanion.insert(
          id: 'w1',
          startedAt: utc.subtract(const Duration(days: 1)),
          endedAt: Value(utc.subtract(const Duration(hours: 23))),
          totalVolumeKg: const Value(640),
          durationSeconds: const Value(3600),
        ),
        <WorkoutExercisesTableCompanion>[
          WorkoutExercisesTableCompanion.insert(
            id: 'w1_e1',
            workoutId: 'w1',
            exerciseId: 'bench',
            orderIndex: 0,
          ),
        ],
        <WorkoutSetsTableCompanion>[
          WorkoutSetsTableCompanion.insert(
            id: 'w1_e1_s0',
            workoutExerciseId: 'w1_e1',
            setIndex: 0,
            weightKg: 80,
            reps: 8,
            isCompleted: const Value(true),
          ),
        ],
      );
    });

    // See `disposeApp` in library_page_test.dart for why the extra pump.
    Future<void> disposeApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      await database.close();
    }

    Future<void> pumpAt(WidgetTester tester, String location) => pumpApp(
          tester,
          initialLocation: location,
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            ...stubSeeders(),
          ],
          prefs: seededPrefs,
          surfaceSize: const Size(400, 1200),
          awaitDatabase: true,
        );

    /// The sheet loads its detail through a real Drift query, which needs
    /// genuine wall-clock time (see `pumpApp`'s `awaitDatabase`).
    Future<void> openAndLoad(WidgetTester tester, Finder target) async {
      await tester.tap(target);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    void expectOrderedSteps(WidgetTester tester) {
      final Finder step1 = find.text('Lower the bar to your chest.');
      final Finder step2 = find.text('Press the bar back up.');
      expect(step1, findsOneWidget);
      expect(step2, findsOneWidget);
      expect(
        tester.getTopLeft(step1).dy,
        lessThan(tester.getTopLeft(step2).dy),
        reason: 'steps must render in step-number order',
      );
    }

    testWidgets('a program day exercise opens its instructions',
        (tester) async {
      await pumpAt(tester, '/program/p1');

      expect(find.text('Workout A'), findsOneWidget);
      expect(find.byType(ExerciseDetailSheet), findsNothing);

      await openAndLoad(tester, find.text('Bench Press'));

      expect(find.byType(ExerciseDetailSheet), findsOneWidget);
      expect(find.text('Instructions'), findsOneWidget);
      expectOrderedSteps(tester);

      await disposeApp(tester);
    });

    testWidgets('each program line opens its own exercise, not the first',
        (tester) async {
      await pumpAt(tester, '/program/p1');

      await openAndLoad(tester, find.text('Barbell Row'));

      // Title in the sheet, plus the line still visible behind it.
      expect(
        find.descendant(
          of: find.byType(ExerciseDetailSheet),
          matching: find.text('Barbell Row'),
        ),
        findsOneWidget,
      );
      expect(find.text('Lower the bar to your chest.'), findsNothing);

      await disposeApp(tester);
    });

    testWidgets('tapping a line does not start the day', (tester) async {
      await pumpAt(tester, '/program/p1');

      await openAndLoad(tester, find.text('Bench Press'));

      // Still on the program page (under the sheet), not the live session.
      expect(find.text('Full Body'), findsOneWidget);
      expect(find.text('Finish'), findsNothing);

      await disposeApp(tester);
    });

    testWidgets('a program line is a labelled button at least 48dp tall',
        (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpAt(tester, '/program/p1');

      final Finder target = find.ancestor(
        of: find.text('Bench Press'),
        matching: find.byType(ExerciseInfoTapTarget),
      );
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(target),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          label: 'Bench Press\n3 × 8\nHow to do Bench Press',
        ),
      );

      semantics.dispose();
      await disposeApp(tester);
    });

    testWidgets('a saved workout exercise opens its instructions',
        (tester) async {
      await pumpAt(tester, '/workout/w1');

      await openAndLoad(tester, find.text('Bench Press'));

      expect(find.byType(ExerciseDetailSheet), findsOneWidget);
      expectOrderedSteps(tester);

      await disposeApp(tester);
    });

    testWidgets('the sheet closes back to the page it was opened from',
        (tester) async {
      await pumpAt(tester, '/workout/w1');

      await openAndLoad(tester, find.text('Bench Press'));
      await tester.tapAt(const Offset(200, 20)); // the scrim
      await tester.pumpAndSettle();

      expect(find.byType(ExerciseDetailSheet), findsNothing);
      expect(find.text('Workout'), findsWidgets);

      await disposeApp(tester);
    });
  });
}
