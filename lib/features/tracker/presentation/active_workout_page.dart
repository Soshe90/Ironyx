import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/tables/exercises.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../library/presentation/exercise_picker_sheet.dart';
import '../domain/active_workout_notifier.dart';
import 'widgets/draft_editor_widgets.dart';

/// Root-level active-workout session (ADR-3): the bottom bar is hidden here
/// by design, so a mistaken tap on another tab mid-set can't happen.
class ActiveWorkoutPage extends ConsumerStatefulWidget {
  const ActiveWorkoutPage({super.key});

  @override
  ConsumerState<ActiveWorkoutPage> createState() => _ActiveWorkoutPageState();
}

class _ActiveWorkoutPageState extends ConsumerState<ActiveWorkoutPage> {
  @override
  void initState() {
    super.initState();
    // Riverpod forbids modifying a provider mid-build (initState counts),
    // so the first mutation is deferred to right after this frame.
    Future.microtask(() {
      if (!mounted) return;
      final notifier = ref.read(activeWorkoutProvider.notifier);
      if (ref.read(activeWorkoutProvider) == null) {
        // Reached directly (e.g. from the Dashboard banner) without a draft.
        unawaited(notifier.start());
      } else {
        // Resumed while a discard-undo window was still open.
        notifier.cancelScheduledDiscard();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(activeWorkoutProvider);
    final notifier = ref.read(activeWorkoutProvider.notifier);

    if (draft == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active workout'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Discard workout',
            onPressed: () => _confirmDiscard(context, notifier),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (draft.exercises.isEmpty)
            const EmptyState(
              icon: Icons.fitness_center_outlined,
              title: 'Add your first exercise',
              message: 'Choose an exercise from the Library to start logging.',
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: true,
              itemCount: draft.exercises.length,
              onReorderItem: (oldIndex, newIndex) {
                unawaited(notifier.reorderExercise(
                  draft.exercises[oldIndex].id,
                  newIndex,
                ));
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
            label: const Text('Finish workout'),
          ),
        ],
      ),
    );
  }

  Future<void> _addExercise(
    BuildContext context,
    ActiveWorkoutNotifier notifier,
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

  Future<void> _save(
    BuildContext context,
    ActiveWorkoutNotifier notifier,
  ) async {
    try {
      await notifier.save();
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Workout saved')));
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save workout: $error')),
        );
      }
    }
  }

  Future<void> _confirmDiscard(
    BuildContext context,
    ActiveWorkoutNotifier notifier,
  ) async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard workout?'),
        content: const Text('Your current draft will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true || !context.mounted) return;

    notifier.scheduleDiscard();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    context.pop();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Workout discarded'),
        duration: AppDuration.undoWindow,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            notifier.cancelScheduledDiscard();
            router.pushNamed(Routes.activeWorkoutName);
          },
        ),
      ),
    );
  }
}
