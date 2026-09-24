import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;

import '../../features/settings/domain/export_envelope.dart';
import '../database/app_database.dart';
import '../error_reporting.dart';
import 'export_schema_upgrades.dart';

/// App version written into every export envelope (ADR-7). Kept as a plain
/// constant rather than pulling in `package_info_plus` — the app has no
/// other use for a runtime version lookup yet. Keep in step with the
/// `version:` line in pubspec.yaml.
const String kAppVersion = '1.0.0';

/// Plain data handed to [_encodeExportEnvelope] on a background isolate via
/// [compute]. Has to be a top-level function, not a closure, so this is a
/// record rather than captured locals.
typedef _ExportEnvelopeData = (
  Map<String, List<Map<String, Object?>>> tables,
  int dbSchemaVersion,
  String exportedAt,
  bool indent,
);

/// Builds and encodes the export envelope. Run via [compute] rather than
/// called directly — `JsonEncoder.withIndent` over a year of training data is
/// a non-trivial, non-yielding chunk of CPU work, and this keeps it off the
/// UI isolate. `compute`, not `Isolate.run`: browsers have no real isolate
/// primitive to spawn, so `compute` is Flutter's own cross-platform-safe
/// wrapper for exactly this — a true background isolate on native platforms,
/// running inline in place on web rather than failing there.
String _encodeExportEnvelope(_ExportEnvelopeData data) {
  final (tables, dbSchemaVersion, exportedAt, indent) = data;
  final Map<String, Object?> envelope = {
    'formatVersion': DataExportService.formatVersion,
    'dbSchemaVersion': dbSchemaVersion,
    'appVersion': kAppVersion,
    'exportedAt': exportedAt,
    'tables': tables,
  };
  final JsonEncoder encoder =
      indent ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
  return encoder.convert(envelope);
}

/// [ImportEnvelope.parse] for [compute], which needs a top-level function.
/// Decoding a large export is the mirror image of encoding one above.
ImportEnvelope _parseExportEnvelope(String jsonContent) => ImportEnvelope.parse(
      jsonContent,
      currentFormatVersion: DataExportService.formatVersion,
    );

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
  static const Set<String> catalogueTableNames = {
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

  /// The complete table set written by [buildJsonExport]. Keep this explicit so
  /// adding a table cannot silently produce an export that older validation
  /// treats as complete.
  static const Set<String> expectedTableNames = {
    'exercises_table',
    'muscles_table',
    'equipment_table',
    'exercise_muscles_table',
    'exercise_equipment_table',
    'exercise_instructions_table',
    'exercise_aliases_table',
    'exercise_media_table',
    'exercise_variations_table',
    'exercise_sources_table',
    'exercise_tags_table',
    'workouts_table',
    'workout_exercises_table',
    'workout_sets_table',
    'templates_table',
    'template_exercises_table',
    'programs_table',
    'program_templates_table',
    'timer_sessions_table',
    'timer_intervals_table',
    'timer_presets_table',
    'body_metrics_table',
    'profiles_table',
  };

  /// Full database dump as the versioned JSON envelope.
  ///
  /// [indent] defaults to on for a human-readable export file. The cloud
  /// backup path (the only other caller of this shape) turns it off: that
  /// payload is gzipped immediately and never read directly, and skipping
  /// indentation roughly halves what there is to compress.
  Future<String> buildJsonExport(AppDatabase db, {bool indent = true}) async {
    final Map<String, List<Map<String, Object?>>> tables = {};
    // The reads stay on the calling isolate — Drift's executor is bound to
    // it — but the encode below, over everything read here, does not need
    // to be.
    await db.transaction(() async {
      for (final table in db.allTables) {
        final rows = await db
            .customSelect(
                'SELECT * FROM ${_quoteIdentifier(table.actualTableName)}')
            .get();
        tables[table.actualTableName] = rows.map((r) => r.data).toList();
      }
    });

    final String json = await compute(
      _encodeExportEnvelope,
      (
        tables,
        db.schemaVersion,
        DateTime.now().toUtc().toIso8601String(),
        indent,
      ),
    );
    // Doesn't block anything — a large export is still a valid one — but a
    // year of hard training is ~1.4MB (see `SupabaseCloudBackupService`'s
    // comment), so multiple orders of magnitude past that is worth having a
    // record of once a crash reporter exists, rather than only finding out
    // from a slow upload or an OOM report with no context.
    if (json.length > 20 * 1024 * 1024) {
      reportError(
        'Export payload is unusually large: ${json.length} bytes.',
        null,
        context: 'DataExportService.buildJsonExport',
      );
    }
    return json;
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
  /// file isn't a valid, current-version Ironyx export.
  ImportEnvelope parseImport(String jsonContent) =>
      _parseExportEnvelope(jsonContent);

  /// [parseImport] off the UI isolate, for callers already awaiting
  /// something slow (a download) where a multi-megabyte decode would
  /// otherwise land as a dropped frame. Throws the same
  /// [ImportValidationException].
  Future<ImportEnvelope> parseImportInBackground(String jsonContent) =>
      compute(_parseExportEnvelope, jsonContent);

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
        preserveCatalogue: true,
      );

  Future<void> _applyImport(
    AppDatabase db,
    ImportEnvelope original, {
    required ImportMode mode,
    required String snapshotDirPath,
    required bool createSnapshot,
    required bool preserveCatalogue,
  }) async {
    // Refuses newer and too-old schemas; upgrades everything in between so
    // a backup survives app updates (ADR-7).
    final ImportEnvelope envelope =
        upgradeEnvelope(original, toSchemaVersion: db.schemaVersion);

    final List<String> tableOrder =
        db.allTables.map((t) => t.actualTableName).toList();
    final Set<String> actualTableNames = tableOrder.toSet();
    final missingDatabaseTables =
        expectedTableNames.difference(actualTableNames);
    final extraDatabaseTables = actualTableNames.difference(expectedTableNames);
    if (missingDatabaseTables.isNotEmpty || extraDatabaseTables.isNotEmpty) {
      throw ImportValidationException(
        'This app database does not match the supported export table set: '
        'missing $missingDatabaseTables, extra $extraDatabaseTables.',
      );
    }

    final Set<String> unknownTableNames =
        envelope.tables.keys.toSet().difference(expectedTableNames);
    if (unknownTableNames.isNotEmpty) {
      final List<String> sortedUnknown = unknownTableNames.toList()..sort();
      throw ImportValidationException(
        'This backup references tables this app does not recognize: '
        '${sortedUnknown.join(', ')}.',
      );
    }

    // A replace import that omits a non-catalogue table isn't a smaller
    // export — it's truncated or hand-edited. Treating a missing key as "this
    // table is now empty" would silently delete real user data with nothing
    // to restore it from, so a replace must supply every user-data table
    // explicitly (catalogue tables have their own preservation logic below).
    if (mode == ImportMode.replace) {
      final Set<String> requiredTableNames = preserveCatalogue
          ? tableOrder.toSet().difference(catalogueTableNames)
          : tableOrder.toSet();
      final Set<String> missingTableNames =
          requiredTableNames.difference(envelope.tables.keys.toSet());
      if (missingTableNames.isNotEmpty) {
        final List<String> sortedMissing = missingTableNames.toList()..sort();
        throw ImportValidationException(
          'This backup is missing data for: ${sortedMissing.join(', ')}. '
          'Replacing local data with an incomplete backup would delete it '
          'without anything to restore, so this import was cancelled.',
        );
      }
    }

    await _validateRowsBeforeApply(
      db,
      envelope,
      mode: mode,
      tableOrder: tableOrder,
      preserveCatalogue: preserveCatalogue,
    );

    // Preserve a populated local catalogue during replace so restoring an
    // older backup cannot downgrade it. An empty catalogue is allowed to be
    // restored, which keeps import useful for a fresh database.
    final protectedCatalogueTables = <String>{};
    if (mode == ImportMode.replace && preserveCatalogue) {
      for (final tableName in catalogueTableNames) {
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

    // A protected catalogue is kept as it is, but exercises the backup
    // needs and this device lacks must still arrive: custom exercises (user
    // data that happens to live in the catalogue table) and retired seed
    // exercises a logged workout still uses. Without them every workout
    // referencing one fails its foreign key and the whole restore is lost.
    // Existing rows are never touched, so the catalogue still cannot be
    // downgraded (ADR-7).
    final List<Map<String, Object?>> missingExercises =
        skipInReplace('exercises_table')
            ? await _exercisesMissingLocally(db, envelope)
            : const [];

    if (createSnapshot) {
      final String snapshotJson = await buildJsonExport(db);
      final File snapshotFile = File(
        '$snapshotDirPath/pre_import_snapshot_'
        '${DateTime.now().toUtc().millisecondsSinceEpoch}.json',
      );
      await snapshotFile.writeAsString(snapshotJson);
    }

    await db.transaction(() async {
      if (mode == ImportMode.replace) {
        for (final tableName in tableOrder.reversed) {
          if (skipInReplace(tableName)) continue;
          await db.customStatement(
            'DELETE FROM ${_quoteIdentifier(tableName)}',
          );
        }
      }

      for (final tableName in tableOrder) {
        final List<Map<String, Object?>> rows;
        if (!skipInReplace(tableName)) {
          rows = envelope.tables[tableName] ?? const [];
        } else if (tableName == 'exercises_table') {
          rows = missingExercises;
        } else {
          continue;
        }
        if (rows.isEmpty) continue;

        final Set<String> rowColumns = {
          for (final row in rows) ...row.keys,
        };
        final List<String> columns = rowColumns.toList()..sort();
        final String placeholders = List.filled(columns.length, '?').join(', ');
        final String columnList = columns.map(_quoteIdentifier).join(', ');

        final String quotedTableName = _quoteIdentifier(tableName);
        final String sql = switch (mode) {
          ImportMode.replace =>
            'INSERT INTO $quotedTableName ($columnList) VALUES ($placeholders)',
          ImportMode.merge => 'INSERT INTO $quotedTableName ($columnList) '
              'VALUES ($placeholders) ON CONFLICT(id) DO UPDATE SET '
              '${columns.where((c) => c != 'id').map((c) => '${_quoteIdentifier(c)} = excluded.${_quoteIdentifier(c)}').join(', ')}',
        };

        for (final row in rows) {
          await db.customStatement(sql, [for (final c in columns) row[c]]);
        }
      }
    });
    // `customStatement` never notifies Drift's stream queries (see its own
    // doc comment), so without this every `watch()` in the app — workout
    // history, Progress, Dashboard — would keep showing the pre-import data
    // until the process restarts, even though the rows underneath just
    // changed inside the transaction above.
    db.markTablesUpdated(db.allTables);

    if (createSnapshot) {
      await _cleanupSnapshots(snapshotDirPath);
    }
  }

  /// The backup's exercises that this device lacks and the backup needs:
  /// custom ones, and any a backed-up workout or template uses. An unused
  /// retired seed row is left out — nothing needs it, and it should not be
  /// able to block a restore.
  ///
  /// Throws [ImportValidationException] if one would collide with a local
  /// exercise's unique name or slug — raised here, before the snapshot and
  /// the transaction, rather than as a raw SQLite error halfway through.
  Future<List<Map<String, Object?>>> _exercisesMissingLocally(
    AppDatabase db,
    ImportEnvelope envelope,
  ) async {
    final Set<Object?> used = {
      for (final table in const [
        'workout_exercises_table',
        'template_exercises_table',
      ])
        for (final row
            in envelope.tables[table] ?? const <Map<String, Object?>>[])
          row['exercise_id'],
    };
    final local = await db
        .customSelect('SELECT id, slug, name FROM exercises_table')
        .get();
    final Set<String> localIds = {for (final r in local) r.read<String>('id')};
    final Set<String> localSlugs = {
      for (final r in local) r.read<String>('slug'),
    };
    final Set<String> localNames = {
      for (final r in local) r.read<String>('name'),
    };

    final List<Map<String, Object?>> missing = [
      for (final row in envelope.tables['exercises_table'] ??
          const <Map<String, Object?>>[])
        if (!localIds.contains(row['id']) &&
            (row['is_custom'] == 1 || used.contains(row['id'])))
          row,
    ];
    for (final row in missing) {
      if (localNames.contains(row['name']) ||
          localSlugs.contains(row['slug'])) {
        throw ImportValidationException(
          'This backup contains an exercise "${row['name']}" that this '
          'device already has under a different id, so it cannot be '
          'restored without renaming one of them.',
        );
      }
    }
    return missing;
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

  /// Restores every table, including the exercise catalogue. This is kept
  /// separate from [applyImport] because ordinary user-data replacement must
  /// never silently downgrade local catalogue content.
  Future<void> restoreCompleteDatabase(
    AppDatabase db,
    ImportEnvelope envelope, {
    required String snapshotDirPath,
  }) =>
      _applyImport(
        db,
        envelope,
        mode: ImportMode.replace,
        snapshotDirPath: snapshotDirPath,
        createSnapshot: true,
        preserveCatalogue: false,
      );

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
      preserveCatalogue: false,
    );
  }

  Future<void> _cleanupSnapshots(String snapshotDirPath) async {
    final snapshots = await listSnapshots(snapshotDirPath);
    for (final file in snapshots.skip(3)) {
      await file.delete();
    }
  }

  Future<void> _validateRowsBeforeApply(
    AppDatabase db,
    ImportEnvelope envelope, {
    required ImportMode mode,
    required List<String> tableOrder,
    required bool preserveCatalogue,
  }) async {
    final schemas = <String, List<_ImportColumn>>{};
    for (final tableName in tableOrder) {
      final info = await db
          .customSelect(
            'PRAGMA table_info(${_quoteIdentifier(tableName)})',
          )
          .get();
      schemas[tableName] = [
        for (final row in info)
          _ImportColumn(
            name: row.read<String>('name'),
            type: row.read<String>('type').toUpperCase(),
            required: row.read<int>('notnull') == 1 || row.read<int>('pk') > 0,
            primaryKey: row.read<int>('pk') > 0,
            hasDefault: row.data['dflt_value'] != null,
          ),
      ];
    }

    for (final tableName in tableOrder) {
      final rows = envelope.tables[tableName] ?? const [];
      final columns = schemas[tableName]!;
      final knownColumns = columns.map((column) => column.name).toSet();
      final requiredColumns = columns
          .where((column) => column.required && !column.hasDefault)
          .map((column) => column.name)
          .toSet();
      final ids = <String>{};

      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        final row = rows[rowIndex];
        final unknown = row.keys.toSet().difference(knownColumns);
        if (unknown.isNotEmpty) {
          throw ImportValidationException(
            'Invalid $tableName row ${rowIndex + 1}: unknown column '
            '"${unknown.first}".',
          );
        }
        final missing = requiredColumns.difference(row.keys.toSet());
        if (missing.isNotEmpty) {
          throw ImportValidationException(
            'Invalid $tableName row ${rowIndex + 1}: missing required '
            'column "${missing.first}".',
          );
        }

        final idColumn =
            columns.where((column) => column.primaryKey).firstOrNull;
        if (idColumn != null) {
          final id = row[idColumn.name];
          if (id is! String || id.isEmpty) {
            throw ImportValidationException(
              'Invalid $tableName row ${rowIndex + 1}: primary key '
              '"${idColumn.name}" must be a non-empty string.',
            );
          }
          if (!ids.add(id)) {
            throw ImportValidationException(
              'Invalid $tableName row ${rowIndex + 1}: duplicate primary '
              'key "$id".',
            );
          }
        }

        for (final column in columns) {
          if (!row.containsKey(column.name)) continue;
          _validateValue(
            tableName,
            rowIndex,
            column,
            row[column.name],
            validateIdentifier:
                column.name == 'id' && !catalogueTableNames.contains(tableName),
          );
        }
      }
    }

    await _validateForeignKeys(
      db,
      envelope,
      mode: mode,
      tableOrder: tableOrder,
      schemas: schemas,
      preserveCatalogue: preserveCatalogue,
    );
  }

  void _validateValue(
    String tableName,
    int rowIndex,
    _ImportColumn column,
    Object? value, {
    required bool validateIdentifier,
  }) {
    if (value == null) {
      if (column.required) {
        throw ImportValidationException(
          'Invalid $tableName row ${rowIndex + 1}: required column '
          '"${column.name}" cannot be null.',
        );
      }
      return;
    }
    if (validateIdentifier &&
        column.type == 'TEXT' &&
        value is String &&
        !_hasSafeIdentifierShape(value)) {
      throw ImportValidationException(
        'Invalid $tableName row ${rowIndex + 1}: column "${column.name}" '
        'must be a UUID or a plain alphanumeric identifier.',
      );
    }
    final valid = switch (column.type) {
      'TEXT' => value is String,
      'INTEGER' => value is int &&
          (column.name.startsWith('is_') ? value == 0 || value == 1 : true),
      'REAL' => value is num && value is! bool && value.isFinite,
      _ => true,
    };
    if (!valid) {
      throw ImportValidationException(
        'Invalid $tableName row ${rowIndex + 1}: column "${column.name}" '
        'has an invalid value type.',
      );
    }
  }

  Future<void> _validateForeignKeys(
    AppDatabase db,
    ImportEnvelope envelope, {
    required ImportMode mode,
    required List<String> tableOrder,
    required Map<String, List<_ImportColumn>> schemas,
    required bool preserveCatalogue,
  }) async {
    final importedIds = <String, Set<String>>{};
    for (final tableName in tableOrder) {
      final idColumn =
          schemas[tableName]!.where((column) => column.primaryKey).firstOrNull;
      importedIds[tableName] = {
        for (final row
            in envelope.tables[tableName] ?? const <Map<String, Object?>>[])
          if (idColumn != null && row[idColumn.name] is String)
            row[idColumn.name]! as String,
      };
    }

    final existingIds = <String, Set<String>>{};
    for (final tableName in tableOrder) {
      final idColumn =
          schemas[tableName]!.where((column) => column.primaryKey).firstOrNull;
      if (idColumn == null) continue;
      final rows = await db
          .customSelect(
            'SELECT ${_quoteIdentifier(idColumn.name)} FROM ${_quoteIdentifier(tableName)}',
          )
          .get();
      existingIds[tableName] = {
        for (final row in rows) row.read<String>(idColumn.name),
      };
    }

    final foreignKeys = <String, List<_ImportForeignKey>>{};
    for (final tableName in tableOrder) {
      final rows = await db
          .customSelect(
            'PRAGMA foreign_key_list(${_quoteIdentifier(tableName)})',
          )
          .get();
      foreignKeys[tableName] = [
        for (final row in rows)
          _ImportForeignKey(
            column: row.read<String>('from'),
            parentTable: row.read<String>('table'),
            parentColumn: row.read<String>('to'),
          ),
      ];
    }

    for (final tableName in tableOrder) {
      for (final foreignKey in foreignKeys[tableName]!) {
        final available = <String>{...importedIds[foreignKey.parentTable]!};
        if (mode == ImportMode.merge ||
            (preserveCatalogue &&
                catalogueTableNames.contains(foreignKey.parentTable))) {
          available.addAll(existingIds[foreignKey.parentTable] ?? const {});
        }
        for (var rowIndex = 0;
            rowIndex < (envelope.tables[tableName]?.length ?? 0);
            rowIndex++) {
          final value =
              envelope.tables[tableName]![rowIndex][foreignKey.column];
          if (value is String &&
              !catalogueTableNames.contains(foreignKey.parentTable) &&
              !_hasSafeIdentifierShape(value)) {
            throw ImportValidationException(
              'Invalid $tableName row ${rowIndex + 1}: ${foreignKey.column} '
              'must be a UUID or a plain alphanumeric identifier.',
            );
          }
          if (value is String && !available.contains(value)) {
            throw ImportValidationException(
              'Invalid $tableName row ${rowIndex + 1}: ${foreignKey.column} '
              'references missing ${foreignKey.parentTable}.${foreignKey.parentColumn} '
              '"$value".',
            );
          }
        }
      }
    }
  }

  /// Whether [value] looks like a UUID or a plain alphanumeric identifier —
  /// not a check against the actual set of ids this app has ever issued.
  /// Every id this app has ever generated (`Uuid().v4()`) or shipped in seed
  /// data (`ex_001`, `chest`, `builtin_full_body`, the `local_profile` /
  /// `custom` sentinels) happens to match one of the two shapes below, but
  /// so does any other alphanumeric string — this is a shape sanity check
  /// on import data, not a lookup against known ids. There is no injection
  /// risk either way: every value here is bound as a query parameter, never
  /// interpolated into SQL.
  bool _hasSafeIdentifierShape(String value) {
    if (value == 'local_profile' || value == 'custom') return true;
    if (RegExp(r'^[A-Za-z0-9_]+$').hasMatch(value)) return true;
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
      r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
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
  Future<void> deleteAllUserData(AppDatabase db) async {
    await db.transaction(() async {
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
    // See the matching comment in `_applyImport`: `customStatement` never
    // notifies stream queries, so without this every `watch()` — Tracker
    // history, Progress, Dashboard — would keep showing the just-deleted
    // rows until the app restarts.
    db.markTablesUpdated(db.allTables);
  }

  Future<void> writeStringToFile(String path, String content) =>
      File(path).writeAsString(content);

  Future<String> readStringFromFile(String path) => File(path).readAsString();
}

class _ImportColumn {
  const _ImportColumn({
    required this.name,
    required this.type,
    required this.required,
    required this.primaryKey,
    required this.hasDefault,
  });

  final String name;
  final String type;
  final bool required;
  final bool primaryKey;
  final bool hasDefault;
}

class _ImportForeignKey {
  const _ImportForeignKey({
    required this.column,
    required this.parentTable,
    required this.parentColumn,
  });

  final String column;
  final String parentTable;
  final String parentColumn;
}
