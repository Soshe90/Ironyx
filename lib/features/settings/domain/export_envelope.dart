import 'dart:convert';

/// Whether an import should merge into existing data or replace it entirely.
enum ImportMode { merge, replace }

/// Thrown when an import file fails validation before any data is touched.
class ImportValidationException implements Exception {
  ImportValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// ADR-7 versioned export envelope: every export/import file carries a
/// [formatVersion] independent of the app version, so a future format
/// change can detect and migrate (or reject) old files explicitly rather
/// than best-effort parsing an unversioned one.
///
/// [formatVersion] 1 is the only version that has ever existed — there is
/// no migration path to write yet, only the rejection path for anything
/// else.
class ImportEnvelope {
  const ImportEnvelope({
    required this.formatVersion,
    required this.dbSchemaVersion,
    required this.appVersion,
    required this.exportedAt,
    required this.tables,
  });

  final int formatVersion;
  final int dbSchemaVersion;
  final String appVersion;
  final DateTime exportedAt;

  /// Table name (as stored in sqlite, e.g. `workouts_table`) to its rows,
  /// each row a raw column-name-to-value map exactly as read from sqlite
  /// (dates as epoch ints, bools as 0/1 — the same representation
  /// `INSERT`ed back in, never reinterpreted).
  final Map<String, List<Map<String, Object?>>> tables;

  /// Parses and validates the envelope header. Throws
  /// [ImportValidationException] with a user-facing message if the file
  /// isn't a FitTrack export or carries an unrecognized [formatVersion].
  factory ImportEnvelope.parse(String jsonContent,
      {required int currentFormatVersion}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonContent);
    } on FormatException {
      throw ImportValidationException(
          'This file is not a valid FitTrack export.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw ImportValidationException(
          'This file is not a valid FitTrack export.');
    }

    final Object? rawFormatVersion = decoded['formatVersion'];
    if (rawFormatVersion is! int) {
      throw ImportValidationException(
          'This file is not a valid FitTrack export.');
    }
    if (rawFormatVersion > currentFormatVersion) {
      throw ImportValidationException(
        'This backup was made with a newer version of FitTrack '
        '(format $rawFormatVersion). Update the app before importing.',
      );
    }
    if (rawFormatVersion < currentFormatVersion) {
      throw ImportValidationException(
        'This backup format (version $rawFormatVersion) is no longer supported.',
      );
    }

    final Object? rawSchemaVersion = decoded['dbSchemaVersion'];
    final Object? rawAppVersion = decoded['appVersion'];
    final Object? rawExportedAt = decoded['exportedAt'];
    if (rawSchemaVersion is! int ||
        rawSchemaVersion < 1 ||
        rawAppVersion is! String ||
        rawAppVersion.trim().isEmpty ||
        rawExportedAt is! String ||
        DateTime.tryParse(rawExportedAt) == null) {
      throw ImportValidationException(
          'This file is not a valid FitTrack export.');
    }

    final Object? rawTables = decoded['tables'];
    if (rawTables is! Map<String, dynamic>) {
      throw ImportValidationException(
          'This file is not a valid FitTrack export.');
    }
    final Map<String, List<Map<String, Object?>>> tables;
    try {
      tables = {
        for (final entry in rawTables.entries)
          entry.key: (entry.value as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((row) => row.cast<String, Object?>())
              .toList(),
      };
    } on TypeError {
      throw ImportValidationException(
          'This file is not a valid FitTrack export.');
    }

    return ImportEnvelope(
      formatVersion: rawFormatVersion,
      dbSchemaVersion: rawSchemaVersion,
      appVersion: rawAppVersion,
      exportedAt: DateTime.parse(rawExportedAt),
      tables: tables,
    );
  }

  /// Row counts per table, for the pre-import confirmation preview.
  Map<String, int> get counts => {
        for (final entry in tables.entries) entry.key: entry.value.length,
      };
}
