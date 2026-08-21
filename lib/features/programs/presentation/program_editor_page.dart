import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/tables/exercises.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/error_view.dart';
import '../../library/presentation/exercise_picker_sheet.dart';
import '../domain/program_draft.dart';
import '../domain/program_editor_controller.dart';

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
        title: Text(isEditing ? 'Edit program' : 'New program'),
        actions: <Widget>[
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete program',
              onPressed: () => _delete(context, ref),
            ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: draftAsync.value == null
                ? null
                : () => _save(context, ref, draftAsync.value!),
          ),
        ],
      ),
      body: draftAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          title: 'Failed to load program',
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
      _showMessage(context, 'Give the program a name.');
      return;
    }
    if (draft.days.isEmpty) {
      _showMessage(context, 'Add at least one day.');
      return;
    }
    if (draft.days.any((day) => day.exercises.isEmpty)) {
      _showMessage(context, 'Every day needs at least one exercise.');
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
        title: const Text('Delete program?'),
        content: const Text(
          'This permanently deletes the program and its days. '
          'Workouts you already logged from it are not affected.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
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

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: <Widget>[
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Program name'),
          onChanged: _notifier.setName,
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _descriptionController,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
          ),
          onChanged: (value) =>
              _notifier.setDescription(value.isEmpty ? null : value),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Days', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < draft.days.length; i++)
          Padding(
            key: ValueKey(draft.days[i].id),
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _DayEditorCard(
              programId: widget.programId,
              day: draft.days[i],
              canMoveUp: i > 0,
              canMoveDown: i < draft.days.length - 1,
            ),
          ),
        OutlinedButton.icon(
          onPressed: _notifier.addDay,
          icon: const Icon(Icons.add),
          label: const Text('Add day'),
        ),
      ],
    );
  }
}

class _DayEditorCard extends ConsumerStatefulWidget {
  const _DayEditorCard({
    required this.programId,
    required this.day,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  final String? programId;
  final ProgramDraftDay day;
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
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _dayNameController,
                  decoration: const InputDecoration(labelText: 'Day name'),
                  onChanged: (value) => _notifier.renameDay(widget.day.id, value),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_upward),
                tooltip: 'Move day up',
                onPressed: widget.canMoveUp
                    ? () => _notifier.moveDay(widget.day.id, -1)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward),
                tooltip: 'Move day down',
                onPressed: widget.canMoveDown
                    ? () => _notifier.moveDay(widget.day.id, 1)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove day',
                onPressed: () => _notifier.removeDay(widget.day.id),
              ),
            ],
          ),
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
            label: const Text('Add exercise'),
          ),
          if (widget.day.exercises.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                'No exercises yet',
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
  ConsumerState<_ExerciseEditorRow> createState() =>
      _ExerciseEditorRowState();
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              widget.exercise.name,
              style: Theme.of(context).textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 56,
            child: TextField(
              controller: _setsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'sets'),
              onChanged: (value) {
                final sets = int.tryParse(value);
                if (sets != null && sets > 0 && sets <= 20) {
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
          SizedBox(
            width: 64,
            child: TextField(
              controller: _repsController,
              decoration: const InputDecoration(labelText: 'reps'),
              onChanged: (value) => _notifier.setExerciseTargetReps(
                widget.dayId,
                widget.exercise.id,
                value.isEmpty ? null : value,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 18),
            tooltip: 'Move exercise up',
            onPressed: widget.canMoveUp
                ? () =>
                    _notifier.moveExercise(widget.dayId, widget.exercise.id, -1)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 18),
            tooltip: 'Move exercise down',
            onPressed: widget.canMoveDown
                ? () =>
                    _notifier.moveExercise(widget.dayId, widget.exercise.id, 1)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Remove exercise',
            onPressed: () =>
                _notifier.removeExercise(widget.dayId, widget.exercise.id),
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
