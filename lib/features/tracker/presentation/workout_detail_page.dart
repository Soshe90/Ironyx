import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/daos/workout_dao.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/database/tables/workout_sets.dart';
import '../../../core/formatters/date_formatters.dart';
import '../../../core/formatters/unit_formatters.dart';
import '../../../core/formatters/weight_unit_controller.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/page_body.dart';
import '../../../core/widgets/pr_badge.dart';
import '../../../core/widgets/stat_strip.dart';
import '../../../core/widgets/trend_badge.dart';
import '../../library/domain/exercise_catalogue_l10n.dart';
import '../../progress/domain/progress_providers.dart';

/// Read-only summary of a saved workout, with edit and delete actions.
class WorkoutDetailPage extends ConsumerWidget {
  const WorkoutDetailPage({required this.workoutId, super.key});

  final String workoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(workoutDetailProvider(workoutId));
    final AppLocalizations l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.workoutDetailTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.workoutEditTooltip,
            onPressed: () => context.pushNamed(
              Routes.workoutEditName,
              pathParameters: {'id': workoutId},
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.workoutDeleteTooltip,
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: detailAsync.when(
        data: (details) {
          if (details == null) {
            return EmptyState(
              icon: Icons.search_off,
              title: l10n.workoutNotFound,
              message: l10n.workoutNotFoundMessage,
            );
          }
          return _WorkoutDetailBody(details: details, workoutId: workoutId);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          title: l10n.workoutLoadFailed,
          details: error.toString(),
          onRetry: () => ref.invalidate(workoutDetailProvider(workoutId)),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.workoutDeleteConfirmTitle),
        content: Text(l10n.workoutDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(workoutDaoProvider).deleteWorkout(workoutId);
    if (context.mounted) context.pop();
  }
}

class _WorkoutDetailBody extends ConsumerWidget {
  const _WorkoutDetailBody({required this.details, required this.workoutId});

  final WorkoutWithDetails details;
  final String workoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;
    final DateFormatters dates = DateFormatters.of(context);
    final workout = details.workout;
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final Map<String, String> slugsById = ref.watch(exerciseSlugsByIdProvider);
    final bool isPr = ref
            .watch(personalRecordWorkoutIdsProvider)
            .value
            ?.contains(workoutId) ??
        false;

    return PageBody(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  dates.relativeDay(workout.startedAt),
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (isPr) const PrBadge(),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.workoutDateTime(
              dates.full(workout.startedAt),
              dates.time(workout.startedAt),
            ),
            style: AppTypography.caption(theme),
          ),
          const SizedBox(height: AppSpacing.xl),
          StatStrip(
            stats: <Stat>[
              Stat(
                label: l10n.statVolume,
                value: UnitFormatters.volume(workout.totalVolumeKg, unit),
                emphasis: true,
              ),
              Stat(
                label: l10n.statDuration,
                value: workout.durationSeconds == null
                    ? '—'
                    : UnitFormatters.durationShort(
                        Duration(seconds: workout.durationSeconds!),
                      ),
              ),
              Stat(
                label: l10n.statExercises,
                value: '${details.exercises.length}',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          for (final exercise in details.exercises)
            _ExerciseBreakdown(
              exerciseId: exercise.exerciseId,
              workoutId: workoutId,
              name: localizedExerciseName(
                context,
                slugsById,
                exercise.exerciseId,
                details.exerciseNames[exercise.id] ??
                    l10n.workoutUnknownExercise,
              ),
              sets: details.setsByExercise[exercise.id] ?? const <WorkoutSet>[],
              unit: unit,
            ),
        ],
      ),
    );
  }
}

/// One exercise's logged sets, led by its best set and how that compares
/// to the best the user had managed before this workout.
///
/// Volume is kept but demoted: it measures work done, not performance, so
/// it cannot answer "am I improving" — the top set and its estimated 1RM
/// can, and that is what a lifter actually tracks.
class _ExerciseBreakdown extends ConsumerWidget {
  const _ExerciseBreakdown({
    required this.exerciseId,
    required this.workoutId,
    required this.name,
    required this.sets,
    required this.unit,
  });

  final String exerciseId;
  final String workoutId;
  final String name;
  final List<WorkoutSet> sets;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    // Working volume only, so these per-exercise figures add up to the
    // workout's stored `totalVolumeKg` in the header. `save` folds an
    // exercise-level warm-up flag into each set's, so the set flag alone
    // is enough here.
    final double volumeKg = sets
        .where((WorkoutSet s) => s.isCompleted && !s.isWarmup)
        .fold<double>(0, (double t, WorkoutSet s) => t + s.weightKg * s.reps);

    final ExercisePerformance? performance = ref
        .watch(workoutPerformanceProvider(workoutId))
        .value
        ?.where((ExercisePerformance p) => p.exerciseId == exerciseId)
        .firstOrNull;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (performance != null && performance.isPersonalRecord)
                  const PrBadge(),
              ],
            ),
            if (performance != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _TopSet(performance: performance, unit: unit),
            ],
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: AppSpacing.md),
            for (int i = 0; i < sets.length; i++)
              _SetLine(index: i + 1, set: sets[i], unit: unit),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.l10n.workoutVolumeLine(
                UnitFormatters.volume(volumeKg, unit),
              ),
              style: AppTypography.caption(theme),
            ),
          ],
        ),
      ),
    );
  }
}

/// Headline performance for one exercise: the best set, its estimated 1RM,
/// and the change against the lift's previous best.
class _TopSet extends StatelessWidget {
  const _TopSet({required this.performance, required this.unit});

  final ExercisePerformance performance;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double? change = performance.change;

    final TrendDirection? trend = change == null
        ? null
        : change > 0
            ? TrendDirection.up
            : change < 0
                ? TrendDirection.down
                : TrendDirection.flat;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.l10n.workoutTopSet,
          style: AppTypography.eyebrow(theme),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                '${UnitFormatters.weight(performance.bestWeightKg, unit)}'
                ' × ${performance.bestReps}',
                style: AppTypography.cardMetric(
                  scheme,
                  size: AppTypography.metricSizeMd,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trend != null) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              TrendBadge(
                direction: trend,
                label: '${(change!.abs() * 100).round()}%',
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          performance.isFirstTime
              ? context.l10n.workoutFirstTimeLogged(
                  UnitFormatters.estimate(performance.bestOneRmKg, unit),
                )
              : context.l10n.workoutOneRmWithPrevious(
                  UnitFormatters.estimate(performance.bestOneRmKg, unit),
                  UnitFormatters.estimate(performance.previousBestKg!, unit),
                ),
          style: AppTypography.caption(theme),
        ),
      ],
    );
  }
}

class _SetLine extends StatelessWidget {
  const _SetLine({
    required this.index,
    required this.set,
    required this.unit,
  });

  final int index;
  final WorkoutSet set;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool done = set.isCompleted;

    return Semantics(
      label: context.l10n.workoutSetSemantic(
        index,
        UnitFormatters.weight(set.weightKg, unit),
        set.reps,
        done
            ? context.l10n.workoutSetCompleted
            : context.l10n.workoutSetNotCompleted,
        set.isWarmup ? context.l10n.workoutSetWarmup : '',
      ),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: AppSpacing.xl,
                child: Text(
                  '$index',
                  style: AppTypography.numeric(
                    theme.textTheme.bodyMedium ?? const TextStyle(),
                  ).copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 16,
                color: done ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${UnitFormatters.weight(set.weightKg, unit)} × ${set.reps}',
                style: AppTypography.numeric(
                  theme.textTheme.bodyMedium ?? const TextStyle(),
                ),
              ),
              if (set.isWarmup) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  context.l10n.workoutWarmupLabel,
                  style: AppTypography.eyebrow(theme),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
