import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_spacing.dart';
import 'draft_editor_controller.dart';
import 'workout_draft.dart';

part 'active_workout_notifier.g.dart';

const _uuid = Uuid();

/// Owns the active workout draft and persists every mutation.
@Riverpod(keepAlive: true)
class ActiveWorkoutNotifier extends _$ActiveWorkoutNotifier
    implements DraftEditorController {
  static const _prefsKey = 'active_workout_draft';

  Timer? _discardTimer;

  @override
  WorkoutDraft? build() {
    ref.onDispose(() => _discardTimer?.cancel());
    final encoded = ref.watch(sharedPreferencesProvider).getString(_prefsKey);
    if (encoded == null) return null;
    try {
      return _decode(jsonDecode(encoded) as Map<String, dynamic>);
    } on Object {
      // A corrupt draft must not prevent the app from launching.
      return null;
    }
  }

  Future<void> start() async {
    state = WorkoutDraft(
      id: _uuid.v4(),
      startedAt: DateTime.now().toUtc(),
      exercises: const [],
    );
    await _persist();
  }

  /// Starts a workout preloaded from a day-template's exercises.
  ///
  /// Each template exercise becomes a [DraftExercise] with `targetSets`
  /// empty [DraftSet] rows so the user can start filling weights immediately.
  Future<void> startFromTemplate(List<TemplateExerciseInput> exercises) async {
    state = WorkoutDraft(
      id: _uuid.v4(),
      startedAt: DateTime.now().toUtc(),
      exercises: [
        for (final input in exercises)
          DraftExercise(
            id: _uuid.v4(),
            exerciseId: input.exerciseId,
            name: input.name,
            sets: [
              for (var i = 0;
                  i < (input.targetSets < 1 ? 1 : input.targetSets);
                  i++)
                DraftSet(id: _uuid.v4()),
            ],
          ),
      ],
    );
    await _persist();
  }

  Future<void> discard() async {
    _discardTimer?.cancel();
    _discardTimer = null;
    state = null;
    await ref.read(sharedPreferencesProvider).remove(_prefsKey);
  }

  /// Marks the draft for discard after [AppDuration.undoWindow]. The draft
  /// stays intact (and restorable) until the timer fires — call
  /// [cancelScheduledDiscard] within that window to undo.
  void scheduleDiscard() {
    _discardTimer?.cancel();
    _discardTimer = Timer(AppDuration.undoWindow, discard);
  }

  /// Cancels a pending [scheduleDiscard]. The draft is left untouched.
  void cancelScheduledDiscard() {
    _discardTimer?.cancel();
    _discardTimer = null;
  }

  /// Commits the draft and nested rows in one database transaction.
  /// The draft is cleared only after the transaction succeeds.
  Future<void> save() async {
    final draft = state;
    if (draft == null || draft.exercises.isEmpty) return;

    final endedAt = DateTime.now().toUtc();
    final durationSeconds = endedAt.difference(draft.startedAt).inSeconds;
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
            isCompleted: Value(set.isCompleted),
            isWarmup: Value(set.isWarmup || exercise.isWarmup),
          ),
        );
        if (set.isCompleted && !set.isWarmup && !exercise.isWarmup) {
          totalVolumeKg += set.weightKg * set.reps;
        }
      }
    }

    await ref.read(workoutDaoProvider).insertWorkout(
          WorkoutsTableCompanion.insert(
            id: draft.id,
            startedAt: draft.startedAt,
            endedAt: Value(endedAt),
            totalVolumeKg: Value(totalVolumeKg),
            durationSeconds: Value(durationSeconds),
          ),
          workoutExercises,
          workoutSets,
        );
    state = null;
    await ref.read(sharedPreferencesProvider).remove(_prefsKey);
  }

  @override
  Future<void> addExercise({
    required String exerciseId,
    required String name,
  }) async {
    final draft = state;
    if (draft == null) return;
    state = draft.copyWith(
      exercises: [
        ...draft.exercises,
        DraftExercise(
          id: _uuid.v4(),
          exerciseId: exerciseId,
          name: name,
          sets: [DraftSet(id: _uuid.v4())],
        ),
      ],
    );
    await _persist();
  }

  @override
  Future<void> removeExercise(String exerciseId) async {
    final draft = state;
    if (draft == null) return;
    state = draft.copyWith(
      exercises: draft.exercises.where((e) => e.id != exerciseId).toList(),
    );
    await _persist();
  }

  @override
  Future<void> reorderExercise(String exerciseId, int newIndex) async {
    final draft = state;
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
    state = draft.copyWith(exercises: exercises);
    await _persist();
  }

  @override
  Future<void> addSet(String exerciseId) async {
    await _updateExercise(
      exerciseId,
      (exercise) => exercise.copyWith(
        sets: [...exercise.sets, DraftSet(id: _uuid.v4())],
      ),
    );
  }

  @override
  Future<void> duplicateSet(String exerciseId, String setId) async {
    await _updateExercise(exerciseId, (exercise) {
      final index = exercise.sets.indexWhere((set) => set.id == setId);
      if (index < 0) return exercise;
      final source = exercise.sets[index];
      final copy = source.copyWith(id: _uuid.v4());
      final sets = [...exercise.sets]..insert(index + 1, copy);
      return exercise.copyWith(sets: sets);
    });
  }

  @override
  Future<void> removeSet(String exerciseId, String setId) async {
    await _updateExercise(exerciseId, (exercise) {
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
  }) async {
    await _updateExercise(
      exerciseId,
      (exercise) => exercise.copyWith(
        sets: exercise.sets.map((set) {
          if (set.id != setId) return set;
          return set.copyWith(
            weightKg: weightKg ?? set.weightKg,
            reps: reps ?? set.reps,
            isCompleted: isCompleted ?? set.isCompleted,
            isWarmup: isWarmup ?? set.isWarmup,
          );
        }).toList(),
      ),
    );
  }

  Future<void> _updateExercise(
    String exerciseId,
    DraftExercise Function(DraftExercise) update,
  ) async {
    final draft = state;
    if (draft == null) return;
    state = draft.copyWith(
      exercises: draft.exercises
          .map(
            (exercise) =>
                exercise.id == exerciseId ? update(exercise) : exercise,
          )
          .toList(),
    );
    await _persist();
  }

  Future<void> _persist() async {
    final draft = state;
    final prefs = ref.read(sharedPreferencesProvider);
    if (draft == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, jsonEncode(_encode(draft)));
    }
  }

  Map<String, dynamic> _encode(WorkoutDraft draft) => {
        'id': draft.id,
        'startedAt': draft.startedAt.toIso8601String(),
        'exercises': draft.exercises
            .map(
              (exercise) => {
                'id': exercise.id,
                'exerciseId': exercise.exerciseId,
                'name': exercise.name,
                'isWarmup': exercise.isWarmup,
                'sets': exercise.sets
                    .map(
                      (set) => {
                        'id': set.id,
                        'weightKg': set.weightKg,
                        'reps': set.reps,
                        'isCompleted': set.isCompleted,
                        'isWarmup': set.isWarmup,
                      },
                    )
                    .toList(),
              },
            )
            .toList(),
      };

  WorkoutDraft _decode(Map<String, dynamic> json) => WorkoutDraft(
        id: json['id'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        exercises: (json['exercises'] as List<dynamic>).map((item) {
          final exercise = item as Map<String, dynamic>;
          return DraftExercise(
            id: exercise['id'] as String,
            exerciseId: exercise['exerciseId'] as String,
            name: exercise['name'] as String,
            isWarmup: exercise['isWarmup'] as bool? ?? false,
            sets: (exercise['sets'] as List<dynamic>).map((item) {
              final set = item as Map<String, dynamic>;
              return DraftSet(
                id: set['id'] as String,
                weightKg: (set['weightKg'] as num?)?.toDouble() ?? 0,
                reps: set['reps'] as int? ?? 0,
                isCompleted: set['isCompleted'] as bool? ?? false,
                isWarmup: set['isWarmup'] as bool? ?? false,
              );
            }).toList(),
          );
        }).toList(),
      );
}
