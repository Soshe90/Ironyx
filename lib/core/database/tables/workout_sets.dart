import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';

import 'workout_exercises.dart';

part 'workout_sets.freezed.dart';

/// WorkoutSet table — one row per set within a workout exercise.
///
/// Weight is stored in **kilograms** (ADR-1).
/// Reps>0 with weight=0 denotes bodyweight reps.
/// For a time-based exercise (`ExercisesTable.isTimeBased`), [reps] is 0 and
/// the hold is recorded in [durationSeconds] instead; [weightKg] still holds
/// any added load (e.g. a weighted plank).
class WorkoutSetsTable extends Table {
  /// Stable UUID.
  TextColumn get id => text()();

  /// Parent workout exercise.
  TextColumn get workoutExerciseId => text().references(
        WorkoutExercisesTable,
        #id,
        onDelete: KeyAction.cascade,
      )();

  /// Set index within the exercise (0-based).
  IntColumn get setIndex => integer()();

  /// Load in kilograms. Always stored in kg.
  RealColumn get weightKg => real()();

  /// Repetitions. 0 for isometric/hold sets where only weight matters.
  IntColumn get reps => integer()();

  /// RPE (Rate of Perceived Exertion) 1–10, nullable.
  /// Stored as integer 10–100 to avoid float precision issues (6.5 → 65).
  IntColumn get rpeTimes10 => integer().nullable()();

  /// Whether this set was completed (vs planned/skipped).
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();

  /// Whether this is a warm-up set.
  /// Warm-up sets are excluded from volume totals (ADR-125).
  BoolColumn get isWarmup => boolean().withDefault(const Constant(false))();

  /// Rest time taken before this set, in seconds. Null = not tracked.
  IntColumn get restSeconds => integer().nullable()();

  /// Held duration for a time-based (isometric) set, in seconds. Null for
  /// ordinary rep-based sets; see `ExercisesTable.isTimeBased`.
  IntColumn get durationSeconds => integer().nullable()();

  /// Optional note for this specific set.
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Freezed model for the workout set row.
@freezed
abstract class WorkoutSet with _$WorkoutSet {
  const WorkoutSet._();

  const factory WorkoutSet({
    required String id,
    required String workoutExerciseId,
    required int setIndex,
    required double weightKg,
    required int reps,
    int? rpeTimes10,
    required bool isCompleted,
    required bool isWarmup,
    int? restSeconds,
    int? durationSeconds,
    String? note,
  }) = _WorkoutSet;

  factory WorkoutSet.fromDrift(WorkoutSetsTableData row) => WorkoutSet(
        id: row.id,
        workoutExerciseId: row.workoutExerciseId,
        setIndex: row.setIndex,
        weightKg: row.weightKg,
        reps: row.reps,
        rpeTimes10: row.rpeTimes10,
        isCompleted: row.isCompleted,
        isWarmup: row.isWarmup,
        restSeconds: row.restSeconds,
        durationSeconds: row.durationSeconds,
        note: row.note,
      );

  /// Convenience: volume for this set in kg.
  double get volumeKg => weightKg * reps;

  /// Convenience: estimated 1RM using Epley formula (ADR-123).
  /// Only valid for 1–12 reps; returns weightKg directly at reps == 1.
  double? get estimated1RM {
    if (reps == 1) return weightKg;
    if (reps >= 1 && reps <= 12) {
      return weightKg * (1 + reps / 30.0);
    }
    return null;
  }
}
