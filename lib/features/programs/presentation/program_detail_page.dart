import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/daos/program_dao.dart';
import '../../../core/l10n/l10n_extension.dart';
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
    // Built-in programs are editable too — the first edit converts them to
    // custom (see `ProgramDao.updateProgramWithDays`), so the seed data is
    // a starting point rather than a read-only fixture.
    final bool showEditAction = detailAsync.value != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.programTitle),
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
          title: context.l10n.programLoadFailed,
          details: error.toString(),
          onRetry: () => ref.invalidate(programDetailProvider(programId)),
        ),
        data: (detail) {
          if (detail == null) {
            return EmptyState(
              icon: Icons.event_busy,
              title: context.l10n.programNotFound,
              message: context.l10n.programNotFoundMessage,
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
      tooltip: context.l10n.programEditTooltip,
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
                label: context.l10n.programDays,
                value: '${detail.days.length}',
                emphasis: true,
              ),
              Stat(label: context.l10n.statExercises, value: '$totalExercises'),
              Stat(
                label: context.l10n.programType,
                value: program.isBuiltIn
                    ? context.l10n.programBuiltIn
                    : context.l10n.programCustom,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(
            title: context.l10n.programDays,
            subtitle: context.l10n.programDaysSubtitle,
          ),
          if (detail.days.isEmpty)
            EmptyState(
              icon: Icons.event_busy,
              title: context.l10n.programNoDays,
              message: context.l10n.programNoDaysMessage,
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
          title: Text(context.l10n.programWorkoutInProgress),
          content: Text(context.l10n.programWorkoutInProgressBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.programDiscardAndStart),
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
                      context.l10n.exerciseCount(day.exercises.length),
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
                onPressed: day.exercises.isEmpty ? null : onStart,
                child: Text(context.l10n.programStart),
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
                      _targetLabel(context, exercise),
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

  String _targetLabel(BuildContext context, ProgramDayExercise exercise) {
    final reps = exercise.targetReps;
    return reps == null
        ? context.l10n.programTargetSets(exercise.targetSets)
        : '${exercise.targetSets} × $reps';
  }
}
