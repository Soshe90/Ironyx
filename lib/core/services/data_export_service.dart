import 'dart:convert';
import 'dart:io';

import '../../features/settings/domain/export_envelope.dart';
import '../database/app_database.dart';

/// App version written into every export envelope (ADR-7). Kept as a plain
/// constant rather than pulling in `package_info_plus` — the app has no
/// other use for a runtime version lookup yet.
const String kAppVersion = '0.1.0';

/// Reads, writes, and applies the ADR-7 versioned export envelope, and the
/// destructive "delete all data" flow. The only file this ADR allows
/// `dart:io` in outside a service — file_picker's dialog itself is called
/// from the settings presentation layer, which hands this service a path.
class DataExportService {
  const DataExportService();

  static const int formatVersion = 1;

  /// The exercise catalogue is seed content, not user data (see
  /// [deleteAllUserData]) — a [ImportMode.replace] must not delete or
  /// overwrite a populated local catalogue. Restoring a backup must not
  /// silently downgrade it to an older snapshot.
  static const Set<String> _catalogueTableNames = {
    'exercises_table',
    'exercise_aliases_table',
    'exercise_equipment_table',
    'exercise_instructions_table',
    'exercise_media_table',
    'exercise_muscles_table',
    'exercise_sources_table',
    'exercise_tags_table',
    'exercise_variations_table',
    'muscles_table',
    'equipment_table',
  };

  /// Full database dump as the versioned JSON envelope.
  Future<String> buildJsonExport(AppDatabase db) {
    return db.transaction(() async {
      final Map<String, List<Map<String, Object?>>> tables = {};
      for (final table in db.allTables) {
        final rows = await db
            .customSelect(
                'SELECT * FROM ${_quoteIdentifier(table.actualTableName)}')
            .get();
        tables[table.actualTableName] = rows.map((r) => r.data).toList();
      }

      final Map<String, Object?> envelope = {
        'formatVersion': formatVersion,
        'dbSchemaVersion': db.schemaVersion,
        'appVersion': kAppVersion,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'tables': tables,
      };
      return const JsonEncoder.withIndent('  ').convert(envelope);
    });
  }

  /// One row per completed set, flattened for opening in a spreadsheet.
  /// One-way: nothing ever reads a CSV back in (see [applyImport], which
  /// only accepts the JSON envelope).
  Future<String> buildCsvExport(AppDatabase db) async {
    final rows = await db.customSelect('''
      SELECT
        w.started_at AS started_at,
        e.name AS exercise_name,
        ws.set_index AS set_index,
        ws.weight_kg AS weight_kg,
        ws.reps AS reps,
        ws.is_completed AS is_completed,
        ws.is_warmup AS is_warmup
      FROM workout_sets_table ws
      JOIN workout_exercises_table we ON ws.workout_exercise_id = we.id
      JOIN workouts_table w ON we.workout_id = w.id
      JOIN exercises_table e ON e.id = we.exercise_id
      ORDER BY w.started_at ASC, we.order_index ASC, ws.set_index ASC
    ''').get();

    final buffer = StringBuffer()
      ..writeln('date,exercise,set,weight_kg,reps,completed,warmup');
    for (final row in rows) {
      final DateTime startedAt = row.read<DateTime>('started_at');
      final String exerciseName = _csvField(row.read<String>('exercise_name'));
      final int setIndex = row.read<int>('set_index');
      final double weightKg = row.read<double>('weight_kg');
      final int reps = row.read<int>('reps');
      final bool completed = row.read<bool>('is_completed');
      final bool warmup = row.read<bool>('is_warmup');
      buffer.writeln(
        '${startedAt.toIso8601String()},$exerciseName,$setIndex,'
        '$weightKg,$reps,$completed,$warmup',
      );
    }
    return buffer.toString();
  }

  String _csvField(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Parses and validates an export file's contents. Throws
  /// [ImportValidationException] (safe to show directly to the user) if the
  /// file isn't a valid, current-version FitTrack export.
  ImportEnvelope parseImport(String jsonContent) => ImportEnvelope.parse(
        jsonContent,
        currentFormatVersion: formatVersion,
      );

  /// Applies a validated envelope inside a single transaction, preceded by
  /// automatic snapshot of the current database (ADR-7's safety net —
  /// written to [snapshotDir] and retained for restore from Settings).
  ///
  /// [ImportMode.replace] deletes every non-catalogue table first (children
  /// before parents, so RESTRICT foreign keys never trip) then inserts
  /// everything from the envelope. Catalogue preservation is handled for
  /// intentionally incomplete files; a complete export restores catalogue
  /// rows as supplied. [ImportMode.merge] leaves
  /// existing rows alone and upserts by id — a real `ON CONFLICT DO
  /// UPDATE`, not `INSERT OR REPLACE`, which is a delete-then-insert
  /// internally and trips the same RESTRICT foreign keys a prior seeder bug
  /// already hit once.
  Future<void> applyImport(
    AppDatabase db,
    ImportEnvelope envelope, {
    required ImportMode mode,
    required String snapshotDirPath,
  }) =>
      _applyImport(
        db,
        envelope,
        mode: mode,
        snapshotDirPath: snapshotDirPath,
        createSnapshot: true,
      );

  Future<void> _applyImport(
    AppDatabase db,
    ImportEnvelope envelope, {
    required ImportMode mode,
    required String snapshotDirPath,
    required bool createSnapshot,
  }) async {
    if (envelope.dbSchemaVersion != db.schemaVersion) {
      throw ImportValidationException(
        'This backup uses database schema ${envelope.dbSchemaVersion}, '
        'but this app uses schema ${db.schemaVersion}. Update or migrate '
        'the backup before importing.',
      );
    }

    if (createSnapshot) {
      final String snapshotJson = await buildJsonExport(db);
      final File snapshotFile = File(
        '$snapshotDirPath/pre_import_snapshot_'
        '${DateTime.now().toUtc().millisecondsSinceEpoch}.json',
      );
      await snapshotFile.writeAsString(snapshotJson);
    }

    final List<String> tableOrder =
        db.allTables.map((t) => t.actualTableName).toList();

    // Preserve a populated local catalogue during replace so restoring an
    // older backup cannot downgrade it. An empty catalogue is allowed to be
    // restored, which keeps import useful for a fresh database.
    final protectedCatalogueTables = <String>{};
    if (mode == ImportMode.replace) {
      for (final tableName in _catalogueTableNames) {
        if (!envelope.tables.containsKey(tableName)) {
          protectedCatalogueTables.add(tableName);
          continue;
        }
        final count = await db
            .customSelect(
              'SELECT COUNT(*) AS count FROM ${_quoteIdentifier(tableName)}',
            )
            .getSingle();
        if (count.read<int>('count') > 0) {
          protectedCatalogueTables.add(tableName);
        }
      }
    }
    bool skipInReplace(String tableName) =>
        mode == ImportMode.replace &&
        protectedCatalogueTables.contains(tableName);

    await db.transaction(() async {
      if (mode == ImportMode.replace) {
        for (final tableName in tableOrder.reversed) {
          if (skipInReplace(tableName)) continue;
          await db.customStatement('DELETE FROM $tableName');
        }
      }

      for (final tableName in tableOrder) {
        if (skipInReplace(tableName)) continue;
        final List<Map<String, Object?>> rows =
            envelope.tables[tableName] ?? const [];
        if (rows.isEmpty) continue;

        final Set<String> tableColumns = await _columnsForTable(db, tableName);
        final Set<String> rowColumns = {
          for (final row in rows) ...row.keys,
        };
        final Set<String> unknownColumns = rowColumns.difference(tableColumns);
        if (unknownColumns.isNotEmpty) {
          throw ImportValidationException(
            'This backup contains unknown columns for $tableName: '
            '${unknownColumns.join(', ')}.',
          );
        }

        final List<String> columns = rowColumns.toList()..sort();
        final String placeholders = List.filled(columns.length, '?').join(', ');
        final String columnList = columns.map(_quoteIdentifier).join(', ');

        final String sql = switch (mode) {
          ImportMode.replace =>
            'INSERT INTO $tableName ($columnList) VALUES ($placeholders)',
          ImportMode.merge => 'INSERT INTO $tableName ($columnList) '
              'VALUES ($placeholders) ON CONFLICT(id) DO UPDATE SET '
              '${columns.where((c) => c != 'id').map((c) => '${_quoteIdentifier(c)} = excluded.${_quoteIdentifier(c)}').join(', ')}',
        };

        for (final row in rows) {
          await db.customStatement(sql, [for (final c in columns) row[c]]);
        }
      }
    });

    if (createSnapshot) {
      await _cleanupSnapshots(snapshotDirPath);
    }
  }

  Future<List<File>> listSnapshots(String snapshotDirPath) async {
    final directory = Directory(snapshotDirPath);
    if (!directory.existsSync()) return const [];
    final files = await directory
        .list()
        .where((entity) =>
            entity is File &&
            entity.path.split(Platform.pathSeparator).last.startsWith(
                  'pre_import_snapshot_',
                ) &&
            entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<void> restoreSnapshot(
    AppDatabase db,
    File snapshotFile, {
    required String snapshotDirPath,
  }) async {
    final envelope = parseImport(await snapshotFile.readAsString());
    await _applyImport(
      db,
      envelope,
      mode: ImportMode.replace,
      snapshotDirPath: snapshotDirPath,
      createSnapshot: false,
    );
  }

  Future<void> _cleanupSnapshots(String snapshotDirPath) async {
    final snapshots = await listSnapshots(snapshotDirPath);
    for (final file in snapshots.skip(3)) {
      await file.delete();
    }
  }

  Future<Set<String>> _columnsForTable(
    AppDatabase db,
    String tableName,
  ) async {
    final rows = await db
        .customSelect(
          'PRAGMA table_info(${_quoteIdentifier(tableName)})',
        )
        .get();
    return {
      for (final row in rows) row.read<String>('name'),
    };
  }

  String _quoteIdentifier(String identifier) =>
      '"${identifier.replaceAll('"', '""')}"';

  /// Deletes all user-logged data — workouts, timer sessions, programs,
  /// templates, body metrics — but not the exercise catalogue, which is
  /// seed content, not user data (wiping it would just be silently
  /// restored by the seeder on next launch, which would be surprising).
  ///
  /// Programs must be deleted alongside templates: every program (built-in
  /// or user-created) links to templates via a cascading foreign key, and
  /// deleting only the templates would leave every program behind as an
  /// empty, permanently broken shell. The caller is responsible for calling
  /// `ProgramSeeder.resetSeedVersion()` afterwards so built-in programs are
  /// restored on next seed, the same way the exercise catalogue survives.
  ///
  /// Deletes only the five root tables; every child table (workout
  /// exercises/sets, timer intervals, program↔template links, template
  /// exercises) cascades via its `onDelete: KeyAction.cascade` foreign key.
  Future<void> deleteAllUserData(AppDatabase db) => db.transaction(() async {
        await db.customStatement('DELETE FROM workouts_table');
        await db.customStatement('DELETE FROM timer_sessions_table');
        await db.customStatement('DELETE FROM timer_presets_table');
        await db.customStatement('DELETE FROM programs_table');
        await db.customStatement('DELETE FROM templates_table');
        await db.customStatement('DELETE FROM body_metrics_table');
        // Includes the account association: "delete all my data" must not
        // leave the next person to open the app looking at someone else's
        // name and email.
        await db.customStatement('DELETE FROM profiles_table');
      });

  Future<void> writeStringToFile(String path, String content) =>
      File(path).writeAsString(content);

  Future<String> readStringFromFile(String path) => File(path).readAsString();
}
