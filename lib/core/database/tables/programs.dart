import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';
import 'templates.dart';

part 'programs.freezed.dart';

/// A training program — a named, ordered collection of day-templates.
///
/// The number of days is derived from the [ProgramTemplatesTable] rows, not
/// stored redundantly, so a program can be 3, 4, 5, or any custom number of
/// days without schema changes. [splitType] is a loose, display-only label
/// (`fullBody`, `upperLower`, `ppl`, `custom`) rather than an enum — the app
/// must not hard-code the ways a trainee can split their week.
class ProgramsTable extends Table {
  /// Stable UUID.
  TextColumn get id => text()();

  /// User-visible name. Unique.
  TextColumn get name => text().unique()();

  /// Optional description (e.g. "3 days/week").
  TextColumn get description => text().nullable()();

  /// Optional split label: `fullBody`, `upperLower`, `ppl`, `custom`.
  TextColumn get splitType => text().nullable()();

  /// ISO-8601 UTC creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  /// ISO-8601 UTC last modified timestamp.
  DateTimeColumn get updatedAt => dateTime()();

  /// Whether this is a built-in program (not user-deletable).
  BoolColumn get isBuiltIn => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Links a program to one of its day-templates, in display order.
class ProgramTemplatesTable extends Table {
  /// Stable UUID.
  TextColumn get id => text()();

  /// Parent program.
  TextColumn get programId =>
      text().references(ProgramsTable, #id, onDelete: KeyAction.cascade)();

  /// The day template (a reusable workout structure).
  TextColumn get templateId =>
      text().references(TemplatesTable, #id, onDelete: KeyAction.cascade)();

  /// Display label for this day, e.g. "Workout A" or "Push Day".
  TextColumn get dayName => text()();

  /// Display order within the program (0-based).
  IntColumn get orderIndex => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Freezed model for the program row.
@freezed
abstract class Program with _$Program {
  const factory Program({
    required String id,
    required String name,
    String? description,
    String? splitType,
    required DateTime createdAt,
    required DateTime updatedAt,
    required bool isBuiltIn,
  }) = _Program;

  factory Program.fromDrift(ProgramsTableData row) => Program(
        id: row.id,
        name: row.name,
        description: row.description,
        splitType: row.splitType,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        isBuiltIn: row.isBuiltIn,
      );
}

/// Freezed model for the program↔template link row.
@freezed
abstract class ProgramTemplate with _$ProgramTemplate {
  const factory ProgramTemplate({
    required String id,
    required String programId,
    required String templateId,
    required String dayName,
    required int orderIndex,
  }) = _ProgramTemplate;

  factory ProgramTemplate.fromDrift(ProgramTemplatesTableData row) =>
      ProgramTemplate(
        id: row.id,
        programId: row.programId,
        templateId: row.templateId,
        dayName: row.dayName,
        orderIndex: row.orderIndex,
      );
}
