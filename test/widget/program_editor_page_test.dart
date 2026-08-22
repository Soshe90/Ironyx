import 'package:drift/drift.dart';
import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/daos/exercise_dao.dart';
import 'package:fittrack/core/database/daos/program_dao.dart';
import 'package:fittrack/core/database/database_providers.dart';
import 'package:fittrack/core/router/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

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
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        prefs: seededPrefs,
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
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        prefs: seededPrefs,
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
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        prefs: seededPrefs,
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
      await tester.enterText(find.widgetWithText(TextField, 'sets'), '5');
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
  });
}
