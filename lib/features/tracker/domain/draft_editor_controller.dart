/// Shared mutation surface for a [WorkoutDraft]-shaped notifier.
///
/// Implemented by [ActiveWorkoutNotifier] (a new, in-progress workout) and
/// [EditWorkoutNotifier] (an existing workout being revised) so the nested
/// row widgets (ADR-5) can be shared between the active-session screen and
/// the edit screen without knowing which one they are backed by.
abstract interface class DraftEditorController {
  Future<void> addExercise({required String exerciseId, required String name});

  Future<void> removeExercise(String exerciseId);

  Future<void> reorderExercise(String exerciseId, int newIndex);

  Future<void> addSet(String exerciseId);

  Future<void> duplicateSet(String exerciseId, String setId);

  Future<void> removeSet(String exerciseId, String setId);

  Future<void> updateSet(
    String exerciseId,
    String setId, {
    double? weightKg,
    int? reps,
    bool? isCompleted,
    bool? isWarmup,
  });
}
