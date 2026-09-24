import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/program_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/router/routes.dart';

import '../helpers/pump_app.dart';
import '../helpers/stub_seeders.dart';

/// End-to-end coverage for the program builder: creating a custom program
/// from the Tracker tab, and editing it afterwards.
void main() {
  group('ProgramEditorPage', () {
    late AppDatabase database;

    const Map<String, Object> seededPrefs = <String, Object>{
      'exercise_seed_version': 999999,
      'program_seed_version': 999999,
    };

    setUp(() async {
      database = AppDatabase.forTesting();
      final exerciseDao = ExerciseDao(database);
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
    });

    Future<void> disposeApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      await database.close();
    }

    testWidgets(
        'creating a program from Tracker adds a day and an exercise, then '
        'shows up in the Programs list', (tester) async {
      await pumpApp(
        tester,
        initialLocation: Routes.tracker,
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          ...stubSeeders(),
        ],
        prefs: seededPrefs,
        // Programs and the exercise picker both read Drift streams.
        awaitDatabase: true,
      );
      await tester.pumpAndSettle();

      // The Programs section header carries a labelled "New" action.
      await tester.tap(find.widgetWithText(TextButton, 'New'));
      await tester.pumpAndSettle();
      expect(find.text('New program'), findsOneWidget);

      // Saving with no name must be rejected, not silently accepted.
      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pumpAndSettle();
      expect(find.text('Give the program a name.'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Program name'),
        'My Split',
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Add day'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Day name'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Add exercise'));
      await tester.pumpAndSettle();
      expect(find.text('Add exercise'), findsWidgets);
      await tester.tap(find.text('Bench Press'));
      await tester.pumpAndSettle();
      expect(find.text('Bench Press'), findsOneWidget);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pumpAndSettle();

      // Back on Tracker, the new program is listed.
      expect(find.text('My Split'), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('editing a custom program renames it and persists the change',
        (tester) async {
      final programDao = ProgramDao(database);
      await programDao.insertProgram(
        ProgramsTableCompanion.insert(
          id: 'custom1',
          name: 'Old Name',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
          isBuiltIn: const Value(false),
        ),
        [
          ProgramDayInsert(
            id: 'custom1_day0',
            dayName: 'Day A',
            orderIndex: 0,
            template: TemplatesTableCompanion.insert(
              id: 'custom1_tpl0',
              name: 'custom1_tpl0',
              createdAt: DateTime.now().toUtc(),
              updatedAt: DateTime.now().toUtc(),
            ),
            exercises: [
              TemplateExercisesTableCompanion.insert(
                id: 'custom1_ex0',
                templateId: 'custom1_tpl0',
                exerciseId: 'bench',
                orderIndex: 0,
                targetSets: 3,
              ),
            ],
          ),
        ],
      );

      await pumpApp(
        tester,
        initialLocation: Routes.tracker,
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          ...stubSeeders(),
        ],
        prefs: seededPrefs,
        // Programs and the exercise picker both read Drift streams.
        awaitDatabase: true,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Old Name'));
      await tester.pumpAndSettle();
      expect(
          find.widgetWithIcon(IconButton, Icons.edit_outlined), findsOneWidget);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Edit program'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Program name'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Program name'),
        'New Name',
      );
      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pumpAndSettle();

      // Back on the detail page, the rename is reflected without a
      // manual refresh.
      expect(find.text('New Name'), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets(
        'a built-in program day can be edited, and the edit survives '
        're-entering the program', (tester) async {
      final programDao = ProgramDao(database);
      await programDao.insertProgram(
        ProgramsTableCompanion.insert(
          id: 'builtin_full_body',
          name: 'Full Body',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
          isBuiltIn: const Value(true),
        ),
        [
          ProgramDayInsert(
            id: 'builtin_full_body_pt_0',
            dayName: 'Workout A',
            orderIndex: 0,
            template: TemplatesTableCompanion.insert(
              id: 'builtin_fb_a',
              name: 'Full Body A',
              createdAt: DateTime.now().toUtc(),
              updatedAt: DateTime.now().toUtc(),
            ),
            exercises: [
              TemplateExercisesTableCompanion.insert(
                id: 'builtin_fb_a_e0',
                templateId: 'builtin_fb_a',
                exerciseId: 'bench',
                orderIndex: 0,
                targetSets: 3,
              ),
            ],
          ),
        ],
      );

      await pumpApp(
        tester,
        initialLocation: Routes.tracker,
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          ...stubSeeders(),
        ],
        prefs: seededPrefs,
        // Programs and the exercise picker both read Drift streams.
        awaitDatabase: true,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Full Body'));
      await tester.pumpAndSettle();
      expect(find.text('Built-in'), findsOneWidget);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Edit program'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Day name'),
        'Heavy Day',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Sets'), '5');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pumpAndSettle();

      // The detail page beneath shows the edit, and the program is now the
      // user's own rather than seed data.
      expect(find.text('Heavy Day'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);

      // Re-entering the editor loads the saved values, not the seed ones.
      await tester.tap(find.widgetWithIcon(IconButton, Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Heavy Day'), findsOneWidget);
      expect(find.widgetWithText(TextField, '5'), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets(
        'shows exercise names in Arabic when editing a program under the '
        'Arabic locale', (tester) async {
      // Regression guard: the program editor's exercise rows carry only the
      // DB's raw English name and an id (`ProgramDraftExercise` has no slug
      // of its own, unlike the read-only detail page's `ProgramDayExercise`
      // — see "translate exercise names inside program day cards"), so this
      // needed its own id-keyed lookup rather than picking up that earlier
      // fix for free.
      final exerciseDao = ExerciseDao(database);
      await exerciseDao.upsertExercises([
        ExercisesTableCompanion.insert(
          id: 'ex_026',
          slug: 'front-squat',
          name: 'Front Squat',
          category: 'strength',
          difficulty: 'intermediate',
          movementPattern: 'kneeDominant',
          seedVersion: 1,
        ),
      ]);
      final programDao = ProgramDao(database);
      await programDao.insertProgram(
        ProgramsTableCompanion.insert(
          id: 'custom2',
          name: 'Legs',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
          isBuiltIn: const Value(false),
        ),
        [
          ProgramDayInsert(
            id: 'custom2_day0',
            dayName: 'Day A',
            orderIndex: 0,
            template: TemplatesTableCompanion.insert(
              id: 'custom2_tpl0',
              name: 'custom2_tpl0',
              createdAt: DateTime.now().toUtc(),
              updatedAt: DateTime.now().toUtc(),
            ),
            exercises: [
              TemplateExercisesTableCompanion.insert(
                id: 'custom2_ex0',
                templateId: 'custom2_tpl0',
                exerciseId: 'ex_026',
                orderIndex: 0,
                targetSets: 3,
              ),
            ],
          ),
        ],
      );

      await pumpApp(
        tester,
        initialLocation: Routes.tracker,
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          ...stubSeeders(),
        ],
        prefs: <String, Object>{...seededPrefs, 'app_locale': 'ar'},
        awaitDatabase: true,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Legs'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.edit_outlined));
      await tester.pumpAndSettle();

      // `exerciseSlugsByIdProvider` derives from a real Drift stream over
      // real sqlite3 I/O (`AppDatabase.forTesting()`), which needs a slice
      // of genuine wall-clock time to resolve — `pumpApp`'s own
      // `awaitDatabase` only grants that once, at initial boot, before this
      // test has navigated anywhere near the exercise row that watches it.
      // Without another real wait here, the row renders with the map still
      // empty and falls back to the English name it was given.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();

      expect(find.text('سكوات أمامي'), findsOneWidget);
      expect(find.text('Front Squat'), findsNothing);

      await disposeApp(tester);
    });
  });
}
