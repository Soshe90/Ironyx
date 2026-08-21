import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';
import 'exercises.dart';
import 'muscles.dart';

part 'exercise_muscles.freezed.dart';

/// Which muscles an exercise trains, and how.
///
/// This is the relational replacement for the old
/// `exercises.primaryMuscle` / `secondaryMuscles` columns — "exercises
/// that train lats" becomes a normal join instead of string parsing.
class ExerciseMusclesTable extends Table {
  TextColumn get id => text()();

  TextColumn get exerciseId =>
      text().references(ExercisesTable, #id, onDelete: KeyAction.cascade)();

  TextColumn get muscleId =>
      text().references(MusclesTable, #id, onDelete: KeyAction.restrict)();

  /// primary / secondary / stabilizer.
  TextColumn get role => text()();

  /// Internal curation confidence (0.0-1.0), never shown to users directly
  /// — useful while combining multiple sources, per the data-model plan.
  RealColumn get confidence => real().withDefault(const Constant(1.0))();

  /// Where this muscle mapping came from, e.g. "fittrack" / "wger".
  TextColumn get source => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

enum MuscleRole { primary, secondary, stabilizer }

extension MuscleRoleX on MuscleRole {
  String get label => switch (this) {
        MuscleRole.primary => 'Primary',
        MuscleRole.secondary => 'Secondary',
        MuscleRole.stabilizer => 'Stabilizer',
      };
}

/// Freezed model for an exercise-muscle mapping row.
@freezed
abstract class ExerciseMuscle with _$ExerciseMuscle {
  const factory ExerciseMuscle({
    required String id,
    required String exerciseId,
    required String muscleId,
    required MuscleRole role,
    required double confidence,
    String? source,
  }) = _ExerciseMuscle;

  factory ExerciseMuscle.fromDrift(ExerciseMusclesTableData row) =>
      ExerciseMuscle(
        id: row.id,
        exerciseId: row.exerciseId,
        muscleId: row.muscleId,
        role: MuscleRole.values.byName(row.role),
        confidence: row.confidence,
        source: row.source,
      );
}
