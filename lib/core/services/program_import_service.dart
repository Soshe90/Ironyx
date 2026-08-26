import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/daos/program_dao.dart';

const _uuid = Uuid();

/// Parses a spreadsheet (CSV) into training programs and applies them to the
/// database. Excel can export/save `.csv`, which keeps the import format
/// simple, portable, and free of a native `.xlsx` dependency.
///
/// Expected header (case-insensitive):
/// `program,day,exercise,sets,reps`
///
/// - `program` and `day` group rows into a program and its day-templates.
/// - `exercise` is matched against the seeded catalogue by name.
/// - `sets` is the target number of sets (integer).
/// - `reps` is an optional target-rep string (e.g. `8-12`); empty means AMRAP.
///
/// Exercises whose names don't match the catalogue are reported in
/// [ProgramImportResult.unknownExercises] and excluded from the write.
class ProgramImportService {
  const ProgramImportService();

  Future<ProgramImportResult> parse(String csvText, AppDatabase db) async {
    final rows = _parseCsv(csvText);
    if (rows.isEmpty) {
      return const ProgramImportResult(
        programs: [],
        unknownExercises: [],
        totalDays: 0,
        totalExercises: 0,
      );
    }

    final header = rows.first.map((c) => c.trim().toLowerCase()).toList();
    final programIndex = header.indexOf('program');
    final dayIndex = header.indexOf('day');
    final exerciseIndex = header.indexOf('exercise');
    final setsIndex = header.indexOf('sets');
    final repsIndex = header.indexOf('reps');
    if (programIndex < 0 || dayIndex < 0 || exerciseIndex < 0) {
      throw const ProgramImportException();
    }

    final exerciseNameToId = await _exerciseNameToId(db);

    final programOrder = <String>[];
    final programMap = <String, Map<String, List<ImportedExercise>>>{};
    final unknownExercises = <String>[];

    for (final row in rows.skip(1)) {
      if (row.every((cell) => cell.trim().isEmpty)) continue;
      final programName = _cell(row, programIndex);
      final dayName = _cell(row, dayIndex);
      final exerciseName = _cell(row, exerciseIndex);
      if (programName.isEmpty || dayName.isEmpty || exerciseName.isEmpty) {
        continue;
      }

      final exerciseId = exerciseNameToId[exerciseName.toLowerCase()];
      if (exerciseId == null) {
        if (!unknownExercises.contains(exerciseName)) {
          unknownExercises.add(exerciseName);
        }
        continue;
      }

      final sets = int.tryParse(_cell(row, setsIndex)) ?? 1;
      final reps = repsIndex < 0 ? null : _nullableCell(row, repsIndex);

      final days = programMap.putIfAbsent(programName, () => {});
      if (!programMap.containsKey(programName) ||
          !programOrder.contains(programName)) {
        programOrder.add(programName);
      }
      final dayExercises =
          days.putIfAbsent(dayName, () => <ImportedExercise>[]);
      dayExercises.add(
        ImportedExercise(
          exerciseId: exerciseId,
          exerciseName: exerciseName,
          sets: sets < 1 ? 1 : sets,
          reps: reps,
        ),
      );
    }

    final programs = [
      for (final name in programOrder)
        ImportedProgram(
          name: name,
          days: [
            for (final entry in programMap[name]!.entries)
              ImportedDay(dayName: entry.key, exercises: entry.value),
          ],
        ),
    ];

    return ProgramImportResult(
      programs: programs,
      unknownExercises: unknownExercises,
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
              _dayInsert(program, program.days[i], i, now),
          ],
        );
      }
    });
  }

  ProgramDayInsert _dayInsert(
    ImportedProgram program,
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
        name: '${program.name} ${day.dayName}',
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

  Future<Map<String, String>> _exerciseNameToId(AppDatabase db) async {
    final rows = await db
        .customSelect(
          'SELECT id, name FROM exercises_table',
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('name').toLowerCase(): row.read<String>('id'),
    };
  }

  String _cell(List<String> row, int index) =>
      index < row.length ? row[index].trim() : '';

  String? _nullableCell(List<String> row, int index) {
    final value = _cell(row, index);
    return value.isEmpty ? null : value;
  }

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
}

/// Thrown when a spreadsheet is missing the required header columns.
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
  });

  final List<ImportedProgram> programs;
  final List<String> unknownExercises;
  final int totalDays;
  final int totalExercises;
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
