import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';
import 'exercises.dart';

part 'exercise_tags.freezed.dart';

/// Free-form tags for filtering beyond muscle/equipment/pattern, e.g.
/// "hypertrophy", "beginner", "low_back_friendly", "chest_supported".
///
/// Deliberately not curated for an AI workout generator right now (that's
/// parked in v2-ideas.md) — this exists as a filtering primitive the
/// Library UI can use today.
class ExerciseTagsTable extends Table {
  TextColumn get id => text()();

  TextColumn get exerciseId =>
      text().references(ExercisesTable, #id, onDelete: KeyAction.cascade)();

  TextColumn get tag => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Freezed model for a tag row.
@freezed
abstract class ExerciseTag with _$ExerciseTag {
  const factory ExerciseTag({
    required String id,
    required String exerciseId,
    required String tag,
  }) = _ExerciseTag;

  factory ExerciseTag.fromDrift(ExerciseTagsTableData row) => ExerciseTag(
        id: row.id,
        exerciseId: row.exerciseId,
        tag: row.tag,
      );
}
