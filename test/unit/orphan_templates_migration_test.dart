import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/program_dao.dart';
import 'package:ironyx/core/services/export_schema_upgrades.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// The v11 -> v12 migration removes the day templates that deleting a
/// program used to leave behind (production review 2026-11-12, finding 9).
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ironyx_orphans_mig');
    dbFile = File('${tempDir.path}/test.sqlite');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<void> addTemplate(AppDatabase db, String id) async {
    final DateTime now = DateTime.utc(2026, 1, 1);
    await db.into(db.templatesTable).insert(
          TemplatesTableCompanion.insert(
            id: id,
            name: 'name_$id',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.into(db.templateExercisesTable).insert(
          TemplateExercisesTableCompanion.insert(
            id: '${id}_ex',
            templateId: id,
            exerciseId: 'bench',
            orderIndex: 0,
            targetSets: 3,
          ),
        );
  }

  test(
      'an upgrade from v11 removes templates no program links to, and only '
      'those', () async {
    // Built at the current schema, then stamped v11: the tables are the
    // same, only the data step differs.
    final AppDatabase before = AppDatabase.withExecutor(NativeDatabase(dbFile));
    await ExerciseDao(before).upsertExercises([
      ExercisesTableCompanion.insert(
        id: 'bench',
        slug: 'bench',
        name: 'Bench',
        category: 'strength',
        difficulty: 'intermediate',
        movementPattern: 'horizontalPush',
        seedVersion: 1,
      ),
    ]);
    await addTemplate(before, 'kept');
    await addTemplate(before, 'orphan');
    final DateTime now = DateTime.utc(2026, 1, 1);
    await before.into(before.programsTable).insert(
          ProgramsTableCompanion.insert(
            id: 'p1',
            name: 'Program',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await before.into(before.programTemplatesTable).insert(
          ProgramTemplatesTableCompanion.insert(
            id: 'link',
            programId: 'p1',
            templateId: 'kept',
            dayName: 'Day 1',
            orderIndex: 0,
          ),
        );
    await before.close();

    final raw = sqlite3.sqlite3.open(dbFile.path);
    raw.execute('PRAGMA user_version = 11');
    raw.close();

    final AppDatabase after = AppDatabase.withExecutor(NativeDatabase(dbFile));
    addTearDown(after.close);
    final templates = await after.select(after.templatesTable).get();
    final exercises = await after.select(after.templateExercisesTable).get();

    expect(templates.map((t) => t.id), ['kept']);
    expect(exercises.map((e) => e.templateId), ['kept']);
    expect(await ProgramDao(after).getDetail('p1'), isNotNull);
  });

  test('the export step removes the same templates from an older backup', () {
    final ExportTables tables = {
      'program_templates_table': [
        {'id': 'link', 'program_id': 'p1', 'template_id': 'kept'},
      ],
      'templates_table': [
        {'id': 'kept'},
        {'id': 'orphan'},
      ],
      'template_exercises_table': [
        {'id': 'a', 'template_id': 'kept'},
        {'id': 'b', 'template_id': 'orphan'},
      ],
    };

    exportSchemaUpgrades[11]!(tables);

    expect(tables['templates_table']!.map((r) => r['id']), ['kept']);
    expect(tables['template_exercises_table']!.map((r) => r['id']), ['a']);
  });

  test('the export step leaves a backup without templates alone', () {
    final ExportTables tables = {'workouts_table': []};

    exportSchemaUpgrades[11]!(tables);

    expect(tables.keys, ['workouts_table']);
  });
}
