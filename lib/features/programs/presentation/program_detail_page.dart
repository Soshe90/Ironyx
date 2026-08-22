import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/daos/program_dao.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/page_body.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stat_strip.dart';
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
    final ThemeData theme = Theme.of(context);
    final int totalExercises = detail.days.fold<int>(
      0,
      (int sum, ProgramDay d) => sum + d.exercises.length,
    );

    return PageBody(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        children: [
          Text(
            program.name,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (program.description case final description?)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(description, style: AppTypography.caption(theme)),
            ),
          const SizedBox(height: AppSpacing.xl),
          StatStrip(
            stats: <Stat>[
              Stat(
                label: 'Days',
                value: '${detail.days.length}',
                emphasis: true,
              ),
              Stat(label: 'Exercises', value: '$totalExercises'),
              Stat(
                label: 'Type',
                value: program.isBuiltIn ? 'Built-in' : 'Custom',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(
            title: 'Days',
            subtitle: 'Starting a day preloads its exercises and target sets',
          ),
          if (detail.days.isEmpty)
            const EmptyState(
              icon: Icons.event_busy,
              title: 'No days yet',
              message: 'Edit this program to add a training day.',
            )
          else
            for (int i = 0; i < detail.days.length; i++) ...[
              _DayCard(
                day: detail.days[i],
                position: i + 1,
                onStart: () => _startDay(context, ref, detail.days[i]),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
        ],
      ),
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

/// Minimum width for a content-sized button sitting next to Row siblings.
const double _inlineButtonMinWidth = 64;

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.position,
    required this.onStart,
  });

  final ProgramDay day;

  /// 1-based ordinal shown in the leading chip.
  final int position;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: AppSpacing.xl,
                  height: AppSpacing.xl,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    '$position',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      day.dayName,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${day.exercises.length} '
                      'exercise${day.exercises.length == 1 ? '' : 's'}',
                      style: AppTypography.caption(theme),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
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
                  minimumSize: const Size(
                    _inlineButtonMinWidth,
                    AppSpacing.minTapTarget,
                  ),
                ),
                onPressed:
                    day.exercises.isEmpty ? null : onStart,
                child: const Text('Start'),
              ),
            ],
          ),
          if (day.exercises.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: AppSpacing.md),
            for (final exercise in day.exercises)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.fitness_center,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        exercise.exerciseName,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      _targetLabel(exercise),
                      style: AppTypography.numeric(
                        theme.textTheme.bodySmall ?? const TextStyle(),
                      ).copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
          ],
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
