import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';

import 'exercises.dart';

part 'templates.freezed.dart';

/// Template table — reusable workout structures.
///
/// A template defines exercises, target sets/reps, and optional notes.
/// It does NOT store actual weight values — those are entered at log time.
class TemplatesTable extends Table {
  /// Stable UUID.
  TextColumn get id => text()();

  /// User-visible name. Unique.
  TextColumn get name => text().unique()();

  /// Optional description.
  TextColumn get description => text().nullable()();

  /// ISO-8601 UTC creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  /// ISO-8601 UTC last modified timestamp.
  DateTimeColumn get updatedAt => dateTime()();

  /// Whether this is a built-in template (not user-deletable).
  BoolColumn get isBuiltIn => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// TemplateExercise table — exercises within a template.
class TemplateExercisesTable extends Table {
  /// Stable UUID.
  TextColumn get id => text()();

  /// Parent template.
  TextColumn get templateId =>
      text().references(TemplatesTable, #id, onDelete: KeyAction.cascade)();

  /// The exercise.
  TextColumn get exerciseId =>
      text().references(ExercisesTable, #id, onDelete: KeyAction.restrict)();

  /// Display order within the template (0-based).
  IntColumn get orderIndex => integer()();

  /// Target number of sets.
  IntColumn get targetSets => integer()();

  /// Target reps per set. Can be a range like "8-12" stored as "8,12".
  /// Null means "as many as possible" (AMRAP).
  TextColumn get targetReps => text().nullable()();

  /// Target RPE. Stored as integer 10–100 (6.5 → 65).
  IntColumn get targetRpeTimes10 => integer().nullable()();

  /// Optional note for this exercise in the template.
  TextColumn get note => text().nullable()();

  /// Groups consecutive exercises into a superset. Null means the exercise
  /// stands alone; exercises sharing a non-null value (within one template)
  /// are performed back-to-back with no rest between them.
  TextColumn get supersetGroupId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Freezed model for the template row.
@freezed
abstract class Template with _$Template {
  const factory Template({
    required String id,
    required String name,
    String? description,
    required DateTime createdAt,
    required DateTime updatedAt,
    required bool isBuiltIn,
  }) = _Template;

  factory Template.fromDrift(TemplatesTableData row) => Template(
        id: row.id,
        name: row.name,
        description: row.description,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        isBuiltIn: row.isBuiltIn,
      );
}

/// Freezed model for the template exercise row.
@freezed
abstract class TemplateExercise with _$TemplateExercise {
  const factory TemplateExercise({
    required String id,
    required String templateId,
    required String exerciseId,
    required int orderIndex,
    required int targetSets,
    String? targetReps,
    int? targetRpeTimes10,
    String? note,
    String? supersetGroupId,
  }) = _TemplateExercise;

  factory TemplateExercise.fromDrift(TemplateExercisesTableData row) =>
      TemplateExercise(
        id: row.id,
        templateId: row.templateId,
        exerciseId: row.exerciseId,
        orderIndex: row.orderIndex,
        targetSets: row.targetSets,
        targetReps: row.targetReps,
        targetRpeTimes10: row.targetRpeTimes10,
        note: row.note,
        supersetGroupId: row.supersetGroupId,
      );
}
