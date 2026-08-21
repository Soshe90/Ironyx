import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';
import 'exercises.dart';

part 'exercise_variations.freezed.dart';

/// Links a canonical exercise to a related variant, e.g. Dumbbell Incline
/// Row → single-arm / pause / neutral-grip variants. Directional:
/// [parentExerciseId] is the canonical exercise, [exerciseId] the variant.
class ExerciseVariationsTable extends Table {
  TextColumn get id => text()();

  TextColumn get parentExerciseId =>
      text().references(ExercisesTable, #id, onDelete: KeyAction.cascade)();

  TextColumn get exerciseId =>
      text().references(ExercisesTable, #id, onDelete: KeyAction.cascade)();

  /// e.g. "single_arm", "pause", "neutral_grip". Nullable — not always
  /// worth categorizing.
  TextColumn get variationType => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Freezed model for a variation link row.
@freezed
abstract class ExerciseVariation with _$ExerciseVariation {
  const factory ExerciseVariation({
    required String id,
    required String parentExerciseId,
    required String exerciseId,
    String? variationType,
  }) = _ExerciseVariation;

  factory ExerciseVariation.fromDrift(ExerciseVariationsTableData row) =>
      ExerciseVariation(
        id: row.id,
        parentExerciseId: row.parentExerciseId,
        exerciseId: row.exerciseId,
        variationType: row.variationType,
      );
}
