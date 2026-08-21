import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';
import 'equipment.dart';
import 'exercises.dart';

part 'exercise_equipment.freezed.dart';

/// Which equipment an exercise needs.
///
/// Relational replacement for the old single `exercises.equipment` enum
/// column — an exercise can now need more than one piece of equipment
/// (e.g. Dumbbell Incline Row needs a dumbbell *and* an incline bench).
class ExerciseEquipmentTable extends Table {
  TextColumn get id => text()();

  TextColumn get exerciseId =>
      text().references(ExercisesTable, #id, onDelete: KeyAction.cascade)();

  TextColumn get equipmentId =>
      text().references(EquipmentTable, #id, onDelete: KeyAction.restrict)();

  /// Whether this piece is strictly required (vs. an optional variant,
  /// e.g. a bench for an otherwise floor-based movement).
  BoolColumn get isRequired => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Freezed model for an exercise-equipment mapping row.
@freezed
abstract class ExerciseEquipmentLink with _$ExerciseEquipmentLink {
  const factory ExerciseEquipmentLink({
    required String id,
    required String exerciseId,
    required String equipmentId,
    required bool isRequired,
  }) = _ExerciseEquipmentLink;

  factory ExerciseEquipmentLink.fromDrift(ExerciseEquipmentTableData row) =>
      ExerciseEquipmentLink(
        id: row.id,
        exerciseId: row.exerciseId,
        equipmentId: row.equipmentId,
        isRequired: row.isRequired,
      );
}
