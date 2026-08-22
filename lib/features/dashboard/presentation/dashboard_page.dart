import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../../../core/widgets/page_body.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/sparkline.dart';
import '../../../core/widgets/stat_strip.dart';
import '../../../core/widgets/trend_badge.dart';
import '../../tracker/domain/active_workout_notifier.dart';
import '../domain/dashboard_providers.dart';
import 'widgets/summary_card.dart';

/// Central hub. Branch index 0 and the app's start destination.
///
/// Laid out in descending priority rather than as a uniform grid: the
/// primary action first, this week's training status second, progress
/// signals third, recent activity last. Cards still own their own async
/// state, so one failing query degrades a single block instead of the page.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const _Greeting(),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.pushNamed(Routes.settingsName),
          ),
        ],
      ),
      body: SafeArea(
        child: PageBody(
          gutter: false,
          child: CustomScrollView(
            slivers: <Widget>[
              SliverPadding(
                padding: context.sliverGutter.copyWith(
                  top: AppSpacing.sm,
                  bottom: AppSpacing.xl,
                ),
                sliver: const SliverToBoxAdapter(child: _TodayCard()),
              ),
              SliverPadding(
                padding: context.sliverGutter,
                sliver: const SliverToBoxAdapter(child: _ThisWeekSection()),
              ),
              SliverPadding(
                padding: context.sliverGutter.copyWith(top: AppSpacing.xl),
                sliver: const SliverToBoxAdapter(child: _ProgressSection()),
              ),
              SliverPadding(
                padding: context.sliverGutter.copyWith(
                  top: AppSpacing.xl,
                  bottom: AppSpacing.xl,
                ),
                sliver: const SliverToBoxAdapter(child: _RecentSection()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Trend trace beside the weekly volume figure.
const double _sparklineWidthCompact = 96;
const double _sparklineWidthWide = 200;

/// Time-of-day greeting. Orients the user faster than a static wordmark,
/// which they already know — they just opened the app.
class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    final int hour = DateTime.now().hour;
    final String greeting = switch (hour) {
      < 12 => 'Good morning',
      < 18 => 'Good afternoon',
      _ => 'Good evening',
    };
    return Text(greeting);
  }
}

/// Priority one: today's session. Resumes an in-progress draft when there
/// is one, otherwise starts a new workout.
///
/// A draft left open is the single most important thing the dashboard can
/// tell the user, so it takes over this card entirely rather than appearing
/// as a separate banner they might scroll past.
class _TodayCard extends ConsumerWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(activeWorkoutProvider);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool inProgress = draft != null;

    final int loggedSets = draft == null
        ? 0
        : draft.exercises.fold<int>(
            0,
            (int total, e) => total + e.sets.where((s) => s.isCompleted).length,
          );

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  DateFormatters.dayHeadline(DateTime.now()).toUpperCase(),
                  style: AppTypography.eyebrow(theme),
                ),
              ),
              if (inProgress)
                // Status is carried by the label, not the dot alone.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.fiber_manual_record,
                      size: 10,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'IN PROGRESS',
                      style:
                          AppTypography.eyebrow(theme, color: scheme.primary),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            inProgress ? 'Workout in progress' : 'Ready to train',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            inProgress
                ? _draftSummary(draft.exercises.length, loggedSets)
                : 'Start a session and log your sets as you go.',
            style: AppTypography.caption(theme),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            onPressed: () => context.pushNamed(Routes.activeWorkoutName),
            icon: Icon(inProgress ? Icons.play_arrow : Icons.add),
            label: Text(inProgress ? 'Resume workout' : 'Start workout'),
          ),
          if (!inProgress) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () => context.goNamed(Routes.trackerName),
              icon: const Icon(Icons.event_note_outlined),
              label: const Text('Start from a program'),
            ),
          ],
        ],
      ),
    );
  }

  String _draftSummary(int exercises, int sets) {
    if (exercises == 0) return 'No exercises added yet.';
    final String e = '$exercises exercise${exercises == 1 ? '' : 's'}';
    final String s = '$sets set${sets == 1 ? '' : 's'} logged';
    return '$e · $s';
  }
}

/// Priority two: am I on track this week?
class _ThisWeekSection extends ConsumerWidget {
  const _ThisWeekSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<WeekSnapshot> snapshotAsync =
        ref.watch(dashboardWeekSnapshotProvider);
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    // Resolved for every branch so the card's Semantics node exists in all
    // of them. A semantics node that appears only in `data` — alongside a
    // child that has its own, like fl_chart's LineChart — trips
    // `!semantics.parentDataDirty` when the branch switches.
    final String semanticLabel = snapshotAsync.when(
      loading: () => 'This week, loading',
      error: (_, __) => 'This week, failed to load',
      data: (s) => 'This week, ${UnitFormatters.volume(s.volumeKg, unit)}, '
          '${s.sessions} session${s.sessions == 1 ? '' : 's'}',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: 'This week',
          actionLabel: 'Progress',
          onAction: () => context.goNamed(Routes.progressName),
        ),
        AppCard(
          onTap: () => context.goNamed(Routes.progressName),
          semanticLabel: semanticLabel,
          child: snapshotAsync.when(
            loading: () => const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LoadingShimmer(width: 160, height: AppTypography.metricSizeLg),
                SizedBox(height: AppSpacing.sm),
                LoadingShimmer(width: 110, height: 12),
              ],
            ),
            error: (error, _) => ErrorView(
              title: 'Could not load this week',
              details: error.toString(),
              compact: true,
            ),
            data: (s) => _WeekBody(snapshot: s, unit: unit, scheme: scheme),
          ),
        ),
      ],
    );
  }
}

class _WeekBody extends StatelessWidget {
  const _WeekBody({
    required this.snapshot,
    required this.unit,
    required this.scheme,
  });

  final WeekSnapshot snapshot;
  final WeightUnit unit;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (!snapshot.hasHistory) {
      // The series only covers the hero window, so an empty one means
      // "nothing recent" — not "never trained". Saying the latter to a
      // user with years of history behind them reads as data loss.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'No training in the last $dashboardHeroWeeks weeks',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Log a workout and your weekly volume, streak and trends will '
            'appear here. Older history is on the Progress tab.',
            style: AppTypography.caption(theme),
          ),
        ],
      );
    }

    final double previous = snapshot.previousVolumeKg;
    final TrendDirection? trend = previous == 0
        ? null
        : snapshot.volumeKg > previous
            ? TrendDirection.up
            : snapshot.volumeKg < previous
                ? TrendDirection.down
                : TrendDirection.flat;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('VOLUME', style: AppTypography.eyebrow(theme)),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          UnitFormatters.volume(snapshot.volumeKg, unit),
                          style: AppTypography.cardMetric(
                            scheme,
                            size: AppTypography.metricSizeLg,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (trend != null) ...<Widget>[
                        const SizedBox(width: AppSpacing.sm),
                        TrendBadge(
                          direction: trend,
                          label: _deltaLabel(snapshot.volumeKg, previous),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (snapshot.volumeSeries.length >= 2) ...<Widget>[
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                // Widens with the card rather than staying phone-sized on a
                // tablet, where a 96dp trace reads as a stray fragment.
                width: context.breakpoint == Breakpoint.compact
                    ? _sparklineWidthCompact
                    : _sparklineWidthWide,
                child: Sparkline(
                  values: snapshot.volumeSeries,
                  color: scheme.primary,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Divider(height: 1, color: scheme.outlineVariant),
        const SizedBox(height: AppSpacing.lg),
        StatStrip(
          stats: <Stat>[
            Stat(label: 'Sessions', value: '${snapshot.sessions}'),
            Stat(
              label: 'Streak',
              value: snapshot.streakWeeks == 0
                  ? '—'
                  : '${snapshot.streakWeeks} wk',
            ),
            Stat(
              label: 'Last week',
              value:
                  previous == 0 ? '—' : UnitFormatters.volume(previous, unit),
            ),
          ],
        ),
      ],
    );
  }

  /// Percentage change against last week, which is the number a lifter
  /// actually reasons about — the raw kilo delta means little without it.
  String _deltaLabel(double current, double previous) {
    final double pct = ((current - previous) / previous) * 100;
    return '${pct.abs().round()}%';
  }
}

/// Priority three: the two progress signals worth surfacing off-screen.
class _ProgressSection extends StatelessWidget {
  const _ProgressSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: 'Progress'),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _OneRmCard()),
              SizedBox(width: AppSpacing.md),
              Expanded(child: _BodyWeightCard()),
            ],
          ),
        ),
      ],
    );
  }
}

/// Priority four: what happened most recently. Compact rows, not tiles —
/// these are navigation affordances with a value attached, not metrics to
/// compare at a glance.
class _RecentSection extends StatelessWidget {
  const _RecentSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: 'Recent'),
        _LastWorkoutRow(),
        SizedBox(height: AppSpacing.sm),
        _LastTimerRow(),
      ],
    );
  }
}

/// Shared shape for the two "recent activity" rows.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
    this.caption,
    this.isLoading = false,
    this.error,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? value;
  final String? caption;
  final bool isLoading;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      semanticLabel: error != null
          ? '$title, failed to load'
          : isLoading
              ? '$title, loading'
              : '$title, ${value ?? 'no data'}, ${caption ?? ''}',
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xxs),
                if (error != null)
                  Text(
                    'Could not load',
                    style: AppTypography.caption(theme)
                        .copyWith(color: scheme.error),
                  )
                else if (isLoading)
                  const LoadingShimmer(width: 120, height: 12)
                else
                  Text(
                    caption ?? 'Nothing yet',
                    style: AppTypography.caption(theme),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (!isLoading && error == null && value != null) ...<Widget>[
            const SizedBox(width: AppSpacing.md),
            Text(
              value!,
              style: AppTypography.cardMetric(
                scheme,
                size: AppTypography.metricSizeSm,
              ),
            ),
          ],
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _LastWorkoutRow extends ConsumerWidget {
  const _LastWorkoutRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Workout?> workoutAsync =
        ref.watch(dashboardLastWorkoutProvider);
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    return _ActivityRow(
      icon: Icons.fitness_center_outlined,
      title: 'Last workout',
      onTap: () => context.goNamed(Routes.trackerName),
      isLoading: workoutAsync.isLoading,
      error: workoutAsync.error,
      value: workoutAsync.value == null
          ? null
          : UnitFormatters.volume(workoutAsync.value!.totalVolumeKg, unit),
      caption: workoutAsync.value == null
          ? null
          : '${DateFormatters.relativeDay(workoutAsync.value!.startedAt)}'
              '${workoutAsync.value!.durationSeconds == null ? '' : ' · ${UnitFormatters.durationShort(Duration(seconds: workoutAsync.value!.durationSeconds!))}'}',
    );
  }
}

class _LastTimerRow extends ConsumerWidget {
  const _LastTimerRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TimerSession?> sessionAsync =
        ref.watch(dashboardLastTimerSessionProvider);

    return _ActivityRow(
      icon: Icons.timer_outlined,
      title: 'Last timer',
      onTap: () => context.goNamed(Routes.timerName),
      isLoading: sessionAsync.isLoading,
      error: sessionAsync.error,
      caption: sessionAsync.value == null
          ? null
          : '${sessionAsync.value!.presetName} · '
              '${DateFormatters.relativeDay(sessionAsync.value!.startedAt)}',
      value: sessionAsync.value?.actualDurationSeconds == null
          ? null
          : UnitFormatters.durationShort(
              Duration(seconds: sessionAsync.value!.actualDurationSeconds!),
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

    return SummaryCard(
      title: 'Est. 1RM',
      icon: Icons.trending_up,
      onTap: () => context.goNamed(Routes.progressName),
      isLoading: oneRmAsync.isLoading,
      error: oneRmAsync.error,
      metric: oneRmAsync.value == null
          ? null
          : UnitFormatters.weight(oneRmAsync.value!.currentKg, unit),
      caption: oneRmAsync.value?.exerciseName,
      emptyCaption: 'Log a lift to see this',
      trend: oneRmAsync.value == null
          ? null
          : _trendDirection(oneRmAsync.value!.trend),
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

    return SummaryCard(
      title: 'Body weight',
      icon: Icons.monitor_weight_outlined,
      onTap: () => context.goNamed(Routes.progressName),
      isLoading: metricsAsync.isLoading,
      error: metricsAsync.error,
      metric: metricsAsync.value == null
          ? null
          : UnitFormatters.weight(metricsAsync.value!.weightKg, unit),
      caption: metricsAsync.value == null
          ? null
          : DateFormatters.relativeDay(metricsAsync.value!.date),
      emptyCaption: 'Not recorded',
    );
  }
}
