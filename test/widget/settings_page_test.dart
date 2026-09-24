import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/formatters/unit_formatters.dart';
import 'package:ironyx/core/formatters/weight_unit_controller.dart';
import 'package:ironyx/core/providers.dart';

import '../helpers/pump_app.dart';

/// Stands in for the real [ExerciseSeeder] in the delete-all test below.
///
/// That test needs the *real* [ProgramSeeder] (it exists to test the real
/// reset -> invalidate -> reseed sequence — see TODO.md A2.14), but the real
/// exercise seeder parses and inserts the full ~300-exercise bundled asset,
/// which this test does not otherwise care about and which was observed to
/// not reliably finish within a generous polling window under the full test
/// suite's load. Standing in for it and seeding by hand only the handful of
/// exercise ids the three built-in programs actually reference (their
/// `template_exercises_table` rows have a RESTRICT foreign key onto
/// `exercises_table`) keeps the real program-seeding path fast and
/// deterministic without touching what it's testing.
class _NoopExerciseSeeder extends ExerciseSeeder {
  @override
  Future<void> build() async {}
}

void main() {
  group('SettingsPage', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.forTesting();
    });

    tearDown(() async {
      await database.close();
    });

    testWidgets('choosing pounds persists the weight unit preference',
        (tester) async {
      await pumpApp(
        tester,
        initialLocation: '/settings',
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      await tester.pumpAndSettle();

      // Units sits below the fold at the test surface size, and lazily-built
      // list children have no element to scroll to until they are reached —
      // same reason the delete-all test below scrolls rather than tapping
      // blind. Every row added to the Account card above pushes this further
      // down, so the scroll is what keeps the test about units.
      await tester.scrollUntilVisible(
        find.text('Pounds (lb)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Kilograms (kg)'), findsOneWidget);
      await tester.tap(find.text('Pounds (lb)'));
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.text('Pounds (lb)'));
      final WeightUnit unit = ProviderScope.containerOf(context).read(
        weightUnitControllerProvider,
      );
      expect(unit, WeightUnit.lb);
    });

    testWidgets(
        'About section shows the exercise-data credit and opens the '
        'license page', (tester) async {
      await pumpApp(
        tester,
        initialLocation: '/settings',
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Exercise data & photos'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Exercise data & photos'));
      await tester.pumpAndSettle();
      expect(find.textContaining('free-exercise-db'), findsWidgets);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Open-source licenses'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open-source licenses'));
      await tester.pumpAndSettle();

      // `showLicensePage` renders a page titled with the app name — enough
      // to confirm the tile actually navigates there, without coupling this
      // test to Flutter's internal LicensePage implementation or to
      // `LicenseRegistry`'s global, test-run-wide registration state.
      expect(find.text('Ironyx'), findsWidgets);
    });

    testWidgets(
        'delete-all confirm button stays disabled until DELETE is typed',
        (tester) async {
      await pumpApp(
        tester,
        initialLocation: '/settings',
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      await tester.pumpAndSettle();

      // Data is the last group on the page and sits below the fold at the
      // test surface size. `scrollUntilVisible` rather than `ensureVisible`:
      // the latter needs the widget to already exist, and this ListView
      // builds lazily, so anything far enough down the page has no element
      // to make visible yet. That made the test brittle to any section
      // added above it — the Account card duly broke it.
      await tester.scrollUntilVisible(
        find.text('Delete all data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();

      final FilledButton confirmButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete everything'),
      );
      expect(confirmButton.onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pumpAndSettle();

      final FilledButton enabledButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete everything'),
      );
      expect(enabledButton.onPressed, isNotNull);
    });

    testWidgets(
        'tapping Delete everything actually deletes data and reseeds '
        'built-in programs', (tester) async {
      // Uses the *real* `ProgramSeeder` — this test exists specifically to
      // exercise its real `resetSeedVersion` -> `invalidate` ->
      // `read(...future)` sequence end to end, which TODO.md's A2.14 notes
      // had never actually been exercised by any test: the sibling test
      // above only checks that the confirm button enables, never taps it.
      //
      // The exercise seeder is stubbed, though: `ProgramSeeder.build()`
      // waits on it before seeding programs, and the real one parses and
      // inserts the full ~300-exercise bundled asset, which is unrelated to
      // what this test checks and was observed to not reliably finish
      // within a generous polling window under the full test suite's load.
      // Standing it up with only the exercise ids the three built-in
      // programs actually reference (a RESTRICT foreign key from
      // `template_exercises_table`) keeps the real program-seeding path
      // fast and deterministic without touching what it's testing.
      final ExerciseDao exerciseDao = ExerciseDao(database);
      const List<String> requiredExerciseIds = [
        'ex_001',
        'ex_002',
        'ex_003',
        'ex_007',
        'ex_009',
        'ex_012',
        'ex_014',
        'ex_016',
        'ex_019',
        'ex_024',
        'ex_025',
        'ex_026',
        'ex_030',
        'ex_031',
        'ex_034',
        'ex_035',
        'ex_036',
        'ex_037',
      ];
      await exerciseDao.upsertExercises([
        for (final id in requiredExerciseIds)
          ExercisesTableCompanion.insert(
            id: id,
            slug: id,
            name: id,
            category: 'strength',
            difficulty: 'intermediate',
            movementPattern: 'horizontalPush',
            seedVersion: 1,
          ),
      ]);

      // Polling, not a fixed wait: even this lighter, stubbed-exercise-seed
      // path still does real sqlite3 work, and a fixed duration flaked
      // twice under the full suite's load in an earlier version of this
      // test that waited on the real, unstubbed exercise seeder instead.
      Future<int> pollProgramCount() async {
        int count = 0;
        for (var attempt = 0; attempt < 50; attempt++) {
          count = await database
              .customSelect('SELECT COUNT(*) AS count FROM programs_table')
              .getSingle()
              .then((row) => row.read<int>('count'));
          if (count > 0) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pump();
        }
        return count;
      }

      await pumpApp(
        tester,
        initialLocation: '/settings',
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          exerciseSeederProvider.overrideWith(_NoopExerciseSeeder.new),
        ],
        awaitDatabase: true,
      );
      await tester.pumpAndSettle();

      final int programsBefore = await pollProgramCount();
      expect(
        programsBefore,
        greaterThan(0),
        reason: 'the real seeders must have run before delete-all, or the '
            'reseed assertion below would not mean anything',
      );

      await tester.scrollUntilVisible(
        find.text('Delete all data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Delete everything'));
      // Not `pumpAndSettle`: deleting and reseeding built-in programs is
      // real work against a real sqlite3 handle, and the reseed re-triggers
      // `app.dart`'s app-wide `programSeederProvider` watch.
      await tester.pump();

      final int programsAfter = await pollProgramCount();
      expect(
        programsAfter,
        greaterThan(0),
        reason: 'built-in programs must come back after delete-all, the '
            'same way the exercise catalogue does',
      );
    });
  });

  group('import progress dialog', () {
    // `DataManagementSection._runImport` is private and reachable only after
    // `FilePicker.pickFile`, which has no test-time platform channel and no
    // mockable seam anywhere in this codebase — so this reproduces the exact
    // dialog shape `_runImport` builds (a `PopScope(canPop: false)` progress
    // dialog, closed via a context captured from its own `builder` rather
    // than the caller's) instead of driving it through Settings' UI. See
    // TODO.md A2.8/A2.14 for the underlying gap: no test exercises the real
    // import confirm button end-to-end yet.
    testWidgets(
        'the system back button cannot dismiss it, and finishing closes '
        'only the dialog', (tester) async {
      final GlobalKey<NavigatorState> navigatorKey =
          GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('Settings')),
        ),
      );

      BuildContext? dialogContext;
      unawaited(
        showDialog<void>(
          context: navigatorKey.currentContext!,
          barrierDismissible: false,
          builder: (context) {
            dialogContext = context;
            return const PopScope(
              canPop: false,
              child: Center(child: CircularProgressIndicator()),
            );
          },
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // The system back button, simulated the way flutter_test always does.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason: 'PopScope(canPop: false) must block the back button while '
            'the import is in flight',
      );
      expect(find.text('Settings'), findsOneWidget);

      // The import "finishes": close via the captured dialog context, the
      // same way `_runImport` does, rather than the outer page's context.
      Navigator.of(dialogContext!).pop();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.text('Settings'),
        findsOneWidget,
        reason: 'closing the dialog must not also pop the page underneath it',
      );
    });

    testWidgets(
        'sound and haptics toggles live here (the Timer tab no longer '
        'duplicates them)', (tester) async {
      final AppDatabase db = AppDatabase.forTesting();
      addTearDown(db.close);
      await pumpApp(
        tester,
        initialLocation: '/settings',
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Haptics'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Sound cues'), findsOneWidget);
      expect(find.widgetWithText(SwitchListTile, 'Haptics'), findsOneWidget);
    });
  });
}
