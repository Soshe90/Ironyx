import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/daos/exercise_dao.dart';
import '../../../core/database/daos/workout_dao.dart';
import '../../../core/database/tables/body_metrics.dart';
import '../../../core/database/tables/timer_sessions.dart';
import '../../../core/database/tables/workouts.dart';
import '../../../core/formatters/date_formatters.dart';
import '../../../core/formatters/unit_formatters.dart';
import '../../../core/formatters/weight_unit_controller.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/sparkline.dart';
import '../../../core/widgets/trend_badge.dart';
import '../domain/dashboard_providers.dart';
import 'widgets/summary_card.dart';

/// Central hub. Branch index 0 and the app's start destination.
///
/// Each card is its own [ConsumerWidget] watching its own stream provider
/// (`dashboard_providers.dart`), so one card failing to load never blanks
/// the rest of the dashboard.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final int columns = context.gridColumns;

    const List<Widget> cards = <Widget>[
      _LastWorkoutCard(),
      _LastTimerCard(),
      _LibraryCard(),
      _OneRmCard(),
      _BodyWeightCard(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('FitTrack'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.pushNamed(Routes.settingsName),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
            child: CustomScrollView(
              slivers: <Widget>[
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  sliver: SliverToBoxAdapter(child: _StartWorkoutBanner()),
                ),
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  sliver: SliverToBoxAdapter(child: _WeeklyVolumeHeroCard()),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: AppSpacing.md,
                      crossAxisSpacing: AppSpacing.md,
                      mainAxisExtent: 160,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => cards[index],
                      childCount: cards.length,
                    ),
                  ),
                ),
                const SliverPadding(
                  padding: EdgeInsets.only(bottom: AppSpacing.lg),
                  sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartWorkoutBanner extends StatelessWidget {
  const _StartWorkoutBanner();

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => context.pushNamed(Routes.activeWorkoutName),
      icon: const Icon(Icons.play_arrow),
      label: const Text('Start workout'),
    );
  }
}

/// Hero card: this week's training volume, its trend against the prior
/// week, and a sparkline over the last 8 weeks. Wider and denser than the
/// grid tiles below it, so it reads as the dashboard's headline stat.
class _WeeklyVolumeHeroCard extends ConsumerWidget {
  const _WeeklyVolumeHeroCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<WeeklyVolume>> volumeAsync =
        ref.watch(dashboardWeeklyVolumeProvider);
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    // Computed for every branch (not just `data`) so `AppCard`'s Semantics
    // node is always present — a semantics node that appears only in one
    // async branch and disappears in others (loading/error) is a real
    // crash trigger (`!semantics.parentDataDirty`) once a child with its
    // own semantics, like fl_chart's `LineChart` here, is involved.
    final String semanticLabel = volumeAsync.when(
      loading: () => 'This week\'s volume, loading',
      error: (error, _) => 'This week\'s volume, failed to load',
      data: (weeks) => 'This week\'s volume, '
          '${weeks.isEmpty ? 'no data' : UnitFormatters.volume(weeks.last.totalVolumeKg, unit)}',
    );

    return AppCard(
      onTap: () => context.pushNamed(Routes.progressName),
      semanticLabel: semanticLabel,
      child: volumeAsync.when(
        loading: () => const SizedBox(
          height: 96,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LoadingShimmer(width: 140, height: 32),
              SizedBox(height: AppSpacing.sm),
              LoadingShimmer(width: 100, height: 12),
            ],
          ),
        ),
        error: (error, _) => ErrorView(
          title: 'Could not load weekly volume',
          details: error.toString(),
          compact: true,
        ),
        data: (weeks) {
          final double current = weeks.isEmpty ? 0 : weeks.last.totalVolumeKg;
          final double? previous =
              weeks.length < 2 ? null : weeks[weeks.length - 2].totalVolumeKg;
          final TrendDirection? trend = previous == null
              ? null
              : current > previous
                  ? TrendDirection.up
                  : current < previous
                      ? TrendDirection.down
                      : TrendDirection.flat;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'THIS WEEK\'S VOLUME',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            weeks.isEmpty
                                ? '—'
                                : UnitFormatters.volume(current, unit),
                            style: AppTypography.cardMetric(scheme)
                                .copyWith(fontSize: 32),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (trend != null) ...<Widget>[
                          const SizedBox(width: AppSpacing.sm),
                          TrendBadge(direction: trend),
                        ],
                      ],
                    ),
                  ),
                  if (weeks.length >= 2) ...<Widget>[
                    const SizedBox(width: AppSpacing.md),
                    SizedBox(
                      width: 96,
                      child: Sparkline(
                        values: <double>[
                          for (final w in weeks) w.totalVolumeKg,
                        ],
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
              if (weeks.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'No completed workouts yet',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LastWorkoutCard extends ConsumerWidget {
  const _LastWorkoutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Workout?> workoutAsync =
        ref.watch(dashboardLastWorkoutProvider);
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    return workoutAsync.when(
      loading: () => SummaryCard(
        title: 'Last workout',
        icon: Icons.add_box_outlined,
        isLoading: true,
        onTap: () => context.goNamed(Routes.trackerName),
      ),
      error: (error, _) => SummaryCard(
        title: 'Last workout',
        icon: Icons.add_box_outlined,
        error: error,
        onTap: () => context.goNamed(Routes.trackerName),
      ),
      data: (workout) => SummaryCard(
        title: 'Last workout',
        icon: Icons.add_box_outlined,
        onTap: () => context.goNamed(Routes.trackerName),
        metric: workout == null
            ? null
            : UnitFormatters.volume(workout.totalVolumeKg, unit),
        caption: workout == null
            ? null
            : '${DateFormatters.relativeDay(workout.startedAt)}'
                '${workout.durationSeconds == null ? '' : ' · ${UnitFormatters.durationShort(Duration(seconds: workout.durationSeconds!))}'}',
      ),
    );
  }
}

class _LastTimerCard extends ConsumerWidget {
  const _LastTimerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TimerSession?> sessionAsync =
        ref.watch(dashboardLastTimerSessionProvider);

    return sessionAsync.when(
      loading: () => SummaryCard(
        title: 'Last timer',
        icon: Icons.timer_outlined,
        isLoading: true,
        onTap: () => context.goNamed(Routes.timerName),
      ),
      error: (error, _) => SummaryCard(
        title: 'Last timer',
        icon: Icons.timer_outlined,
        error: error,
        onTap: () => context.goNamed(Routes.timerName),
      ),
      data: (session) => SummaryCard(
        title: 'Last timer',
        icon: Icons.timer_outlined,
        onTap: () => context.goNamed(Routes.timerName),
        metric: session?.presetName,
        caption: session == null
            ? null
            : DateFormatters.relativeDay(session.startedAt) +
                (session.actualDurationSeconds == null
                    ? ''
                    : ' · ${UnitFormatters.durationShort(Duration(seconds: session.actualDurationSeconds!))}'),
      ),
    );
  }
}

class _LibraryCard extends ConsumerWidget {
  const _LibraryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<LibrarySummary> summaryAsync =
        ref.watch(dashboardLibrarySummaryProvider);

    return summaryAsync.when(
      loading: () => SummaryCard(
        title: 'Exercises',
        icon: Icons.fitness_center_outlined,
        isLoading: true,
        onTap: () => context.goNamed(Routes.libraryName),
      ),
      error: (error, _) => SummaryCard(
        title: 'Exercises',
        icon: Icons.fitness_center_outlined,
        error: error,
        onTap: () => context.goNamed(Routes.libraryName),
      ),
      data: (summary) => SummaryCard(
        title: 'Exercises',
        icon: Icons.fitness_center_outlined,
        onTap: () => context.goNamed(Routes.libraryName),
        metric: summary.count == 0 ? null : '${summary.count}',
        caption: summary.mostRecentName == null
            ? null
            : 'Latest: ${summary.mostRecentName}',
      ),
    );
  }
}

class _OneRmCard extends ConsumerWidget {
  const _OneRmCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<MostLoggedOneRM?> oneRmAsync =
        ref.watch(dashboardMostLoggedOneRMProvider);
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    return oneRmAsync.when(
      loading: () => SummaryCard(
        title: 'Est. 1RM',
        icon: Icons.insights_outlined,
        isLoading: true,
        onTap: () => context.goNamed(Routes.progressName),
      ),
      error: (error, _) => SummaryCard(
        title: 'Est. 1RM',
        icon: Icons.insights_outlined,
        error: error,
        onTap: () => context.goNamed(Routes.progressName),
      ),
      data: (oneRm) => SummaryCard(
        title: 'Est. 1RM',
        icon: Icons.insights_outlined,
        onTap: () => context.goNamed(Routes.progressName),
        metric:
            oneRm == null ? null : UnitFormatters.weight(oneRm.currentKg, unit),
        caption: oneRm?.exerciseName,
        trend: oneRm == null ? null : _trendDirection(oneRm.trend),
      ),
    );
  }

  TrendDirection _trendDirection(OneRMTrend trend) => switch (trend) {
        OneRMTrend.up => TrendDirection.up,
        OneRMTrend.down => TrendDirection.down,
        OneRMTrend.flat => TrendDirection.flat,
      };
}

class _BodyWeightCard extends ConsumerWidget {
  const _BodyWeightCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<BodyMetrics?> metricsAsync =
        ref.watch(dashboardLatestBodyMetricsProvider);
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    return metricsAsync.when(
      loading: () => SummaryCard(
        title: 'Body weight',
        icon: Icons.monitor_weight_outlined,
        isLoading: true,
        onTap: () => context.goNamed(Routes.progressName),
      ),
      error: (error, _) => SummaryCard(
        title: 'Body weight',
        icon: Icons.monitor_weight_outlined,
        error: error,
        onTap: () => context.goNamed(Routes.progressName),
      ),
      data: (metrics) => SummaryCard(
        title: 'Body weight',
        icon: Icons.monitor_weight_outlined,
        onTap: () => context.goNamed(Routes.progressName),
        metric: metrics == null
            ? null
            : UnitFormatters.weight(metrics.weightKg, unit),
        caption:
            metrics == null ? null : DateFormatters.relativeDay(metrics.date),
      ),
    );
  }
}
