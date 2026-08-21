import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/tables/exercises.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../library/presentation/exercise_picker_sheet.dart';
import '../domain/edit_workout_notifier.dart';
import '../domain/workout_draft.dart';
import 'widgets/draft_editor_widgets.dart';

/// Edits a saved workout's exercises and sets, then writes the changes back.
class WorkoutEditPage extends ConsumerWidget {
  const WorkoutEditPage({required this.workoutId, super.key});

  final String workoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = editWorkoutProvider(workoutId);
    final draftAsync = ref.watch(provider);
    final notifier = ref.read(provider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit workout')),
      body: draftAsync.when(
        data: (draft) => _EditWorkoutBody(draft: draft, notifier: notifier),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          title: 'Failed to load workout',
          details: error.toString(),
          onRetry: () => ref.invalidate(provider),
        ),
      ),
    );
  }
}

class _EditWorkoutBody extends StatelessWidget {
  const _EditWorkoutBody({required this.draft, required this.notifier});

  final WorkoutDraft draft;
  final EditWorkoutNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (draft.exercises.isEmpty)
          const EmptyState(
            icon: Icons.fitness_center_outlined,
            title: 'No exercises left',
            message: 'Add at least one exercise before saving.',
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: true,
            itemCount: draft.exercises.length,
            onReorderItem: (oldIndex, newIndex) {
              notifier.reorderExercise(
                draft.exercises[oldIndex].id,
                newIndex,
              );
            },
            itemBuilder: (context, index) {
              final exercise = draft.exercises[index];
              return ExerciseDraftCard(
                key: ValueKey(exercise.id),
                exercise: exercise,
                controller: notifier,
              );
            },
          ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          onPressed: () => _addExercise(context, notifier),
          icon: const Icon(Icons.add),
          label: const Text('Add exercise'),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed:
              draft.exercises.isEmpty ? null : () => _save(context, notifier),
          icon: const Icon(Icons.check),
          label: const Text('Save changes'),
        ),
      ],
    );
  }

  Future<void> _addExercise(
    BuildContext context,
    EditWorkoutNotifier notifier,
  ) async {
    final exercise = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ExercisePickerSheet(),
    );
    if (exercise != null) {
      await notifier.addExercise(exerciseId: exercise.id, name: exercise.name);
    }
  }

  Future<void> _save(BuildContext context, EditWorkoutNotifier notifier) async {
    try {
      await notifier.save();
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Workout updated')));
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save changes: $error')),
        );
      }
    }
  }
}
