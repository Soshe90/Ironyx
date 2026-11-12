import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/formatters/unit_formatters.dart';
import 'package:ironyx/core/formatters/week_start.dart';
import 'package:ironyx/core/formatters/week_start_controller.dart';
import 'package:ironyx/core/formatters/weight_unit_controller.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/core/services/data_export_service.dart';
import 'package:ironyx/core/widgets/app_card.dart';
import 'package:ironyx/features/backup/domain/cloud_backup_controller.dart';
import 'package:ironyx/features/tracker/domain/active_workout_notifier.dart';
import 'package:ironyx/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Counts delete-all calls, and fails them on request, without touching
/// a database.
class _CountingExportService extends DataExportService {
  int deletes = 0;
  bool fail = false;

  /// Holds the export open until completed, or fails it.
  Completer<String>? export;

  @override
  Future<String> buildJsonExport(AppDatabase db, {bool indent = true}) =>
      export?.future ?? Future<String>.value('{}');

  @override
  Future<void> deleteAllUserData(
    AppDatabase db, {
    String? snapshotDirPath,
  }) async {
    deletes++;
    if (fail) throw StateError('disk full');
  }
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

    group('first day of the week', () {
      Future<void> openSetting(
        WidgetTester tester, {
        Map<String, Object> prefs = const <String, Object>{},
        Size surfaceSize = const Size(400, 800),
      }) async {
        await pumpApp(
          tester,
          initialLocation: '/settings',
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          prefs: prefs,
          surfaceSize: surfaceSize,
        );
        await tester.pumpAndSettle();
        // Below the fold, and lazily built: see the units test above.
        await tester.scrollUntilVisible(
          find.byType(SegmentedButton<WeekStart>),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
      }

      WeekStart selected(WidgetTester tester) => tester
          .widget<SegmentedButton<WeekStart>>(
            find.byType(SegmentedButton<WeekStart>),
          )
          .selected
          .single;

      WeekStart stored(WidgetTester tester) => ProviderScope.containerOf(
            tester.element(find.byType(SegmentedButton<WeekStart>)),
          ).read(weekStartControllerProvider);

      testWidgets('offers Saturday, Sunday and Monday, with Monday chosen',
          (tester) async {
        await openSetting(tester);

        // The header ends up just above the viewport once the control is
        // scrolled to; it is built, only not on screen.
        expect(
          find.text('Week starts on', skipOffstage: false),
          findsOneWidget,
        );
        final Finder button = find.byType(SegmentedButton<WeekStart>);
        for (final String day in <String>['Saturday', 'Sunday', 'Monday']) {
          expect(
            find.descendant(of: button, matching: find.text(day)),
            findsOneWidget,
          );
        }
        expect(
          find.descendant(of: button, matching: find.text('Friday')),
          findsNothing,
        );
        expect(selected(tester), WeekStart.monday);
      });

      testWidgets('choosing a day selects it and saves it', (tester) async {
        await openSetting(tester);
        final Finder button = find.byType(SegmentedButton<WeekStart>);

        await tester.tap(
          find.descendant(of: button, matching: find.text('Saturday')),
        );
        await tester.pumpAndSettle();

        expect(selected(tester), WeekStart.saturday);
        expect(stored(tester), WeekStart.saturday);
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('week_start'), 'saturday');

        await tester.tap(
          find.descendant(of: button, matching: find.text('Sunday')),
        );
        await tester.pumpAndSettle();

        expect(selected(tester), WeekStart.sunday);
        expect(prefs.getString('week_start'), 'sunday');
      });

      testWidgets('shows the day saved on an earlier launch', (tester) async {
        await openSetting(
          tester,
          prefs: <String, Object>{'week_start': 'saturday'},
        );

        expect(selected(tester), WeekStart.saturday);
      });

      testWidgets('fits a narrow phone in Arabic without overflowing',
          (tester) async {
        await openSetting(
          tester,
          prefs: <String, Object>{'app_locale': 'ar'},
          surfaceSize: const Size(320, 640),
        );

        final AppLocalizations ar = lookupAppLocalizations(const Locale('ar'));
        expect(
          find.text(ar.settingsWeekStartTitle, skipOffstage: false),
          findsOneWidget,
        );
        final Finder button = find.byType(SegmentedButton<WeekStart>);
        expect(
          find.descendant(
            of: button,
            matching: find.text(ar.progressWeekdayFull('saturday')),
          ),
          findsOneWidget,
        );
        // A layout overflow would be reported here as an exception.
        expect(tester.takeException(), isNull);
      });
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

    // Found on a real phone: the field autofocuses, the keyboard takes most
    // of the screen, and the dialog's content overflowed. No keyboard exists
    // under test, so this fakes one with a bottom inset of the same size.
    testWidgets(
        'the delete-all dialog still fits with the keyboard open on a '
        'small phone', (tester) async {
      await pumpApp(
        tester,
        initialLocation: '/settings',
        surfaceSize: const Size(360, 640),
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Delete all data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The field can still be reached and used.
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Delete everything'),
            )
            .onPressed,
        isNotNull,
      );
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

      // What else delete-all must remove: an exercise of the user's own, an
      // import snapshot, and an open workout.
      await exerciseDao.upsertExercises([
        ExercisesTableCompanion.insert(
          id: 'mine',
          slug: 'mine',
          name: 'My Row',
          category: 'other',
          difficulty: 'intermediate',
          movementPattern: 'other',
          seedVersion: 0,
          isCustom: const Value(true),
        ),
      ]);
      final Directory snapshots =
          Directory.systemTemp.createTempSync('ironyx_settings_delete');
      addTearDown(() => snapshots.deleteSync(recursive: true));
      File('${snapshots.path}/pre_import_snapshot_1.json')
          .writeAsStringSync('{}');

      await pumpApp(
        tester,
        initialLocation: '/settings',
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          exerciseSeederProvider.overrideWith(_NoopExerciseSeeder.new),
          snapshotDirectoryProvider.overrideWith((ref) async => snapshots.path),
        ],
        awaitDatabase: true,
      );
      await tester.pumpAndSettle();
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      await tester.runAsync(
        () => container.read(activeWorkoutProvider.notifier).start(),
      );
      expect(container.read(activeWorkoutProvider), isNotNull);

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
      expect(
        snapshots.listSync(),
        isEmpty,
        reason: 'a snapshot is a full copy, and Restore snapshot undid the '
            'delete with it',
      );
      expect(container.read(activeWorkoutProvider), isNull,
          reason: 'the open workout is kept outside the database');
      final mine = await database
          .customSelect("SELECT id FROM exercises_table WHERE id = 'mine'")
          .get();
      expect(mine, isEmpty);
      expect(find.text('All data deleted'), findsOneWidget);
    });

    Future<void> openDeleteDialog(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.text('Delete all data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();
    }

    testWidgets('Export first offers the export and deletes nothing',
        (tester) async {
      final _CountingExportService service = _CountingExportService();
      await pumpApp(
        tester,
        initialLocation: '/settings',
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          dataExportServiceProvider.overrideWithValue(service),
        ],
      );
      await tester.pumpAndSettle();
      await openDeleteDialog(tester);

      await tester.tap(find.text('Export first'));
      await tester.pumpAndSettle();

      // The export's own first step: choosing the format.
      expect(find.text('JSON backup (can be imported later)'), findsOneWidget);
      expect(service.deletes, 0);
    });

    testWidgets('an export shows its progress, and a failure says so',
        (tester) async {
      final _CountingExportService service = _CountingExportService()
        ..export = Completer<String>();
      await pumpApp(
        tester,
        initialLocation: '/settings',
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          dataExportServiceProvider.overrideWithValue(service),
        ],
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Export data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JSON backup (can be imported later)'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'nothing showed while the export was built');

      service.export!.completeError(StateError('disk full'));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text("Couldn't export your data. Please try again."),
          findsOneWidget);
    });

    testWidgets('snapshots are listed by when they were taken', (tester) async {
      final Directory snapshots =
          Directory.systemTemp.createTempSync('ironyx_snapshot_list');
      addTearDown(() => snapshots.deleteSync(recursive: true));
      final DateTime taken = DateTime(2026, 11, 12, 9, 1);
      File('${snapshots.path}/pre_import_snapshot_'
              '${taken.toUtc().millisecondsSinceEpoch}.json')
          .writeAsStringSync('{}');
      await pumpApp(
        tester,
        initialLocation: '/settings',
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          snapshotDirectoryProvider.overrideWith((ref) async => snapshots.path),
        ],
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Restore pre-import snapshot'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore pre-import snapshot'));
      // Listing the folder is real file I/O.
      for (int i = 0;
          i < 50 && find.text('Restore snapshot').evaluate().isEmpty;
          i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.textContaining('12 Nov 2026'), findsOneWidget);
      expect(find.textContaining('pre_import_snapshot'), findsNothing,
          reason: 'it listed file names');
    });

    testWidgets('a snapshot folder that cannot be read says so',
        (tester) async {
      await pumpApp(
        tester,
        initialLocation: '/settings',
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          snapshotDirectoryProvider.overrideWith(
            (ref) => Future<String>.error(StateError('no storage')),
          ),
        ],
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Restore pre-import snapshot'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore pre-import snapshot'));
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't restore this snapshot"),
          findsOneWidget);
    });

    testWidgets('language, appearance, units and week start share one card',
        (tester) async {
      await pumpApp(
        tester,
        initialLocation: '/settings',
        surfaceSize: const Size(400, 2400),
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      await tester.pumpAndSettle();

      expect(find.text('Preferences'), findsOneWidget);
      final Set<Element> cards = <Element>{
        for (final String title in <String>[
          'Language',
          'Appearance',
          'Units',
          'Week starts on',
        ])
          tester.element(
            find.ancestor(
              of: find.text(title),
              matching: find.byType(AppCard),
            ),
          ),
      };
      expect(cards, hasLength(1),
          reason: 'each was a card under its own heading');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a delete that fails says so', (tester) async {
      final _CountingExportService service = _CountingExportService()
        ..fail = true;
      await pumpApp(
        tester,
        initialLocation: '/settings',
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          dataExportServiceProvider.overrideWithValue(service),
          snapshotDirectoryProvider.overrideWith((ref) async => 'unused'),
        ],
      );
      await tester.pumpAndSettle();
      await openDeleteDialog(tester);
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete everything'));
      await tester.pumpAndSettle();

      expect(service.deletes, 1);
      expect(
        find.text(
          'Something went wrong while deleting your data. Please try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('All data deleted'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'the progress dialog is closed');
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
