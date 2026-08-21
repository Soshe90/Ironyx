import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/program_dao.dart';
import '../../../core/database/database_providers.dart';
import 'program_draft.dart';

part 'program_editor_controller.g.dart';

const _uuid = Uuid();

/// Owns the in-progress edit of a program: a brand new one when
/// [programId] is null, or an existing (always non-built-in — the editor
/// is never opened on a built-in program) one loaded from the DB.
///
/// Not persisted incrementally like `ActiveWorkoutNotifier`'s draft — a
/// half-built program isn't useful to resume later the way a half-logged
/// workout is, so this stays in memory until [save].
@riverpod
class ProgramEditorController extends _$ProgramEditorController {
  @override
  Future<ProgramDraft> build(String? programId) async {
    if (programId == null) {
      return const ProgramDraft(name: '', days: []);
    }
    final ProgramDetail? detail =
        await ref.watch(programDaoProvider).getDetail(programId);
    if (detail == null) {
      return const ProgramDraft(name: '', days: []);
    }
    return ProgramDraft(
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
                ),
            ],
          ),
      ],
    );
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

  void removeDay(String dayId) =>
      _update((d) => d.copyWith(days: d.days.where((x) => x.id != dayId).toList()));

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
          exercises:
              day.exercises.where((x) => x.id != exerciseRowId).toList(),
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
  void setExerciseTargetReps(String dayId, String exerciseRowId, String? reps) =>
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

  /// Saves the draft — inserting a new program, or replacing an existing
  /// one's metadata and days — and returns the program's id.
  Future<String> save() async {
    final ProgramDraft? draft = state.value;
    if (draft == null) throw StateError('Program draft is not loaded yet.');

    final ProgramDao dao = ref.read(programDaoProvider);
    final DateTime now = DateTime.now().toUtc();
    final List<ProgramDayInsert> days = [
      for (var i = 0; i < draft.days.length; i++)
        _buildDayInsert(draft.days[i], orderIndex: i, now: now),
    ];

    if (programId == null) {
      return dao.insertProgram(
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
    }

    await dao.updateProgramWithDays(
      programId!,
      name: draft.name,
      description: draft.description,
      splitType: draft.splitType,
      days: days,
    );
    return programId!;
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
          ),
      ],
    );
  }

  Future<void> delete() async {
    if (programId == null) return;
    await ref.read(programDaoProvider).deleteProgram(programId!);
  }

  void _update(ProgramDraft Function(ProgramDraft) fn) {
    final draft = state.value;
    if (draft == null) return;
    state = AsyncData(fn(draft));
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
