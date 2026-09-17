import 'package:freezed_annotation/freezed_annotation.dart';

part 'workout_draft.freezed.dart';

/// Immutable in-progress workout state.
///
/// Every nested entity has a stable UUID. Widgets must use these IDs as keys
/// and all mutations must address IDs rather than list positions (ADR-5).
@freezed
abstract class WorkoutDraft with _$WorkoutDraft {
  const factory WorkoutDraft({
    required String id,
    required DateTime startedAt,
    required List<DraftExercise> exercises,
  }) = _WorkoutDraft;
}

@freezed
abstract class DraftExercise with _$DraftExercise {
  const factory DraftExercise({
    required String id,
    required String exerciseId,
    required String name,
    required List<DraftSet> sets,
    @Default(false) bool isWarmup,

    /// Whether this exercise logs a held duration instead of reps, e.g. a
    /// plank. Copied from the exercise catalogue at add-time (ADR-6:
    /// catalogue lookups shouldn't be needed to render an already-built
    /// draft).
    @Default(false) bool isTimeBased,

    /// Groups consecutive exercises into a superset. Null means standalone;
    /// exercises sharing a non-null value are performed back-to-back.
    String? supersetGroupId,
  }) = _DraftExercise;
}

@freezed
abstract class DraftSet with _$DraftSet {
  const factory DraftSet({
    required String id,
    @Default(0) double weightKg,
    @Default(0) int reps,
    @Default(false) bool isCompleted,
    @Default(false) bool isWarmup,
    int? rpeTimes10,
    int? restSeconds,
    int? durationSeconds,
  }) = _DraftSet;
}

/// A single exercise to preload when starting a workout from a template.
///
/// Plain data (not freezed) — the active-workout notifier consumes it once
/// and immediately expands it into UUID-keyed [DraftExercise]/[DraftSet]
/// rows, so there is no need for value equality here.
class TemplateExerciseInput {
  const TemplateExerciseInput({
    required this.exerciseId,
    required this.name,
    required this.targetSets,
    this.isTimeBased = false,
    this.supersetGroupId,
  });

  final String exerciseId;
  final String name;

  /// Number of empty set rows to pre-create (1 when unknown).
  final int targetSets;

  /// Whether this exercise logs a held duration instead of reps.
  final bool isTimeBased;

  /// Superset group, copied through to the preloaded [DraftExercise].
  final String? supersetGroupId;
}
