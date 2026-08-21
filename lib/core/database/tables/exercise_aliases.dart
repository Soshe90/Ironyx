import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';
import 'exercises.dart';

part 'exercise_aliases.freezed.dart';

/// Alternate names a user might search for, e.g. "Incline DB Row" for
/// "Dumbbell Incline Row". Search-only — never displayed as the exercise's
/// name.
class ExerciseAliasesTable extends Table {
  TextColumn get id => text()();

  TextColumn get exerciseId =>
      text().references(ExercisesTable, #id, onDelete: KeyAction.cascade)();

  TextColumn get alias => text()();

  TextColumn get language => text().withDefault(const Constant('en'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Freezed model for an alias row.
@freezed
abstract class ExerciseAlias with _$ExerciseAlias {
  const factory ExerciseAlias({
    required String id,
    required String exerciseId,
    required String alias,
    required String language,
  }) = _ExerciseAlias;

  factory ExerciseAlias.fromDrift(ExerciseAliasesTableData row) =>
      ExerciseAlias(
        id: row.id,
        exerciseId: row.exerciseId,
        alias: row.alias,
        language: row.language,
      );
}
