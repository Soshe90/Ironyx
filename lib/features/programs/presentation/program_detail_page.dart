import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/daos/program_dao.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../tracker/domain/active_workout_notifier.dart';
import '../../tracker/domain/workout_draft.dart';
import '../domain/program_providers.dart';

/// Read-only view of a program: its ordered day-templates (Workout A/B/C…),
/// each with its exercises and a start action.
class ProgramDetailPage extends ConsumerWidget {
  const ProgramDetailPage({required this.programId, super.key});

  final String programId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(programDetailProvider(programId));
    final bool showEditAction =
        detailAsync.value != null && !detailAsync.value!.program.isBuiltIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Program'),
        actions: <Widget>[
          // Always mounted (never conditionally inserted/removed), even
          // though visibility depends on async data — a widget that
          // appears/disappears from the tree as a provider cycles
          // loading -> data has been a real crash trigger elsewhere in
          // this app (see the Dashboard's hero card), so this avoids that
          // class of bug here defensively even though it isn't confirmed
          // to be reachable for this specific action.
          Visibility(
            visible: showEditAction,
            maintainState: true,
            maintainAnimation: true,
            maintainSize: true,
            maintainSemantics: true,
            child: _EditProgramAction(programId: programId),
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          title: 'Failed to load program',
          details: error.toString(),
          onRetry: () => ref.invalidate(programDetailProvider(programId)),
        ),
        data: (detail) {
          if (detail == null) {
            return const EmptyState(
              icon: Icons.event_busy,
              title: 'Program not found',
              message: 'It may have been deleted.',
            );
          }
          return _ProgramDetailBody(detail: detail);
        },
      ),
    );
  }
}

class _EditProgramAction extends ConsumerWidget {
  const _EditProgramAction({required this.programId});

  final String programId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.edit_outlined),
      tooltip: 'Edit program',
      onPressed: () async {
        await context.pushNamed(
          Routes.programEditName,
          pathParameters: {'id': programId},
        );
        // Refreshed here, once the editor is actually done, rather than
        // the editor invalidating this page's provider directly — this
        // page shouldn't be a dependency the editor has to know about.
        if (context.mounted) ref.invalidate(programDetailProvider(programId));
      },
    );
  }
}

class _ProgramDetailBody extends ConsumerWidget {
  const _ProgramDetailBody({required this.detail});

  final ProgramDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final program = detail.program;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(program.name, style: Theme.of(context).textTheme.headlineSmall),
        if (program.description case final description?)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        for (final day in detail.days) ...[
          _DayCard(day: day, onStart: () => _startDay(context, ref, day)),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }

  Future<void> _startDay(
    BuildContext context,
    WidgetRef ref,
    ProgramDay day,
  ) async {
    if (ref.read(activeWorkoutProvider) != null) {
      final bool? replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Workout in progress'),
          content: const Text(
            'You already have a workout in progress. Starting this one '
            'will discard it and its logged sets.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard & start'),
            ),
          ],
        ),
      );
      if (replace != true || !context.mounted) return;
      await ref.read(activeWorkoutProvider.notifier).discard();
    }

    final notifier = ref.read(activeWorkoutProvider.notifier);
    await notifier.startFromTemplate([
      for (final exercise in day.exercises)
        TemplateExerciseInput(
          exerciseId: exercise.exerciseId,
          name: exercise.exerciseName,
          targetSets: exercise.targetSets,
        ),
    ]);
    if (context.mounted) {
      unawaited(context.pushNamed(Routes.activeWorkoutName));
    }
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.onStart});

  final ProgramDay day;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  day.dayName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              FilledButton.tonal(
                // `AppTheme`'s filledButtonTheme sets `minimumSize:
                // Size.fromHeight(...)` — i.e. an *infinite*-width
                // minimum, correct for the full-width CTA buttons it was
                // designed for, but fatal here: as a Row's non-Expanded
                // child, this button already gets an unbounded max-width
                // from the Row itself, and the two infinities combine
                // into a real, 100%-reproducible layout crash
                // (`BoxConstraints forces an infinite width`). Any
                // content-sized button next to other Row siblings needs
                // this override, not just full-width ones.
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, AppSpacing.minTapTarget),
                ),
                onPressed: onStart,
                child: const Text('Start'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final exercise in day.exercises)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.fitness_center,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      exercise.exerciseName,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    _targetLabel(exercise),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _targetLabel(ProgramDayExercise exercise) {
    final reps = exercise.targetReps;
    return reps == null
        ? '${exercise.targetSets} sets'
        : '${exercise.targetSets} × $reps';
  }
}
