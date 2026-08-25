import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/tables/exercises.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/page_body.dart';
import '../../../core/widgets/section_header.dart';
import '../../library/presentation/exercise_picker_sheet.dart';
import '../domain/program_draft.dart';
import '../domain/program_editor_controller.dart';

/// Upper bound on a day-template's target sets. Guards a typo turning one
/// exercise into a hundred preloaded set rows.
const int _maxTargetSets = 20;

enum _DayAction { moveUp, moveDown, remove }

enum _ExerciseAction { moveUp, moveDown, remove }

/// Create/edit screen for a custom (non-built-in) program: name, days, and
/// each day's exercises with target sets/reps.
///
/// [programId] is null when creating a new program.
class ProgramEditorPage extends ConsumerWidget {
  const ProgramEditorPage({this.programId, super.key});

  final String? programId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ProgramDraft> draftAsync =
        ref.watch(programEditorControllerProvider(programId));
    final bool isEditing = programId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing
              ? context.l10n.programEditTitle
              : context.l10n.programNewTitle,
        ),
        actions: <Widget>[
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: context.l10n.programDeleteTooltip,
              onPressed: () => _delete(context, ref),
            ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: context.l10n.actionSave,
            onPressed: draftAsync.value == null
                ? null
                : () => _save(context, ref, draftAsync.value!),
          ),
        ],
      ),
      body: draftAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          title: context.l10n.programLoadFailed,
          details: error.toString(),
        ),
        data: (draft) => _EditorBody(programId: programId, draft: draft),
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    ProgramDraft draft,
  ) async {
    if (draft.name.trim().isEmpty) {
      _showMessage(context, context.l10n.programGiveName);
      return;
    }
    if (draft.days.isEmpty) {
      _showMessage(context, context.l10n.programAddDayValidation);
      return;
    }
    if (draft.days.any((day) => day.exercises.isEmpty)) {
      _showMessage(context, context.l10n.programDayNeedsExercise);
      return;
    }

    final notifier =
        ref.read(programEditorControllerProvider(programId).notifier);
    await notifier.save();
    if (!context.mounted) return;
    // Refreshing `programDetailProvider` is the detail page's job, done
    // once its `pushNamed` future resolves (see `_EditProgramAction`) —
    // not here. Invalidating it from this side races the pop transition:
    // the page beneath would flip loading -> data while mid-animation,
    // which is a reproducible layout/semantics crash, not just a glitch.
    context.pop();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.programDeleteTitle),
        content: Text(context.l10n.programDeleteBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await ref
        .read(programEditorControllerProvider(programId).notifier)
        .delete();
    if (!context.mounted) return;
    // Pop both the editor and the (now-deleted) detail page beneath it.
    context.pop();
    if (context.canPop()) context.pop();
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EditorBody extends ConsumerStatefulWidget {
  const _EditorBody({required this.programId, required this.draft});

  final String? programId;
  final ProgramDraft draft;

  @override
  ConsumerState<_EditorBody> createState() => _EditorBodyState();
}

class _EditorBodyState extends ConsumerState<_EditorBody> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.draft.name);
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.draft.description ?? '');

  ProgramEditorController get _notifier => ref.read(
        programEditorControllerProvider(widget.programId).notifier,
      );

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ProgramDraft draft = widget.draft;

    return PageBody(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        children: <Widget>[
          SectionHeader(title: context.l10n.programDetails),
          AppCard(
            child: Column(
              children: <Widget>[
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: context.l10n.programNameField,
                  ),
                  onChanged: _notifier.setName,
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: context.l10n.programDescriptionField,
                  ),
                  onChanged: (value) =>
                      _notifier.setDescription(value.isEmpty ? null : value),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(
            title: context.l10n.programDays,
            subtitle: draft.days.isEmpty
                ? context.l10n.programDaysRequired
                : context.l10n.dayCount(draft.days.length),
          ),
          for (var i = 0; i < draft.days.length; i++)
            Padding(
              key: ValueKey<String>(draft.days[i].id),
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _DayEditorCard(
                programId: widget.programId,
                day: draft.days[i],
                position: i + 1,
                canMoveUp: i > 0,
                canMoveDown: i < draft.days.length - 1,
              ),
            ),
          OutlinedButton.icon(
            onPressed: _notifier.addDay,
            icon: const Icon(Icons.add),
            label: Text(context.l10n.programAddDay),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _DayEditorCard extends ConsumerStatefulWidget {
  const _DayEditorCard({
    required this.programId,
    required this.day,
    required this.position,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  final String? programId;
  final ProgramDraftDay day;

  /// 1-based ordinal shown in the card header.
  final int position;
  final bool canMoveUp;
  final bool canMoveDown;

  @override
  ConsumerState<_DayEditorCard> createState() => _DayEditorCardState();
}

class _DayEditorCardState extends ConsumerState<_DayEditorCard> {
  late final TextEditingController _dayNameController =
      TextEditingController(text: widget.day.dayName);

  @override
  void didUpdateWidget(covariant _DayEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.day.id != widget.day.id) return;
    _sync(_dayNameController, widget.day.dayName);
  }

  @override
  void dispose() {
    _dayNameController.dispose();
    super.dispose();
  }

  ProgramEditorController get _notifier => ref.read(
        programEditorControllerProvider(widget.programId).notifier,
      );

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Reorder and delete collapse into one menu: three icon buttons
          // alongside the name field left it barely wider than the label.
          Row(
            children: <Widget>[
              Text(
                context.l10n.programDayLabel(widget.position),
                style: AppTypography.eyebrow(Theme.of(context)),
              ),
              const Spacer(),
              PopupMenuButton<_DayAction>(
                tooltip: context.l10n.programDayOptions(widget.position),
                icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
                onSelected: (_DayAction action) => switch (action) {
                  _DayAction.moveUp => _notifier.moveDay(widget.day.id, -1),
                  _DayAction.moveDown => _notifier.moveDay(widget.day.id, 1),
                  _DayAction.remove => _notifier.removeDay(widget.day.id),
                },
                itemBuilder: (_) => <PopupMenuEntry<_DayAction>>[
                  PopupMenuItem<_DayAction>(
                    value: _DayAction.moveUp,
                    enabled: widget.canMoveUp,
                    child: ListTile(
                      leading: const Icon(Icons.arrow_upward),
                      title: Text(context.l10n.programMoveUp),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem<_DayAction>(
                    value: _DayAction.moveDown,
                    enabled: widget.canMoveDown,
                    child: ListTile(
                      leading: const Icon(Icons.arrow_downward),
                      title: Text(context.l10n.programMoveDown),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem<_DayAction>(
                    value: _DayAction.remove,
                    child: ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: Text(context.l10n.programRemoveDay),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          TextField(
            controller: _dayNameController,
            decoration: InputDecoration(
              labelText: context.l10n.programDayNameField,
            ),
            onChanged: (value) => _notifier.renameDay(widget.day.id, value),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < widget.day.exercises.length; i++)
            _ExerciseEditorRow(
              key: ValueKey(widget.day.exercises[i].id),
              programId: widget.programId,
              dayId: widget.day.id,
              exercise: widget.day.exercises[i],
              canMoveUp: i > 0,
              canMoveDown: i < widget.day.exercises.length - 1,
            ),
          const SizedBox(height: AppSpacing.xs),
          TextButton.icon(
            onPressed: () => _addExercise(context),
            icon: const Icon(Icons.add),
            label: Text(context.l10n.programAddExercise),
          ),
          if (widget.day.exercises.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                context.l10n.programNoExercises,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addExercise(BuildContext context) async {
    final Exercise? exercise = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ExercisePickerSheet(),
    );
    if (exercise == null) return;
    _notifier.addExercise(
      widget.day.id,
      exerciseId: exercise.id,
      name: exercise.name,
    );
  }

  void _sync(TextEditingController controller, String value) {
    if (controller.text != value && !controller.selection.isValid) {
      controller.text = value;
    }
  }
}

class _ExerciseEditorRow extends ConsumerStatefulWidget {
  const _ExerciseEditorRow({
    required this.programId,
    required this.dayId,
    required this.exercise,
    required this.canMoveUp,
    required this.canMoveDown,
    super.key,
  });

  final String? programId;
  final String dayId;
  final ProgramDraftExercise exercise;
  final bool canMoveUp;
  final bool canMoveDown;

  @override
  ConsumerState<_ExerciseEditorRow> createState() => _ExerciseEditorRowState();
}

class _ExerciseEditorRowState extends ConsumerState<_ExerciseEditorRow> {
  late final TextEditingController _setsController =
      TextEditingController(text: '${widget.exercise.targetSets}');
  late final TextEditingController _repsController =
      TextEditingController(text: widget.exercise.targetReps ?? '');

  @override
  void didUpdateWidget(covariant _ExerciseEditorRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exercise.id != widget.exercise.id) return;
    _sync(_setsController, '${widget.exercise.targetSets}');
    _sync(_repsController, widget.exercise.targetReps ?? '');
  }

  @override
  void dispose() {
    _setsController.dispose();
    _repsController.dispose();
    super.dispose();
  }

  ProgramEditorController get _notifier => ref.read(
        programEditorControllerProvider(widget.programId).notifier,
      );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    // Name and controls on one line, the two target fields on the next.
    // Fitting all five across a phone left the fields ~56dp wide, which is
    // not enough for a label and a two-digit value.
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.exercise.name,
                  style: theme.textTheme.bodyLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PopupMenuButton<_ExerciseAction>(
                tooltip: context.l10n.programExerciseOptions(
                  widget.exercise.name,
                ),
                icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
                onSelected: (_ExerciseAction action) => switch (action) {
                  _ExerciseAction.moveUp => _notifier.moveExercise(
                      widget.dayId, widget.exercise.id, -1),
                  _ExerciseAction.moveDown =>
                    _notifier.moveExercise(widget.dayId, widget.exercise.id, 1),
                  _ExerciseAction.remove =>
                    _notifier.removeExercise(widget.dayId, widget.exercise.id),
                },
                itemBuilder: (_) => <PopupMenuEntry<_ExerciseAction>>[
                  PopupMenuItem<_ExerciseAction>(
                    value: _ExerciseAction.moveUp,
                    enabled: widget.canMoveUp,
                    child: ListTile(
                      leading: const Icon(Icons.arrow_upward),
                      title: Text(context.l10n.programMoveUp),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem<_ExerciseAction>(
                    value: _ExerciseAction.moveDown,
                    enabled: widget.canMoveDown,
                    child: ListTile(
                      leading: const Icon(Icons.arrow_downward),
                      title: Text(context.l10n.programMoveDown),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem<_ExerciseAction>(
                    value: _ExerciseAction.remove,
                    child: ListTile(
                      leading: const Icon(Icons.close),
                      title: Text(context.l10n.programRemoveExercise),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _setsController,
                  keyboardType: TextInputType.number,
                  style: AppTypography.numeric(
                    theme.textTheme.bodyLarge ?? const TextStyle(),
                  ),
                  decoration: InputDecoration(
                    labelText: context.l10n.programSetsField,
                  ),
                  onChanged: (value) {
                    final sets = int.tryParse(value);
                    if (sets != null && sets > 0 && sets <= _maxTargetSets) {
                      _notifier.setExerciseTargetSets(
                        widget.dayId,
                        widget.exercise.id,
                        sets,
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _repsController,
                  style: AppTypography.numeric(
                    theme.textTheme.bodyLarge ?? const TextStyle(),
                  ),
                  decoration: InputDecoration(
                    labelText: context.l10n.programRepsField,
                  ),
                  onChanged: (value) => _notifier.setExerciseTargetReps(
                    widget.dayId,
                    widget.exercise.id,
                    value.isEmpty ? null : value,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _sync(TextEditingController controller, String value) {
    if (controller.text != value && !controller.selection.isValid) {
      controller.text = value;
    }
  }
}
