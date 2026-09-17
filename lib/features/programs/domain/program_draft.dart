import 'package:freezed_annotation/freezed_annotation.dart';

part 'program_draft.freezed.dart';

/// In-memory editable state for the program builder/editor. Mirrors
/// `WorkoutDraft`'s role for the tracker: a plain, freely-editable model
/// that gets translated into DB writes only on save, never persisted
/// incrementally.
@freezed
abstract class ProgramDraft with _$ProgramDraft {
  const factory ProgramDraft({
    required String name,
    String? description,
    String? splitType,
    required List<ProgramDraftDay> days,
  }) = _ProgramDraft;
}

/// One editable day within a [ProgramDraft].
@freezed
abstract class ProgramDraftDay with _$ProgramDraftDay {
  const factory ProgramDraftDay({
    required String id,
    required String dayName,
    required List<ProgramDraftExercise> exercises,
  }) = _ProgramDraftDay;
}

/// One editable exercise row within a [ProgramDraftDay].
@freezed
abstract class ProgramDraftExercise with _$ProgramDraftExercise {
  const factory ProgramDraftExercise({
    required String id,
    required String exerciseId,
    required String name,
    required int targetSets,
    String? targetReps,
    String? supersetGroupId,
  }) = _ProgramDraftExercise;
}
