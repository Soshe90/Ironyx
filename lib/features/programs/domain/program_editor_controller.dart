import 'dart:async';

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/program_dao.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/theme/app_spacing.dart';
import 'program_draft.dart';

part 'program_editor_controller.g.dart';

const _uuid = Uuid();

/// Owns the in-progress edit of a program: a brand new one when
/// [programId] is null, or an existing one loaded from the DB. Built-in
/// programs are editable; saving one converts it to a custom program.
///
/// Auto-saves on a debounce once the draft is structurally valid (a named
/// program with at least one day that each have at least one exercise) —
/// the same rule [ProgramEditorPage._save] enforces before allowing an
/// explicit save. A brand new program's first auto-save inserts a real row
/// and remembers its id ([_persistedId]); every write after that, auto-save
/// or explicit, updates that same row rather than inserting another.
@riverpod
class ProgramEditorController extends _$ProgramEditorController {
  /// Captured once so a dispose-time flush can still reach the database
  /// after this (autoDispose) provider's own `ref` has stopped being valid
  /// to read from. `programDaoProvider` is `keepAlive`, so the DAO instance
  /// itself outlives this notifier regardless.
  late final ProgramDao _dao;

  /// The id of the row this draft has actually been written to, or null if
  /// it never has been. Starts as [programId] (an existing program being
  /// edited) and, for a brand new one, is set the moment the first
  /// insert-worthy auto-save fires.
  String? _persistedId;

  /// Mirrors `state.value`, but as a plain field rather than a getter that
  /// runs through `Ref`. Riverpod forbids touching `state`/`ref` from
  /// inside a dispose callback (`_debugCallbackStack` assertion) — this is
  /// what the [build] dispose hook reads instead to flush a pending edit.
  ProgramDraft? _latestDraft;

  Timer? _autoSaveTimer;
  bool _dirty = false;

  @override
  Future<ProgramDraft> build(String? programId) async {
    _dao = ref.read(programDaoProvider);
    _persistedId = programId;
    ref.onDispose(() {
      _autoSaveTimer?.cancel();
      // The debounce window may not have elapsed yet when the user
      // navigates away right after an edit — flush whatever is pending
      // rather than silently dropping it.
      if (_dirty) {
        _dirty = false;
        final draft = _latestDraft;
        if (draft != null && _isSaveWorthy(draft)) {
          unawaited(_persist(draft));
        }
      }
    });

    if (programId == null) {
      const draft = ProgramDraft(name: '', days: []);
      _latestDraft = draft;
      return draft;
    }
    final ProgramDetail? detail =
        await ref.watch(programDaoProvider).getDetail(programId);
    if (detail == null) {
      const draft = ProgramDraft(name: '', days: []);
      _latestDraft = draft;
      return draft;
    }
    final draft = ProgramDraft(
      name: detail.program.name,
      description: detail.program.description,
      splitType: detail.program.splitType,
      days: [
        for (final day in detail.days)
          ProgramDraftDay(
            id: _uuid.v4(),
            dayName: day.dayName,
            exercises: [
              for (final exercise in day.exercises)
                ProgramDraftExercise(
                  id: _uuid.v4(),
                  exerciseId: exercise.exerciseId,
                  name: exercise.exerciseName,
                  targetSets: exercise.targetSets,
                  targetReps: exercise.targetReps,
                  supersetGroupId: exercise.supersetGroupId,
                ),
            ],
          ),
      ],
    );
    _latestDraft = draft;
    return draft;
  }

  void setName(String name) => _update((d) => d.copyWith(name: name));

  void setDescription(String? description) =>
      _update((d) => d.copyWith(description: description));

  void addDay() => _update(
        (d) => d.copyWith(
          days: [
            ...d.days,
            ProgramDraftDay(
              id: _uuid.v4(),
              dayName: 'Day ${d.days.length + 1}',
              exercises: const [],
            ),
          ],
        ),
      );

  void removeDay(String dayId) => _update(
      (d) => d.copyWith(days: d.days.where((x) => x.id != dayId).toList()));

  void renameDay(String dayId, String name) =>
      _updateDay(dayId, (day) => day.copyWith(dayName: name));

  void moveDay(String dayId, int delta) => _update((d) {
        final index = d.days.indexWhere((x) => x.id == dayId);
        final target = index + delta;
        if (index < 0 || target < 0 || target >= d.days.length) return d;
        final days = [...d.days];
        final day = days.removeAt(index);
        days.insert(target, day);
        return d.copyWith(days: days);
      });

  void addExercise(
    String dayId, {
    required String exerciseId,
    required String name,
  }) =>
      _updateDay(
        dayId,
        (day) => day.copyWith(
          exercises: [
            ...day.exercises,
            ProgramDraftExercise(
              id: _uuid.v4(),
              exerciseId: exerciseId,
              name: name,
              targetSets: 3,
            ),
          ],
        ),
      );

  void removeExercise(String dayId, String exerciseRowId) => _updateDay(
        dayId,
        (day) => day.copyWith(
          exercises: day.exercises.where((x) => x.id != exerciseRowId).toList(),
        ),
      );

  void setExerciseTargetSets(String dayId, String exerciseRowId, int sets) =>
      _updateExercise(
        dayId,
        exerciseRowId,
        (exercise) => exercise.copyWith(targetSets: sets),
      );

  /// [reps] is always applied verbatim (including `null`, meaning "no
  /// target set / AMRAP" per `TemplateExercisesTable.targetReps`) — unlike
  /// [setExerciseTargetSets], there's no "leave unchanged" case to
  /// distinguish from "clear it".
  void setExerciseTargetReps(
          String dayId, String exerciseRowId, String? reps) =>
      _updateExercise(
        dayId,
        exerciseRowId,
        (exercise) => exercise.copyWith(targetReps: reps),
      );

  void _updateExercise(
    String dayId,
    String exerciseRowId,
    ProgramDraftExercise Function(ProgramDraftExercise) fn,
  ) =>
      _updateDay(
        dayId,
        (day) => day.copyWith(
          exercises: [
            for (final exercise in day.exercises)
              exercise.id == exerciseRowId ? fn(exercise) : exercise,
          ],
        ),
      );

  void moveExercise(String dayId, String exerciseRowId, int delta) =>
      _updateDay(dayId, (day) {
        final index = day.exercises.indexWhere((x) => x.id == exerciseRowId);
        final target = index + delta;
        if (index < 0 || target < 0 || target >= day.exercises.length) {
          return day;
        }
        final exercises = [...day.exercises];
        final exercise = exercises.removeAt(index);
        exercises.insert(target, exercise);
        return day.copyWith(exercises: exercises);
      });

  /// Groups [exerciseRowId] into the same superset as the exercise directly
  /// above it, creating a new group if the one above is standalone.
  ///
  /// The group id is shared by reference: joining an existing group adopts
  /// its id, so a third exercise can extend a two-exercise superset.
  void groupWithPrevious(String dayId, String exerciseRowId) => _updateDay(
        dayId,
        (day) {
          final index = day.exercises.indexWhere((x) => x.id == exerciseRowId);
          if (index <= 0) return day;
          final previous = day.exercises[index - 1];
          final current = day.exercises[index];
          if (previous.supersetGroupId != null &&
              previous.supersetGroupId == current.supersetGroupId) {
            return day; // Already grouped together.
          }
          final groupId = previous.supersetGroupId ?? _uuid.v4();
          return day.copyWith(
            exercises: [
              for (final exercise in day.exercises)
                if (exercise.id == previous.id)
                  exercise.copyWith(supersetGroupId: groupId)
                else if (exercise.id == current.id)
                  exercise.copyWith(supersetGroupId: groupId)
                else
                  exercise,
            ],
          );
        },
      );

  /// Removes [exerciseRowId] from its superset. If that leaves a single
  /// stranded member behind, it is made standalone too — a superset of one
  /// has no meaning.
  void ungroupFromSuperset(String dayId, String exerciseRowId) => _updateDay(
        dayId,
        (day) {
          final index = day.exercises.indexWhere((x) => x.id == exerciseRowId);
          if (index < 0) return day;
          final current = day.exercises[index];
          if (current.supersetGroupId == null) return day;
          final groupId = current.supersetGroupId!;
          final withoutCurrent = day.exercises
              .map((x) =>
                  x.id == current.id ? x.copyWith(supersetGroupId: null) : x)
              .toList();
          final remaining = withoutCurrent
              .where((x) => x.supersetGroupId == groupId)
              .toList();
          if (remaining.length != 1) {
            return day.copyWith(exercises: withoutCurrent);
          }
          return day.copyWith(
            exercises: [
              for (final exercise in withoutCurrent)
                if (exercise.supersetGroupId == groupId)
                  exercise.copyWith(supersetGroupId: null)
                else
                  exercise,
            ],
          );
        },
      );

  /// Explicit save: cancels any pending debounce and writes immediately, so
  /// the caller's returned id and the confirmation it shows both reflect
  /// the true DB state rather than racing the debounce timer.
  Future<String> save() async {
    _autoSaveTimer?.cancel();
    _dirty = false;
    final ProgramDraft? draft = state.value;
    if (draft == null) throw StateError('Program draft is not loaded yet.');
    return _persist(draft);
  }

  /// Same structural rule [ProgramEditorPage._save] validates before
  /// allowing an explicit save — applied here silently, since auto-save has
  /// no UI to surface a "give it a name" message to.
  bool _isSaveWorthy(ProgramDraft draft) =>
      draft.name.trim().isNotEmpty &&
      draft.days.isNotEmpty &&
      draft.days.every((day) => day.exercises.isNotEmpty);

  void _scheduleAutoSave() {
    _dirty = true;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(AppDuration.autoSaveDebounce, () {
      _dirty = false;
      final draft = _latestDraft;
      if (draft == null || !_isSaveWorthy(draft)) return;
      unawaited(_persist(draft));
    });
  }

  /// Inserts a new program on the first write, remembering [_persistedId]
  /// so every write after that — auto-save or explicit — updates the same
  /// row instead of inserting another one.
  Future<String> _persist(ProgramDraft draft) async {
    final DateTime now = DateTime.now().toUtc();
    final List<ProgramDayInsert> days = [
      for (var i = 0; i < draft.days.length; i++)
        _buildDayInsert(draft.days[i], orderIndex: i, now: now),
    ];

    final String? existingId = _persistedId;
    if (existingId == null) {
      final String newId = await _dao.insertProgram(
        ProgramsTableCompanion.insert(
          id: _uuid.v4(),
          name: draft.name,
          description: Value(draft.description),
          splitType: Value(draft.splitType),
          createdAt: now,
          updatedAt: now,
          isBuiltIn: const Value(false),
        ),
        days,
      );
      _persistedId = newId;
      return newId;
    }

    await _dao.updateProgramWithDays(
      existingId,
      name: draft.name,
      description: draft.description,
      splitType: draft.splitType,
      days: days,
    );
    return existingId;
  }

  ProgramDayInsert _buildDayInsert(
    ProgramDraftDay day, {
    required int orderIndex,
    required DateTime now,
  }) {
    // Minted once and reused for both the template row and its exercises'
    // foreign key, rather than building the exercise rows first and
    // patching the id in afterwards.
    final String templateId = _uuid.v4();
    return ProgramDayInsert(
      id: _uuid.v4(),
      dayName: day.dayName,
      orderIndex: orderIndex,
      template: TemplatesTableCompanion.insert(
        id: templateId,
        // Never shown in the UI (see `ProgramDay.templateName`'s callers)
        // — only needs to satisfy the table's unique constraint.
        name: _uuid.v4(),
        createdAt: now,
        updatedAt: now,
      ),
      exercises: [
        for (var j = 0; j < day.exercises.length; j++)
          TemplateExercisesTableCompanion.insert(
            id: _uuid.v4(),
            templateId: templateId,
            exerciseId: day.exercises[j].exerciseId,
            orderIndex: j,
            targetSets: day.exercises[j].targetSets,
            targetReps: Value(day.exercises[j].targetReps),
            supersetGroupId: Value(day.exercises[j].supersetGroupId),
          ),
      ],
    );
  }

  Future<void> delete() async {
    // Cancelled first: a pending auto-save must not resurrect the row a
    // moment after this deletes it.
    _autoSaveTimer?.cancel();
    _dirty = false;
    final String? id = _persistedId;
    if (id == null) return;
    await _dao.deleteProgram(id);
  }

  void _update(ProgramDraft Function(ProgramDraft) fn) {
    final draft = state.value;
    if (draft == null) return;
    final updated = fn(draft);
    state = AsyncData(updated);
    _latestDraft = updated;
    _scheduleAutoSave();
  }

  void _updateDay(String dayId, ProgramDraftDay Function(ProgramDraftDay) fn) {
    _update(
      (d) => d.copyWith(
        days: [
          for (final day in d.days) day.id == dayId ? fn(day) : day,
        ],
      ),
    );
  }
}
