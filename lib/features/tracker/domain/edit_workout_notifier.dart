import 'dart:async';

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/workout_dao.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/database/tables/workout_sets.dart';
import '../../../core/theme/app_spacing.dart';
import 'draft_editor_controller.dart';
import 'workout_draft.dart';

part 'edit_workout_notifier.g.dart';

const _uuid = Uuid();

/// Loads a previously saved workout into an editable [WorkoutDraft] and
/// writes the revised exercises/sets back — automatically, on a debounce,
/// as well as explicitly via [save].
///
/// Scoped to the edit screen (autoDispose) — unlike [ActiveWorkoutNotifier]
/// there is no local draft to restore after a kill, because every edit is
/// already durable in the database within [AppDuration.autoSaveDebounce].
@riverpod
class EditWorkoutNotifier extends _$EditWorkoutNotifier
    implements DraftEditorController {
  /// Captured once so a dispose-time flush can still reach the database
  /// after this (autoDispose) provider's own `ref` has stopped being valid
  /// to read from. `workoutDaoProvider` is `keepAlive`, so the DAO instance
  /// itself outlives this notifier regardless.
  late final WorkoutDao _dao;

  /// Mirrors `state.value`, but as a plain field rather than a getter that
  /// runs through `Ref`. Riverpod forbids touching `state`/`ref` from
  /// inside a dispose callback (`_debugCallbackStack` assertion) — this is
  /// what the [build] dispose hook reads instead to flush a pending edit.
  WorkoutDraft? _latestDraft;

  Timer? _autoSaveTimer;
  bool _dirty = false;

  @override
  Future<WorkoutDraft> build(String workoutId) async {
    _dao = ref.read(workoutDaoProvider);
    ref.onDispose(() {
      _autoSaveTimer?.cancel();
      // The debounce window may not have elapsed yet when the user
      // navigates away right after an edit — flush whatever is pending
      // rather than silently dropping it.
      if (_dirty) {
        _dirty = false;
        final draft = _latestDraft;
        if (draft != null) unawaited(_writeDraftToDb(draft));
      }
    });

    final details = await ref.watch(workoutDaoProvider).getWithDetails(
          workoutId,
        );
    if (details == null) {
      throw StateError('Workout $workoutId not found');
    }
    final draft = WorkoutDraft(
      id: details.workout.id,
      startedAt: details.workout.startedAt,
      exercises: [
        for (final exercise in details.exercises)
          DraftExercise(
            id: exercise.id,
            exerciseId: exercise.exerciseId,
            name: details.exerciseNames[exercise.id] ?? 'Unknown exercise',
            isWarmup: exercise.isWarmup,
            sets: [
              for (final set in details.setsByExercise[exercise.id] ??
                  const <WorkoutSet>[])
                DraftSet(
                  id: set.id,
                  weightKg: set.weightKg,
                  reps: set.reps,
                  isCompleted: set.isCompleted,
                  isWarmup: set.isWarmup,
                  rpeTimes10: set.rpeTimes10,
                  restSeconds: set.restSeconds,
                ),
            ],
          ),
      ],
    );
    _latestDraft = draft;
    return draft;
  }

  @override
  Future<void> addExercise({
    required String exerciseId,
    required String name,
  }) async {
    final draft = state.value;
    if (draft == null) return;
    _setDraft(
      draft.copyWith(
        exercises: [
          ...draft.exercises,
          DraftExercise(
            id: _uuid.v4(),
            exerciseId: exerciseId,
            name: name,
            sets: [DraftSet(id: _uuid.v4())],
          ),
        ],
      ),
    );
  }

  @override
  Future<void> removeExercise(String exerciseId) async {
    final draft = state.value;
    if (draft == null) return;
    _setDraft(
      draft.copyWith(
        exercises: draft.exercises.where((e) => e.id != exerciseId).toList(),
      ),
    );
  }

  @override
  Future<void> reorderExercise(String exerciseId, int newIndex) async {
    final draft = state.value;
    if (draft == null) return;
    final oldIndex = draft.exercises.indexWhere((e) => e.id == exerciseId);
    if (oldIndex < 0 || newIndex < 0 || newIndex >= draft.exercises.length) {
      return;
    }
    final exercises = [...draft.exercises];
    final exercise = exercises.removeAt(oldIndex);
    final targetIndex =
        newIndex > exercises.length ? exercises.length : newIndex;
    exercises.insert(targetIndex, exercise);
    _setDraft(draft.copyWith(exercises: exercises));
  }

  @override
  Future<void> addSet(String exerciseId) async {
    _updateExercise(
      exerciseId,
      (exercise) => exercise.copyWith(
        sets: [...exercise.sets, DraftSet(id: _uuid.v4())],
      ),
    );
  }

  @override
  Future<void> duplicateSet(String exerciseId, String setId) async {
    _updateExercise(exerciseId, (exercise) {
      final index = exercise.sets.indexWhere((set) => set.id == setId);
      if (index < 0) return exercise;
      final copy = exercise.sets[index].copyWith(id: _uuid.v4());
      final sets = [...exercise.sets]..insert(index + 1, copy);
      return exercise.copyWith(sets: sets);
    });
  }

  @override
  Future<void> removeSet(String exerciseId, String setId) async {
    _updateExercise(exerciseId, (exercise) {
      if (exercise.sets.length <= 1) return exercise;
      return exercise.copyWith(
        sets: exercise.sets.where((set) => set.id != setId).toList(),
      );
    });
  }

  @override
  Future<void> updateSet(
    String exerciseId,
    String setId, {
    double? weightKg,
    int? reps,
    bool? isCompleted,
    bool? isWarmup,
    int? rpeTimes10,
    int? restSeconds,
  }) async {
    _updateExercise(
      exerciseId,
      (exercise) => exercise.copyWith(
        sets: exercise.sets.map((set) {
          if (set.id != setId) return set;
          return set.copyWith(
            weightKg: weightKg ?? set.weightKg,
            reps: reps ?? set.reps,
            isCompleted: isCompleted ?? set.isCompleted,
            isWarmup: isWarmup ?? set.isWarmup,
            rpeTimes10: rpeTimes10 ?? set.rpeTimes10,
            restSeconds: restSeconds ?? set.restSeconds,
          );
        }).toList(),
      ),
    );
  }

  void _updateExercise(
    String exerciseId,
    DraftExercise Function(DraftExercise) update,
  ) {
    final draft = state.value;
    if (draft == null) return;
    _setDraft(
      draft.copyWith(
        exercises: draft.exercises
            .map(
              (exercise) =>
                  exercise.id == exerciseId ? update(exercise) : exercise,
            )
            .toList(),
      ),
    );
  }

  /// Explicit save: cancels any pending debounce and writes immediately, so
  /// the "Save changes" button's confirmation reflects the true DB state
  /// the instant it's shown rather than racing the debounce timer.
  Future<void> save() async {
    _autoSaveTimer?.cancel();
    _dirty = false;
    final draft = state.value;
    if (draft == null || draft.exercises.isEmpty) return;
    await _writeDraftToDb(draft);
    ref.invalidate(workoutDetailProvider(draft.id));
  }

  void _setDraft(WorkoutDraft draft) {
    state = AsyncData(draft);
    _latestDraft = draft;
    _scheduleAutoSave();
  }

  void _scheduleAutoSave() {
    _dirty = true;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(AppDuration.autoSaveDebounce, () {
      _dirty = false;
      final draft = _latestDraft;
      if (draft != null) unawaited(_writeDraftToDb(draft));
    });
  }

  /// Writes the edited exercises and sets back in one transaction.
  ///
  /// Uses [_dao] rather than `ref.read` so this still runs from the
  /// dispose-time flush, after this provider's own `ref` is no longer safe
  /// to touch.
  Future<void> _writeDraftToDb(WorkoutDraft draft) async {
    if (draft.exercises.isEmpty) return;

    final workoutExercises = <WorkoutExercisesTableCompanion>[];
    final workoutSets = <WorkoutSetsTableCompanion>[];
    var totalVolumeKg = 0.0;

    for (var exerciseIndex = 0;
        exerciseIndex < draft.exercises.length;
        exerciseIndex++) {
      final exercise = draft.exercises[exerciseIndex];
      workoutExercises.add(
        WorkoutExercisesTableCompanion.insert(
          id: exercise.id,
          workoutId: draft.id,
          exerciseId: exercise.exerciseId,
          orderIndex: exerciseIndex,
          isWarmup: Value(exercise.isWarmup),
        ),
      );
      for (var setIndex = 0; setIndex < exercise.sets.length; setIndex++) {
        final set = exercise.sets[setIndex];
        workoutSets.add(
          WorkoutSetsTableCompanion.insert(
            id: set.id,
            workoutExerciseId: exercise.id,
            setIndex: setIndex,
            weightKg: set.weightKg,
            reps: set.reps,
            rpeTimes10: Value(set.rpeTimes10),
            restSeconds: Value(set.restSeconds),
            isCompleted: Value(set.isCompleted),
            isWarmup: Value(set.isWarmup || exercise.isWarmup),
          ),
        );
        if (set.isCompleted && !set.isWarmup && !exercise.isWarmup) {
          totalVolumeKg += set.weightKg * set.reps;
        }
      }
    }

    await _dao.updateWorkout(
      workoutId: draft.id,
      totalVolumeKg: totalVolumeKg,
      exercises: workoutExercises,
      sets: workoutSets,
    );
  }
}
