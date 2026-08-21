import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';
import 'exercises.dart';

part 'exercise_instructions.freezed.dart';

/// One ordered step of an exercise's instructions.
///
/// Replaces the old single `exercises.instructions` paragraph so the UI
/// can render "① Setup ② Position ③ Pull" instead of one block of text.
/// Exercises migrated from the old schema land with exactly one step
/// (the old paragraph, verbatim) until manually re-curated into real
/// steps — step boundaries aren't fabricated automatically.
class ExerciseInstructionsTable extends Table {
  TextColumn get id => text()();

  TextColumn get exerciseId =>
      text().references(ExercisesTable, #id, onDelete: KeyAction.cascade)();

  /// 1-based order within the exercise.
  IntColumn get stepNumber => integer()();

  TextColumn get instruction => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Freezed model for an instruction step row.
@freezed
abstract class ExerciseInstruction with _$ExerciseInstruction {
  const factory ExerciseInstruction({
    required String id,
    required String exerciseId,
    required int stepNumber,
    required String instruction,
  }) = _ExerciseInstruction;

  factory ExerciseInstruction.fromDrift(ExerciseInstructionsTableData row) =>
      ExerciseInstruction(
        id: row.id,
        exerciseId: row.exerciseId,
        stepNumber: row.stepNumber,
        instruction: row.instruction,
      );
}
