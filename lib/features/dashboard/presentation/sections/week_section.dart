/// Home's "This week" card: volume against the same point last week,
/// its sparkline, the session goal and the day strip.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/daos/workout_dao.dart';
import '../../../../core/database/tables/profiles.dart';
import '../../../../core/formatters/unit_formatters.dart';
import '../../../../core/formatters/weight_unit_controller.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/services/clock.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../../core/widgets/metric_value.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/sparkline.dart';
import '../../../../core/widgets/trend_badge.dart';
import '../../../progress/domain/consistency_calculators.dart';
import '../../domain/dashboard_providers.dart';

/// Trend trace beside the weekly volume figure.
const double _sparklineWidthCompact = 96;
const double _sparklineWidthWide = 200;

/// Priority two: am I on track this week?
class ThisWeekSection extends ConsumerWidget {
  const ThisWeekSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<WeekSnapshot> snapshotAsync =
        ref.watch(dashboardWeekSnapshotProvider);
    final AsyncValue<List<WeekdayDistribution>> weekdayAsync =
        ref.watch(dashboardWeekdayDistributionProvider);
    // The goal waits for the profile: read as `.value` it showed the
    // default target of 3 until the profile arrived, then the real one. A
    // profile that fails to load falls back to the default rather than
    // taking the card down; the target is not what the card is about.
    final AsyncValue<Profile?> profileAsync =
        ref.watch(dashboardProfileProvider);
    final bool profileLoading =
        !profileAsync.hasValue && !profileAsync.hasError;
    final int weeklyTarget =
        profileAsync.value?.weeklySessionTarget ?? defaultWeeklySessionTarget;
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final DateTime today = ref.watch(todayProvider);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = context.l10n;

    // Resolved for every branch so the card's Semantics node exists in all
    // of them. A semantics node that appears only in `data` — alongside a
    // child that has its own, like fl_chart's LineChart — trips
    // `!semantics.parentDataDirty` when the branch switches.
    final String semanticLabel = profileLoading
        ? l10n.dashboardThisWeekSemanticLoading
        : snapshotAsync.when(
            loading: () => l10n.dashboardThisWeekSemanticLoading,
            error: (_, __) => l10n.dashboardThisWeekSemanticError,
            data: (s) => l10n.dashboardThisWeekSemantic(
              UnitFormatters.volume(s.volumeKg, unit, context.l10n),
              l10n.sessionCount(s.sessions),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: l10n.dashboardThisWeek,
          actionLabel: l10n.dashboardSeeAll,
          onAction: () => context.goNamed(Routes.progressName),
        ),
        AppCard(
          onTap: () => context.goNamed(Routes.progressName),
          semanticLabel: semanticLabel,
          child: profileLoading
              ? const _WeekLoading()
              : snapshotAsync.when(
                  loading: () => const _WeekLoading(),
                  error: (error, _) => ErrorView(
                    title: l10n.dashboardThisWeekLoadFailed,
                    details: error.toString(),
                    compact: true,
                  ),
                  data: (s) => _WeekBody(
                    snapshot: s,
                    weeklyTarget: weeklyTarget,
                    weekdayAsync: weekdayAsync,
                    today: today,
                    unit: unit,
                    scheme: scheme,
                  ),
                ),
        ),
      ],
    );
  }
}

class _WeekLoading extends StatelessWidget {
  const _WeekLoading();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LoadingShimmer(width: 160, height: AppTypography.metricSizeLg),
          SizedBox(height: AppSpacing.sm),
          LoadingShimmer(width: 110, height: 12),
        ],
      );
}

class _WeekBody extends StatelessWidget {
  const _WeekBody({
    required this.snapshot,
    required this.weeklyTarget,
    required this.weekdayAsync,
    required this.today,
    required this.unit,
    required this.scheme,
  });

  final WeekSnapshot snapshot;
  final int weeklyTarget;
  final AsyncValue<List<WeekdayDistribution>> weekdayAsync;
  final DateTime today;
  final WeightUnit unit;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;

    if (!snapshot.hasHistory) {
      // The series only covers the hero window, so an empty one means
      // "nothing recent" — not "never trained". Saying the latter to a
      // user with years of history behind them reads as data loss.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.dashboardNoRecentTraining(dashboardHeroWeeks),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.dashboardNoRecentTrainingCaption,
            style: AppTypography.caption(theme),
          ),
          // The goal and the week strip stay visible: they are the invitation
          // to start, and hiding them makes a new user's dashboard look
          // broken rather than empty.
          const SizedBox(height: AppSpacing.lg),
          _SessionGoal(
            completed: snapshot.sessions,
            target: weeklyTarget,
          ),
          const SizedBox(height: AppSpacing.md),
          _WeeklyBreakdown(asyncValue: weekdayAsync, today: today),
        ],
      );
    }

    // What is compared with what is the snapshot's rule (see
    // [WeekSnapshot.comparedWithKg]); this only draws it.
    final double previous = snapshot.previousVolumeKg;
    final double? comparedWith = snapshot.comparedWithKg;
    final double? change = snapshot.volumeChange;
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    l10n.dashboardVolumeEyebrow,
                    style: AppTypography.eyebrow(theme),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: MetricValue(
                          UnitFormatters.volume(
                              snapshot.volumeKg, unit, context.l10n),
                          style: AppTypography.cardMetric(
                            scheme,
                            size: AppTypography.metricSizeLg,
                          ),
                        ),
                      ),
                      if (trend != null) ...<Widget>[
                        const SizedBox(width: AppSpacing.sm),
                        TrendBadge(
                          direction: trend,
                          label: snapshot.volumeChangePercent! >
                                  WeekSnapshot.maxShownChangePercent
                              ? '${WeekSnapshot.maxShownChangePercent}%+'
                              : '${snapshot.volumeChangePercent}%',
                        ),
                      ],
                    ],
                  ),
                  // What the badge's percentage is a percentage of; with no
                  // badge, last week's total as context; and with neither
                  // week trained, how long the break has been.
                  if (comparedWith != null ||
                      previous > 0 ||
                      snapshot.weeksWithoutWorkouts > 0) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      comparedWith != null
                          ? l10n.dashboardSamePointLastWeekVolume(
                              UnitFormatters.volume(
                                  comparedWith, unit, context.l10n),
                            )
                          : previous > 0
                              ? l10n.dashboardLastWeekVolume(
                                  UnitFormatters.volume(
                                      previous, unit, context.l10n),
                                )
                              : l10n.dashboardNoWorkoutsForWeeks(
                                  snapshot.weeksWithoutWorkouts,
                                ),
                      style: AppTypography.caption(theme),
                    ),
                  ],
                ],
              ),
            ),
            if (snapshot.showsTrend) ...<Widget>[
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
        _SessionGoal(
          completed: snapshot.sessions,
          target: weeklyTarget,
        ),
        // The day strip sits directly under the goal: together they are
        // one statement, how many sessions and on which days. A row of
        // three stats used to follow; it repeated the session count a
        // third time, and its other two figures have better homes (last
        // week under the volume, the streak as a Progress tile).
        const SizedBox(height: AppSpacing.md),
        _WeeklyBreakdown(asyncValue: weekdayAsync, today: today),
      ],
    );
  }
}

class _WeeklyBreakdown extends StatelessWidget {
  const _WeeklyBreakdown({required this.asyncValue, required this.today});

  final AsyncValue<List<WeekdayDistribution>> asyncValue;

  /// Decides which cell is today and which days have not come yet.
  final DateTime today;

  @override
  Widget build(BuildContext context) => asyncValue.when(
        loading: () => const LoadingShimmer(
          width: double.infinity,
          height: 56,
        ),
        error: (_, __) => Text(
          context.l10n.metricCouldNotLoad,
          style: AppTypography.caption(Theme.of(context)),
        ),
        data: (days) {
          final int todayIndex = days.indexWhere(
            (WeekdayDistribution d) => d.weekday == today.weekday,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (int i = 0; i < days.length; i++)
                Expanded(
                  child: _WeekdayCell(
                    day: days[i],
                    isToday: i == todayIndex,
                    isFuture: todayIndex >= 0 && i > todayIndex,
                  ),
                ),
            ],
          );
        },
      );
}

const double _dayMarkerSize = 32;

/// One day of the current week.
///
/// Four states, so the strip can be read without counting from its edge:
/// trained (filled, checked), today and not yet trained (a ring in the
/// brand colour), a past day without training (a grey disc) and a day still
/// to come (an outline). Before this the last two looked the same, which
/// made every Monday look like a week of missed sessions.
class _WeekdayCell extends StatelessWidget {
  const _WeekdayCell({
    required this.day,
    required this.isToday,
    required this.isFuture,
  });

  final WeekdayDistribution day;
  final bool isToday;
  final bool isFuture;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool trained = day.trainingDayCount > 0;
    final BoxDecoration marker = trained
        ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
        : isToday
            ? BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.primary,
                  width: AppSpacing.xxs,
                ),
              )
            : isFuture
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.outlineVariant),
                  )
                : BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  );
    final String key = switch (day.weekday) {
      DateTime.monday => 'monday',
      DateTime.tuesday => 'tuesday',
      DateTime.wednesday => 'wednesday',
      DateTime.thursday => 'thursday',
      DateTime.friday => 'friday',
      DateTime.saturday => 'saturday',
      _ => 'sunday',
    };

    final String summary = context.l10n.progressWeekdaySemantic(
      context.l10n.progressWeekdayFull(key),
      day.trainingDayCount,
      day.workoutCount,
    );
    return Semantics(
      // The ring is the only visual sign of today, so it is said as well:
      // after the day's own summary, which is what the label is found by.
      label: isToday ? '$summary. ${context.l10n.commonToday}' : summary,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: Column(
          children: <Widget>[
            // Not interactive, so no 48dp minimum; seven of them must also
            // fit a 360dp card, where a 48dp marker gets squeezed non-square.
            Container(
              key: ValueKey<String>('weekday-marker-$key'),
              width: _dayMarkerSize,
              height: _dayMarkerSize,
              decoration: marker,
              child: trained
                  ? Icon(Icons.check, size: 18, color: scheme.onPrimary)
                  : null,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.l10n.progressWeekdayShort(key),
              style: isToday
                  ? theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    )
                  : theme.textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionGoal extends StatelessWidget {
  const _SessionGoal({required this.completed, required this.target});

  final int completed;
  final int target;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = context.l10n;
    final int safeTarget = target.clamp(1, 7);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                l10n.dashboardSessionGoal,
                style: theme.textTheme.labelLarge,
              ),
            ),
            Text(
              l10n.dashboardSessionGoalProgress(completed, safeTarget),
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // One segment per session of the target. Sessions are whole things:
        // a continuous bar a third full says less than one of three
        // segments lit. The count beside the label is the text of it.
        ExcludeSemantics(
          child: Row(
            children: <Widget>[
              for (int i = 0; i < safeTarget; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: AnimatedContainer(
                    key: ValueKey<String>('session-goal-segment-$i'),
                    duration: AppDuration.normal,
                    height: AppSpacing.sm,
                    decoration: BoxDecoration(
                      color: i < completed
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
