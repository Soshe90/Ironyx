import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';

import 'exercises.dart';
import 'workouts.dart';

part 'workout_exercises.freezed.dart';

/// WorkoutExercise table — one row per exercise within a workout.
///
/// Order is preserved by [orderIndex] so the log renders in the order
/// the user performed them.
class WorkoutExercisesTable extends Table {
  /// Stable UUID.
  TextColumn get id => text()();

  /// Parent workout.
  TextColumn get workoutId =>
      text().references(WorkoutsTable, #id, onDelete: KeyAction.cascade)();

  /// The exercise performed.
  TextColumn get exerciseId =>
      text().references(ExercisesTable, #id, onDelete: KeyAction.restrict)();

  /// Display order within the workout (0-based).
  IntColumn get orderIndex => integer()();

  /// Whether this exercise was marked as a warm-up.
  /// Warm-up sets are excluded from volume totals (ADR-125).
  BoolColumn get isWarmup => boolean().withDefault(const Constant(false))();

  /// Optional note specific to this exercise in this workout.
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Freezed model for the workout exercise row.
@freezed
abstract class WorkoutExercise with _$WorkoutExercise {
  const factory WorkoutExercise({
    required String id,
    required String workoutId,
    required String exerciseId,
    required int orderIndex,
    required bool isWarmup,
    String? note,
  }) = _WorkoutExercise;

  factory WorkoutExercise.fromDrift(WorkoutExercisesTableData row) =>
      WorkoutExercise(
        id: row.id,
        workoutId: row.workoutId,
        exerciseId: row.exerciseId,
        orderIndex: row.orderIndex,
        isWarmup: row.isWarmup,
        note: row.note,
      );
}
