import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/services/data_export_service.dart';

/// "Delete all data" removes the user's data, all of it, and nothing else.
void main() {
  const DataExportService service = DataExportService();
  late AppDatabase database;
  late Directory snapshotDir;

  setUp(() async {
    database = AppDatabase.forTesting();
    snapshotDir = Directory.systemTemp.createTempSync('ironyx_delete_all');
    await ExerciseDao(database).upsertExercises([
      ExercisesTableCompanion.insert(
        id: 'bench',
        slug: 'bench',
        name: 'Bench Press',
        category: 'strength',
        difficulty: 'intermediate',
        movementPattern: 'horizontalPush',
        seedVersion: 1,
      ),
      ExercisesTableCompanion.insert(
        id: 'mine',
        slug: 'my-row-imported-1',
        name: 'My Row',
        category: 'other',
        difficulty: 'intermediate',
        movementPattern: 'other',
        seedVersion: 0,
        isCustom: const Value(true),
      ),
    ]);
    // The custom exercise is in use, as an imported one would be.
    await WorkoutDao(database).insertWorkout(
      WorkoutsTableCompanion.insert(
        id: 'w1',
        startedAt: DateTime.utc(2026, 1, 1),
        endedAt: Value(DateTime.utc(2026, 1, 1, 1)),
      ),
      [
        WorkoutExercisesTableCompanion.insert(
          id: 'w1_ex',
          workoutId: 'w1',
          exerciseId: 'mine',
          orderIndex: 0,
        ),
      ],
      const [],
    );
    for (final String name in <String>[
      'pre_import_snapshot_1794310503598.json',
      'pre_import_snapshot_1794398970790.json',
      'unrelated.txt',
    ]) {
      File('${snapshotDir.path}/$name').writeAsStringSync('{}');
    }
  });

  tearDown(() async {
    await database.close();
    snapshotDir.deleteSync(recursive: true);
  });

  Future<List<String>> exerciseIds() async => <String>[
        for (final row in await database
            .customSelect('SELECT id FROM exercises_table ORDER BY id')
            .get())
          row.read<String>('id'),
      ];

  test('own exercises go, even once used; the catalogue stays', () async {
    await service.deleteAllUserData(database);

    expect(await exerciseIds(), <String>['bench']);
    expect(
      await database.customSelect('SELECT id FROM workouts_table').get(),
      isEmpty,
    );
  });

  test('the import snapshots go, and nothing else in their folder', () async {
    await service.deleteAllUserData(
      database,
      snapshotDirPath: snapshotDir.path,
    );

    expect(
      snapshotDir.listSync().map((e) => e.uri.pathSegments.last),
      <String>['unrelated.txt'],
      reason: 'a snapshot is a full copy of the data, name and email '
          'included, and Restore snapshot brought it back',
    );
  });

  test('a failed delete keeps the snapshots', () async {
    await database.close();

    await expectLater(
      service.deleteAllUserData(database, snapshotDirPath: snapshotDir.path),
      throwsA(anything),
    );
    expect(snapshotDir.listSync(), hasLength(3));
    // Reopened, so tearDown's close has something to close.
    database = AppDatabase.forTesting();
  });

  test("a snapshot's time is read from its name", () {
    expect(
      DataExportService.snapshotTakenAt(
        File('${snapshotDir.path}/pre_import_snapshot_1794398970790.json'),
      ),
      DateTime.fromMillisecondsSinceEpoch(1794398970790, isUtc: true).toLocal(),
    );
    expect(
      DataExportService.snapshotTakenAt(File('${snapshotDir.path}/other.json')),
      isNull,
    );
  });
}
