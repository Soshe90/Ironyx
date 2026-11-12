import 'dart:convert';

/// Whether an import should merge into existing data or replace it entirely.
enum ImportMode { merge, replace }

/// Thrown when an import file fails validation before any data is touched.
/// Why a backup was refused, as the user needs to know it: each is one
/// translated sentence (see `ImportValidationL10n`), where the 22 refusals
/// each had their own English message, shown as they were in any language.
enum ImportProblem {
  /// The file is not an Ironyx export at all.
  notAnExport,

  /// Made by a newer version of the app: updating the app fixes it.
  madeByNewerApp,

  /// Made by a version too old for this app to read.
  tooOld,

  /// A replace would delete data the backup does not have.
  incomplete,

  /// One of its exercises is here already under another id; [subject] is
  /// its name.
  exerciseConflict,

  /// A row, a column or a reference in it is wrong: damaged or edited.
  damaged,

  /// This app's own tables do not match what an export holds: a fault in
  /// the app, not the file.
  appMismatch,
}

class ImportValidationException implements Exception {
  ImportValidationException(
    this.message, {
    this.problem = ImportProblem.damaged,
    this.subject,
  });

  /// The detail, in English, for logs and tests. Not for the user: see
  /// [problem].
  final String message;

  final ImportProblem problem;

  /// What [problem] is about, where it names something (an exercise).
  final String? subject;

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
  /// isn't a Ironyx export or carries an unrecognized [formatVersion].
  factory ImportEnvelope.parse(String jsonContent,
      {required int currentFormatVersion}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonContent);
    } on FormatException {
      throw ImportValidationException('This file is not a valid Ironyx export.',
          problem: ImportProblem.notAnExport);
    }
    if (decoded is! Map<String, dynamic>) {
      throw ImportValidationException('This file is not a valid Ironyx export.',
          problem: ImportProblem.notAnExport);
    }

    final Object? rawFormatVersion = decoded['formatVersion'];
    if (rawFormatVersion is! int) {
      throw ImportValidationException('This file is not a valid Ironyx export.',
          problem: ImportProblem.notAnExport);
    }
    if (rawFormatVersion > currentFormatVersion) {
      throw ImportValidationException(
        'This backup was made with a newer version of Ironyx '
        '(format $rawFormatVersion). Update the app before importing.',
        problem: ImportProblem.madeByNewerApp,
      );
    }
    if (rawFormatVersion < currentFormatVersion) {
      throw ImportValidationException(
        'This backup format (version $rawFormatVersion) is no longer supported.',
        problem: ImportProblem.tooOld,
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
      throw ImportValidationException('This file is not a valid Ironyx export.',
          problem: ImportProblem.notAnExport);
    }

    final Object? rawTables = decoded['tables'];
    if (rawTables is! Map<String, dynamic>) {
      throw ImportValidationException('This file is not a valid Ironyx export.',
          problem: ImportProblem.notAnExport);
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
      throw ImportValidationException('This file is not a valid Ironyx export.',
          problem: ImportProblem.notAnExport);
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
