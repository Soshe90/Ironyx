import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/services/data_export_service.dart';
import 'package:ironyx/features/settings/domain/export_envelope.dart';
import 'package:ironyx/features/settings/presentation/settings_page.dart';
import 'package:uuid/uuid.dart';

import 'helpers/e2e_harness.dart';

/// Export, import, snapshots and delete-all, against the device's own SQLite
/// and file system, at a data size a long-term user will reach.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const DataExportService service = DataExportService();

  Future<E2eApp> launchSeeded(WidgetTester tester) async {
    final E2eApp app =
        await E2eApp.install(prefs: {'onboarding_complete': true});
    await app.launch(tester);
    await pumpUntilFound(tester, find.text('Start workout'));
    await io(tester, () async {
      final Stopwatch clock = Stopwatch()..start();
      while (clock.elapsed < const Duration(seconds: 60)) {
        final int n = (await app.db.select(app.db.exercisesTable).get()).length;
        if (n >= 300) return;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      throw TestFailure('Exercise catalogue was not seeded within 60 s');
    });
    return app;
  }

  /// [count] workouts of 4 exercises x 4 sets, one every two days: about
  /// two and a half years of training three times a week at 400.
  ///
  /// UUIDs throughout, as the app writes them: the importer rejects any
  /// other id shape, so made-up ids would fail restore for the wrong reason.
  /// Returns the workout ids, oldest first.
  Future<List<String>> logHistory(AppDatabase db, int count) async {
    const Uuid uuid = Uuid();
    final List<String> exerciseIds =
        (await (db.select(db.exercisesTable)..limit(8)).get())
            .map((e) => e.id)
            .toList();
    final WorkoutDao dao = WorkoutDao(db);
    final DateTime start = DateTime.utc(2024, 1, 1, 18);
    final List<String> workoutIds = <String>[];
    for (int w = 0; w < count; w++) {
      final String workoutId = uuid.v4();
      workoutIds.add(workoutId);
      final List<String> exerciseRowIds =
          List<String>.generate(4, (_) => uuid.v4());
      final DateTime at = start.add(Duration(days: 2 * w));
      await dao.insertWorkout(
        WorkoutsTableCompanion.insert(
          id: workoutId,
          startedAt: at,
          endedAt: Value(at.add(const Duration(hours: 1))),
          totalVolumeKg: const Value(4000),
          durationSeconds: const Value(3600),
        ),
        <WorkoutExercisesTableCompanion>[
          for (int e = 0; e < 4; e++)
            WorkoutExercisesTableCompanion.insert(
              id: exerciseRowIds[e],
              workoutId: workoutId,
              exerciseId: exerciseIds[(w + e) % exerciseIds.length],
              orderIndex: e,
            ),
        ],
        <WorkoutSetsTableCompanion>[
          for (int e = 0; e < 4; e++)
            for (int s = 0; s < 4; s++)
              WorkoutSetsTableCompanion.insert(
                id: uuid.v4(),
                workoutExerciseId: exerciseRowIds[e],
                setIndex: s,
                weightKg: 50 + w * 0.25,
                reps: 8,
                isCompleted: const Value(true),
              ),
        ],
      );
    }
    return workoutIds;
  }

  Future<int> count(AppDatabase db, String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS c FROM $table').getSingle())
          .read<int>('c');

  testWidgets(
      'a large history exports to a file and restores from it exactly, '
      'within a usable time', (tester) async {
    final E2eApp app = await launchSeeded(tester);
    final Directory dir = await io(
      tester,
      () => Directory.systemTemp.createTemp('ironyx_export_'),
    );
    addTearDown(() => dir.delete(recursive: true));

    final List<String> ids = await io(tester, () => logHistory(app.db, 400));
    final int workouts =
        await io(tester, () => count(app.db, 'workouts_table'));
    final int sets =
        await io(tester, () => count(app.db, 'workout_sets_table'));
    expect(workouts, 400);
    expect(sets, 6400);

    final Stopwatch exportClock = Stopwatch()..start();
    final String json = await io(tester, () => service.buildJsonExport(app.db));
    final File file = File('${dir.path}/backup.json');
    await io(tester, () => file.writeAsString(json, flush: true));
    exportClock.stop();

    final Stopwatch importClock = Stopwatch()..start();
    final String readBack = await io(tester, file.readAsString);
    final ImportEnvelope envelope =
        await io(tester, () => service.parseImportInBackground(readBack));
    await io(tester, () => service.deleteAllUserData(app.db));
    expect(await io(tester, () => count(app.db, 'workouts_table')), 0);
    await io(
      tester,
      () => service.applyImport(
        app.db,
        envelope,
        mode: ImportMode.replace,
        snapshotDirPath: dir.path,
      ),
    );
    importClock.stop();

    // ignore: avoid_print
    print('[e2e] 400 workouts / 6400 sets: export '
        '${exportClock.elapsedMilliseconds} ms '
        '(${(json.length / 1024).round()} KiB), import '
        '${importClock.elapsedMilliseconds} ms');

    expect(await io(tester, () => count(app.db, 'workouts_table')), workouts);
    expect(await io(tester, () => count(app.db, 'workout_sets_table')), sets);
    final WorkoutWithDetails? last =
        await io(tester, () => WorkoutDao(app.db).getWithDetails(ids.last));
    expect(last, isNotNull);
    // A generous ceiling: this is to catch a regression to something
    // unusable, not to benchmark. Both run behind a progress dialog.
    expect(exportClock.elapsed, lessThan(const Duration(seconds: 30)));
    expect(importClock.elapsed, lessThan(const Duration(seconds: 60)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('damaged backup files are refused and change nothing',
      (tester) async {
    final E2eApp app = await launchSeeded(tester);
    await io(tester, () => logHistory(app.db, 3));
    final String good = await io(tester, () => service.buildJsonExport(app.db));

    final Map<String, String> damaged = <String, String>{
      'an empty file': '',
      'a truncated file': good.substring(0, good.length ~/ 2),
      'a file of zero bytes as text': '\u0000\u0000\u0000',
      'a JSON array': '[]',
      'a JSON object with no tables': '{"formatVersion": 1}',
      'a newer format version': jsonEncode(
        (jsonDecode(good) as Map<String, dynamic>)..['formatVersion'] = 999,
      ),
      'text that is not JSON': 'workout,weight\nbench,100',
    };

    for (final MapEntry<String, String> entry in damaged.entries) {
      expect(
        () => service.parseImport(entry.value),
        throwsA(isA<ImportValidationException>()),
        reason: entry.key,
      );
    }
    expect(await io(tester, () => count(app.db, 'workouts_table')), 3);
  });

  testWidgets(
      'a replace import snapshots the old data first, and the snapshot '
      'brings it back', (tester) async {
    final E2eApp app = await launchSeeded(tester);
    final Directory dir = await io(
      tester,
      () => Directory.systemTemp.createTemp('ironyx_snapshots_'),
    );
    addTearDown(() => dir.delete(recursive: true));

    // What the user has now: 5 workouts.
    await io(tester, () => logHistory(app.db, 5));
    // What they import over it: a backup with only 2.
    final String smaller = await io(tester, () async {
      await service.deleteAllUserData(app.db);
      await logHistory(app.db, 2);
      final String json = await service.buildJsonExport(app.db);
      await service.deleteAllUserData(app.db);
      await logHistory(app.db, 5);
      return json;
    });

    await io(
      tester,
      () => service.applyImport(
        app.db,
        service.parseImport(smaller),
        mode: ImportMode.replace,
        snapshotDirPath: dir.path,
      ),
    );
    expect(await io(tester, () => count(app.db, 'workouts_table')), 2);

    final List<File> snapshots =
        await io(tester, () => service.listSnapshots(dir.path));
    expect(snapshots, hasLength(1));

    await io(
      tester,
      () => service.restoreSnapshot(
        app.db,
        snapshots.single,
        snapshotDirPath: dir.path,
      ),
    );
    expect(await io(tester, () => count(app.db, 'workouts_table')), 5);
  });

  testWidgets(
      'Delete all data needs the exact word, then clears training data but '
      'keeps the library and restores built-in programs', (tester) async {
    final E2eApp app = await launchSeeded(tester);
    await io(tester, () => logHistory(app.db, 10));
    final int exercisesBefore =
        await io(tester, () => count(app.db, 'exercises_table'));

    await tester.tap(find.byTooltip('Settings'));
    await pumpUntilFound(tester, find.byType(SettingsPage));
    await scrollToAndTap(tester, find.text('Delete all data'));
    await pumpUntilFound(tester, find.text('Delete all data?'));

    FilledButton confirm() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Delete everything'),
        );
    final Finder input = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );

    for (final String wrong in <String>['delete', 'DELET', 'DELETE!', '']) {
      await tester.enterText(input, wrong);
      await tester.pump();
      expect(confirm().onPressed, isNull, reason: '"$wrong"');
    }
    // Surrounding spaces from an autocorrecting keyboard are forgiven.
    await tester.enterText(input, ' DELETE ');
    await tester.pump();
    expect(confirm().onPressed, isNotNull);

    // Cancel first: nothing happens.
    await tester.tap(find.text('Cancel'));
    await pumpUntilGone(tester, find.byType(AlertDialog));
    expect(await io(tester, () => count(app.db, 'workouts_table')), 10);

    await scrollToAndTap(tester, find.text('Delete all data'));
    await pumpUntilFound(tester, find.text('Delete all data?'));
    await tester.enterText(input, 'DELETE');
    await tester.pump();
    await tester.tap(find.text('Delete everything'));
    await pumpUntilFound(tester, find.text('All data deleted'));

    expect(await io(tester, () => count(app.db, 'workouts_table')), 0);
    expect(await io(tester, () => count(app.db, 'workout_sets_table')), 0);
    expect(
      await io(tester, () => count(app.db, 'exercises_table')),
      exercisesBefore,
    );
    expect(
      await io(tester, () => count(app.db, 'programs_table')),
      greaterThan(0),
    );
  });
}
