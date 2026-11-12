import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/daos/exercise_dao.dart';
import '../database/daos/program_dao.dart';
import '../database/tables/templates.dart' show kMaxTargetSets;

const _uuid = Uuid();

/// Largest program CSV the importer reads: 1 MB. Five programs of six days
/// and eight exercises are about 15 KB; past this the file is not a program
/// sheet, and splitting it into rows would hold all of it in memory several
/// times over. Checked before the file is read and again in
/// [ProgramImportService.parse].
const int kMaxProgramCsvBytes = 1024 * 1024;

/// The CSV is larger than [kMaxProgramCsvBytes].
class ProgramCsvTooLargeException implements Exception {
  const ProgramCsvTooLargeException(this.size);

  final int size;

  @override
  String toString() =>
      'ProgramCsvTooLargeException: $size (limit $kMaxProgramCsvBytes)';
}

/// Parses a spreadsheet (CSV) into training programs and applies them to the
/// database. Excel can export/save `.csv`, which keeps the import format
/// simple, portable, and free of a native `.xlsx` dependency.
///
/// Expected header (case-insensitive):
/// `program,day,exercise,sets,reps`
///
/// - `program` and `day` group rows into a program and its day-templates.
/// - `exercise` is matched against the seeded catalogue by name.
/// - `sets` is the target number of sets: a whole number from 1 to
///   [kMaxTargetSets]. A blank cell, or no `sets` column, means 1.
/// - `reps` is an optional target-rep string (e.g. `8-12`); empty means AMRAP.
///
/// Nothing in the file is silently dropped or guessed at. Every row that is
/// not imported is accounted for in the preview:
/// - exercises whose names don't match the catalogue are listed in
///   [ProgramImportResult.unknownExercises];
/// - programs whose name is already taken on this device (program names are
///   UNIQUE) are listed in [ProgramImportResult.existingPrograms];
/// - rows with an empty required cell or an unusable `sets` value are listed,
///   by spreadsheet row number, in [ProgramImportResult.rejectedRows].
class ProgramImportService {
  const ProgramImportService();

  /// Throws [ProgramImportException] when the file has no header row with
  /// `program`, `day` and `exercise` columns.
  Future<ProgramImportResult> parse(String csvText, AppDatabase db) async {
    if (csvText.length > kMaxProgramCsvBytes) {
      throw ProgramCsvTooLargeException(csvText.length);
    }
    // Split off the UI isolate: it walks every character of the file.
    final rows = await compute(parseProgramCsv, csvText);
    if (rows.isEmpty) throw const ProgramImportException();

    final header = rows.first.map((c) => c.trim().toLowerCase()).toList();
    final programIndex = header.indexOf('program');
    final dayIndex = header.indexOf('day');
    final exerciseIndex = header.indexOf('exercise');
    final setsIndex = header.indexOf('sets');
    final repsIndex = header.indexOf('reps');
    if (programIndex < 0 || dayIndex < 0 || exerciseIndex < 0) {
      throw const ProgramImportException();
    }

    // Names and aliases, as the workout importer reads them: a programme
    // written with coaching names still lands on catalogue exercises.
    final exerciseNameToId = await ExerciseDao(db).exerciseIdsByLookupName();
    final Set<String> takenProgramNames =
        await ProgramDao(db).allProgramNames();

    final programMap = <String, Map<String, List<ImportedExercise>>>{};
    final unknownExercises = <String>[];
    final existingPrograms = <String>[];
    final rejectedRows = <ProgramImportRowIssue>[];

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      // Numbered as a spreadsheet app shows them: the header is row 1.
      final int rowNumber = i + 1;
      if (row.every((cell) => cell.trim().isEmpty)) continue;
      final programName = _cell(row, programIndex);
      final dayName = _cell(row, dayIndex);
      final exerciseName = _cell(row, exerciseIndex);
      if (programName.isEmpty || dayName.isEmpty || exerciseName.isEmpty) {
        rejectedRows.add(
          ProgramImportRowIssue(
            rowNumber: rowNumber,
            problem: ProgramImportRowProblem.missingField,
          ),
        );
        continue;
      }

      // Inserting it would break the UNIQUE name and fail the whole import,
      // so it is left out and named in the preview instead.
      if (takenProgramNames.contains(programName)) {
        if (!existingPrograms.contains(programName)) {
          existingPrograms.add(programName);
        }
        continue;
      }

      final exerciseId = exerciseNameToId[normalizeExerciseName(exerciseName)];
      if (exerciseId == null) {
        if (!unknownExercises.contains(exerciseName)) {
          unknownExercises.add(exerciseName);
        }
        continue;
      }

      final String setsText = _cell(row, setsIndex);
      final int? sets = setsText.isEmpty ? 1 : int.tryParse(setsText);
      if (sets == null || sets < 1 || sets > kMaxTargetSets) {
        rejectedRows.add(
          ProgramImportRowIssue(
            rowNumber: rowNumber,
            problem: ProgramImportRowProblem.invalidSets,
          ),
        );
        continue;
      }
      final reps = repsIndex < 0 ? null : _nullableCell(row, repsIndex);

      // Map literals keep insertion order, so programs and days come out in
      // the order they first appear in the file.
      programMap
          .putIfAbsent(programName, () => {})
          .putIfAbsent(dayName, () => <ImportedExercise>[])
          .add(
            ImportedExercise(
              exerciseId: exerciseId,
              exerciseName: exerciseName,
              sets: sets,
              reps: reps,
            ),
          );
    }

    final programs = [
      for (final MapEntry(key: name, value: days) in programMap.entries)
        ImportedProgram(
          name: name,
          days: [
            for (final entry in days.entries)
              ImportedDay(dayName: entry.key, exercises: entry.value),
          ],
        ),
    ];

    return ProgramImportResult(
      programs: programs,
      unknownExercises: unknownExercises,
      existingPrograms: existingPrograms,
      rejectedRows: rejectedRows,
      totalDays: programs.fold(0, (sum, p) => sum + p.days.length),
      totalExercises: programs.fold(0,
          (sum, p) => sum + p.days.fold(0, (s, d) => s + d.exercises.length)),
    );
  }

  /// Inserts parsed programs. Exercises listed in [result.unknownExercises]
  /// are already excluded, so this is a straightforward bulk write.
  Future<void> apply(AppDatabase db, ProgramImportResult result) {
    return db.transaction(() async {
      final dao = ProgramDao(db);
      final now = DateTime.now().toUtc();

      for (final program in result.programs) {
        await dao.insertProgram(
          ProgramsTableCompanion.insert(
            id: _uuid.v4(),
            name: program.name,
            // No auto-generated description: `description` is a freeform
            // field the user can edit (see program_editor_page.dart), and
            // the day count it would restate already renders localized in
            // the detail page's StatStrip.
            splitType: const Value('custom'),
            createdAt: now,
            updatedAt: now,
          ),
          [
            for (var i = 0; i < program.days.length; i++)
              _dayInsert(program.days[i], i, now),
          ],
        );
      }
    });
  }

  ProgramDayInsert _dayInsert(
    ImportedDay day,
    int index,
    DateTime now,
  ) {
    final templateId = _uuid.v4();
    return ProgramDayInsert(
      id: _uuid.v4(),
      dayName: day.dayName,
      orderIndex: index,
      template: TemplatesTableCompanion.insert(
        id: templateId,
        // A UUID, as in the program editor: template names are UNIQUE and
        // never shown, and "<program> <day>" collided with the templates a
        // deleted program leaves behind, and within one file ("A B" + "C"
        // against "A" + "B C").
        name: _uuid.v4(),
        createdAt: now,
        updatedAt: now,
      ),
      exercises: [
        for (var j = 0; j < day.exercises.length; j++)
          TemplateExercisesTableCompanion.insert(
            id: _uuid.v4(),
            templateId: templateId,
            exerciseId: day.exercises[j].exerciseId,
            orderIndex: j,
            targetSets: day.exercises[j].sets,
            targetReps: day.exercises[j].reps == null
                ? const Value.absent()
                : Value(day.exercises[j].reps),
          ),
      ],
    );
  }

  /// The trimmed cell, or '' for a short row or an optional column the
  /// header does not have (index -1).
  String _cell(List<String> row, int index) =>
      index >= 0 && index < row.length ? row[index].trim() : '';

  String? _nullableCell(List<String> row, int index) {
    final value = _cell(row, index);
    return value.isEmpty ? null : value;
  }

}

/// Thrown when a spreadsheet is empty or missing the required header columns.
///
/// Carries no message: this is a service class with no `BuildContext`, and
/// the previous hardcoded-English message shipped verbatim to the UI even
/// under Arabic. The catch site resolves the localized copy instead.
class ProgramImportException implements Exception {
  const ProgramImportException();
}

/// Result of parsing a spreadsheet, before writing to the database.
class ProgramImportResult {
  const ProgramImportResult({
    required this.programs,
    required this.unknownExercises,
    required this.totalDays,
    required this.totalExercises,
    this.existingPrograms = const [],
    this.rejectedRows = const [],
  });

  final List<ImportedProgram> programs;
  final List<String> unknownExercises;

  /// Program names in the file that already exist on this device, in file
  /// order. None of their rows are imported.
  final List<String> existingPrograms;

  /// Rows left out because a cell was empty or unusable, in file order.
  final List<ProgramImportRowIssue> rejectedRows;

  final int totalDays;
  final int totalExercises;
}

/// Why a spreadsheet row was left out of an import.
enum ProgramImportRowProblem {
  /// The `program`, `day` or `exercise` cell is empty.
  missingField,

  /// The `sets` cell is not a whole number from 1 to [kMaxTargetSets].
  invalidSets,
}

/// One spreadsheet row that was left out of an import, and why.
class ProgramImportRowIssue {
  const ProgramImportRowIssue({required this.rowNumber, required this.problem});

  /// The row number a spreadsheet app shows for it; the header is row 1.
  final int rowNumber;
  final ProgramImportRowProblem problem;
}

class ImportedProgram {
  const ImportedProgram({required this.name, required this.days});

  final String name;
  final List<ImportedDay> days;
}

class ImportedDay {
  const ImportedDay({required this.dayName, required this.exercises});

  final String dayName;
  final List<ImportedExercise> exercises;
}

class ImportedExercise {
  const ImportedExercise({
    required this.exerciseId,
    required this.exerciseName,
    required this.sets,
    this.reps,
  });

  final String exerciseId;
  final String exerciseName;
  final int sets;
  final String? reps;
}

/// Splits a program CSV into rows of cells, without the byte-order mark
/// Excel's "CSV UTF-8" puts first. Top level so `compute` can run it on
/// another isolate.
@visibleForTesting
List<List<String>> parseProgramCsv(String text) =>
    _parseCsv(_withoutByteOrderMark(text));

/// Excel's "CSV UTF-8" starts the file with a byte-order mark, which would
/// otherwise stick to the first header cell and hide the `program` column.
String _withoutByteOrderMark(String text) =>
    text.startsWith('﻿') ? text.substring(1) : text;

/// Minimal RFC-4180 CSV parser (handles quoted fields and embedded
/// commas/newlines). Deliberately small — the import format is simple.
List<List<String>> _parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (inQuotes) {
      if (char == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(char);
      }
    } else if (char == '"') {
      inQuotes = true;
    } else if (char == ',') {
      row.add(field.toString());
      field = StringBuffer();
    } else if (char == '\n') {
      row.add(field.toString());
      rows.add(row);
      row = <String>[];
      field = StringBuffer();
    } else if (char == '\r') {
      // ignore — \r\n handled by the \n branch
    } else {
      field.write(char);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}
