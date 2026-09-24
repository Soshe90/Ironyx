/// Brings an export written against an older database schema up to the
/// current one, so a backup or export file survives app updates.
///
/// ADR-7: "Older versions are migrated by explicit, tested migration
/// functions." Each step mirrors the `AppDatabase.onUpgrade` step with the
/// same number, applied to exported rows instead of live tables. Only what
/// an export can observe needs a step body: a new nullable or defaulted
/// column needs nothing (the import leaves it to the column default), but a
/// new table must appear (a replace refuses an export that omits a user
/// table) and a backfilled column must be backfilled the same way.
///
/// Changing the schema? Add the step here in the same change. The test
/// suite fails if any version between [kOldestUpgradableSchemaVersion] and
/// `AppDatabase.schemaVersion` has no step.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../features/settings/domain/export_envelope.dart';

/// The oldest schema any build of the app has exported. Every version this
/// repository has shipped is 5 or later; anything older predates it and is
/// refused rather than guessed at.
const int kOldestUpgradableSchemaVersion = 5;

typedef ExportTables = Map<String, List<Map<String, Object?>>>;

/// Steps keyed by the schema version they upgrade *from*. Each mutates the
/// copy of the tables it is handed.
@visibleForTesting
final Map<int, void Function(ExportTables tables)> exportSchemaUpgrades = {
  // v5 -> v6: indexes only.
  5: (tables) {},
  // v6 -> v7: profiles table (ADR-8).
  6: (tables) => tables.putIfAbsent('profiles_table', () => []),
  // v7 -> v8: explicit custom-exercise marker, backfilled from the old
  // `seed_version == 0` convention exactly as the database migration does.
  7: (tables) {
    for (final Map<String, Object?> row
        in tables['exercises_table'] ?? const []) {
      row.putIfAbsent('is_custom', () => row['seed_version'] == 0 ? 1 : 0);
    }
  },
  // v8 -> v9: profiles.weekly_session_target, nullable.
  8: (tables) {},
  // v9 -> v10: exercises.is_time_based (default false) and
  // workout_sets.duration_seconds (nullable).
  9: (tables) {},
  // v10 -> v11: superset_group_id on template and workout exercises,
  // nullable.
  10: (tables) {},
};

/// Returns [envelope] upgraded to [toSchemaVersion], or [envelope] itself if
/// it is already there. Never mutates [envelope].
///
/// Throws [ImportValidationException] for an export from a newer schema
/// (this build cannot know what it contains) or one older than
/// [kOldestUpgradableSchemaVersion].
ImportEnvelope upgradeEnvelope(
  ImportEnvelope envelope, {
  required int toSchemaVersion,
}) {
  final int from = envelope.dbSchemaVersion;
  if (from == toSchemaVersion) return envelope;
  if (from > toSchemaVersion) {
    throw ImportValidationException(
      'This backup was made by a newer version of Ironyx (database schema '
      '$from; this app uses $toSchemaVersion). Update the app before '
      'importing it.',
    );
  }
  if (from < kOldestUpgradableSchemaVersion) {
    throw ImportValidationException(
      'This backup is too old to import (database schema $from; the oldest '
      'supported is $kOldestUpgradableSchemaVersion).',
    );
  }

  // Rows are copied so the caller's envelope — possibly shown in an import
  // preview — is never changed underneath it.
  final ExportTables tables = {
    for (final entry in envelope.tables.entries)
      entry.key: [
        for (final row in entry.value) Map<String, Object?>.of(row),
      ],
  };
  for (int version = from; version < toSchemaVersion; version++) {
    final step = exportSchemaUpgrades[version];
    if (step == null) {
      // Unreachable while the completeness test passes; fail closed rather
      // than import data a missing step would have transformed.
      throw ImportValidationException(
        'This app cannot upgrade a backup from database schema $version.',
      );
    }
    step(tables);
  }

  return ImportEnvelope(
    formatVersion: envelope.formatVersion,
    dbSchemaVersion: toSchemaVersion,
    appVersion: envelope.appVersion,
    exportedAt: envelope.exportedAt,
    tables: tables,
  );
}
