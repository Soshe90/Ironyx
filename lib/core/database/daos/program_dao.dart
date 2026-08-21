import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/exercises.dart';
import '../tables/programs.dart';
import '../tables/templates.dart';

part 'program_dao.g.dart';

@DriftAccessor(
  tables: [
    ProgramsTable,
    ProgramTemplatesTable,
    TemplatesTable,
    TemplateExercisesTable,
    ExercisesTable,
  ],
)
class ProgramDao extends DatabaseAccessor<AppDatabase> with _$ProgramDaoMixin {
  ProgramDao(super.db);

  /// Watch all programs, ordered by name, each with its day count.
  Stream<List<ProgramSummary>> watchAll() {
    return customSelect(
      '''
      SELECT
        p.id AS id,
        p.name AS name,
        p.description AS description,
        p.split_type AS split_type,
        p.created_at AS created_at,
        p.updated_at AS updated_at,
        p.is_built_in AS is_built_in,
        (SELECT COUNT(*) FROM program_templates_table pt
          WHERE pt.program_id = p.id) AS day_count
      FROM programs_table p
      ORDER BY p.name ASC
      ''',
      readsFrom: {programsTable, programTemplatesTable},
    ).watch().map((rows) => rows.map((row) {
          return ProgramSummary(
            program: Program(
              id: row.read<String>('id'),
              name: row.read<String>('name'),
              description: row.readNullable<String>('description'),
              splitType: row.readNullable<String>('split_type'),
              createdAt: row.read<DateTime>('created_at'),
              updatedAt: row.read<DateTime>('updated_at'),
              isBuiltIn: row.read<bool>('is_built_in'),
            ),
            dayCount: row.read<int>('day_count'),
          );
        }).toList());
  }

  /// Watch all programs, ordered by name (full rows).
  Stream<List<Program>> watchPrograms() =>
      (select(programsTable)..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch()
          .map((rows) => rows.map<Program>(Program.fromDrift).toList());

  /// Load one program with its ordered day-templates and each day's
  /// exercises (exercise id + name + targets).
  Future<ProgramDetail?> getDetail(String programId) async {
    final program = await (select(programsTable)
          ..where((t) => t.id.equals(programId)))
        .getSingleOrNull();
    if (program == null) return null;

    final linkRows = await (select(programTemplatesTable).join([
      innerJoin(
        templatesTable,
        templatesTable.id.equalsExp(programTemplatesTable.templateId),
      ),
    ])
          ..where(programTemplatesTable.programId.equals(programId))
          ..orderBy([OrderingTerm.asc(programTemplatesTable.orderIndex)]))
        .get();

    final days = <ProgramDay>[];
    for (final link in linkRows) {
      final linkRow = link.readTable(programTemplatesTable);
      final templateRow = link.readTable(templatesTable);

      final exerciseRows = await (select(templateExercisesTable).join([
        innerJoin(
          exercisesTable,
          exercisesTable.id.equalsExp(templateExercisesTable.exerciseId),
        ),
      ])
            ..where(templateExercisesTable.templateId.equals(templateRow.id))
            ..orderBy([OrderingTerm.asc(templateExercisesTable.orderIndex)]))
          .get();

      days.add(
        ProgramDay(
          dayName: linkRow.dayName,
          templateId: templateRow.id,
          templateName: templateRow.name,
          exercises: [
            for (final ex in exerciseRows)
              ProgramDayExercise(
                exerciseId: ex.readTable(templateExercisesTable).exerciseId,
                exerciseName: ex.readTable(exercisesTable).name,
                targetSets: ex.readTable(templateExercisesTable).targetSets,
                targetReps: ex.readTable(templateExercisesTable).targetReps,
                targetRpeTimes10:
                    ex.readTable(templateExercisesTable).targetRpeTimes10,
                note: ex.readTable(templateExercisesTable).note,
              ),
          ],
        ),
      );
    }

    return ProgramDetail(
      program: Program.fromDrift(program),
      days: days,
    );
  }

  /// Insert a program with its day-templates (each a template + its
  /// exercises) in a single transaction.
  Future<String> insertProgram(
    ProgramsTableCompanion program,
    List<ProgramDayInsert> days,
  ) {
    return transaction(() async {
      await into(programsTable).insert(program);
      await _insertDays(program.id.value, days);
      return program.id.value;
    });
  }

  /// Renames/updates a program's metadata and replaces its day-templates
  /// entirely with [days], in one transaction. Used by the program editor —
  /// simpler and safer than diffing individual day/exercise rows against
  /// whatever the user rearranged in the UI.
  Future<void> updateProgramWithDays(
    String programId, {
    required String name,
    String? description,
    String? splitType,
    required List<ProgramDayInsert> days,
  }) {
    return transaction(() async {
      await (update(programsTable)..where((t) => t.id.equals(programId)))
          .write(
        ProgramsTableCompanion(
          name: Value(name),
          description: Value(description),
          splitType: Value(splitType),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

      final existingLinks = await (select(programTemplatesTable)
            ..where((t) => t.programId.equals(programId)))
          .get();
      for (final link in existingLinks) {
        await (delete(templatesTable)..where((t) => t.id.equals(link.templateId)))
            .go();
      }

      await _insertDays(programId, days);
    });
  }

  /// Shared by [insertProgram] and [updateProgramWithDays]: inserts each
  /// day's template, its exercises, and the program↔template link.
  Future<void> _insertDays(String programId, List<ProgramDayInsert> days) async {
    for (final day in days) {
      final template = day.template;
      await into(templatesTable).insert(template);
      await batch(
        (b) => b.insertAll(templateExercisesTable, day.exercises),
      );
      await into(programTemplatesTable).insert(
        ProgramTemplatesTableCompanion.insert(
          id: day.id,
          programId: programId,
          templateId: template.id.value,
          dayName: day.dayName,
          orderIndex: day.orderIndex,
        ),
      );
    }
  }

  /// Delete a program. Cascades to its day-templates and their exercises.
  Future<void> deleteProgram(String programId) =>
      (delete(programsTable)..where((t) => t.id.equals(programId))).go();

  /// Deletes all built-in programs and their day-templates, leaving
  /// user-created programs untouched. Used by the seeder when the built-in
  /// seed version advances.
  Future<void> deleteBuiltInPrograms() {
    return transaction(() async {
      final templateIds = await (select(programTemplatesTable).join([
        innerJoin(
          programsTable,
          programsTable.id.equalsExp(programTemplatesTable.programId),
        ),
      ])
            ..where(programsTable.isBuiltIn.equals(true)))
          .get()
          .then(
            (rows) => rows
                .map((r) => r.readTable(programTemplatesTable).templateId)
                .toSet(),
          );

      for (final templateId in templateIds) {
        await (delete(templatesTable)..where((t) => t.id.equals(templateId)))
            .go();
      }
      await (delete(programsTable)..where((t) => t.isBuiltIn.equals(true)))
          .go();
    });
  }
}

/// A program plus its day count, for the list view.
class ProgramSummary {
  const ProgramSummary({required this.program, required this.dayCount});

  final Program program;
  final int dayCount;
}

/// One day (template) within a program.
class ProgramDay {
  const ProgramDay({
    required this.dayName,
    required this.templateId,
    required this.templateName,
    required this.exercises,
  });

  final String dayName;
  final String templateId;
  final String templateName;
  final List<ProgramDayExercise> exercises;
}

/// One exercise row within a program day, with display fields resolved.
class ProgramDayExercise {
  const ProgramDayExercise({
    required this.exerciseId,
    required this.exerciseName,
    required this.targetSets,
    this.targetReps,
    this.targetRpeTimes10,
    this.note,
  });

  final String exerciseId;
  final String exerciseName;
  final int targetSets;
  final String? targetReps;
  final int? targetRpeTimes10;
  final String? note;
}

/// The fully assembled view of one program.
class ProgramDetail {
  const ProgramDetail({required this.program, required this.days});

  final Program program;
  final List<ProgramDay> days;
}

/// Input for inserting one day of a program.
class ProgramDayInsert {
  const ProgramDayInsert({
    required this.id,
    required this.dayName,
    required this.orderIndex,
    required this.template,
    required this.exercises,
  });

  final String id;
  final String dayName;
  final int orderIndex;
  final TemplatesTableCompanion template;
  final List<TemplateExercisesTableCompanion> exercises;
}
