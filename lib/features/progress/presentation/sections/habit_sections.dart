/// The Habits chapter: consistency, frequency, training days, and effort
/// and rest.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/daos/workout_dao.dart';
import '../../../../core/formatters/unit_formatters.dart';
import '../../../../core/formatters/weight_unit_controller.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/services/clock.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/segmented_pills.dart';
import '../../domain/consistency_calculators.dart';
import '../../domain/progress_providers.dart';
import '../../domain/progress_summaries.dart';
import '../widgets/progress_charts.dart';
import '../widgets/progress_visuals.dart';

class ConsistencySection extends ConsumerWidget {
  const ConsistencySection({super.key, required this.range});
  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool light = theme.brightness == Brightness.light;
    final AppLocalizations l10n = context.l10n;
    return ref.watch(consistencySummaryProvider(range)).when(
          loading: () => const ProgressCardLoading(),
          error: (e, _) => ProgressChartError(
            error: e,
            onRetry: () => ref.invalidate(consistencySummaryProvider(range)),
          ),
          data: (summary) => AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: ProgressStatTile(
                    icon: Icons.local_fire_department_rounded,
                    color: theme.colorScheme.primary,
                    label: l10n.progressCurrentStreak,
                    value: l10n.dashboardStreakWeeks(
                      summary.currentStreakWeeks,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ProgressStatTile(
                    icon: Icons.emoji_events_rounded,
                    color: light
                        ? AppColors.personalRecordInkLight
                        : AppColors.personalRecord,
                    label: l10n.progressLongestStreak,
                    value: l10n.dashboardStreakWeeks(
                      summary.longestStreakWeeks,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ProgressStatTile(
                    icon: Icons.task_alt_rounded,
                    color: light ? AppColors.gainInkLight : AppColors.gain,
                    label: l10n.progressAdherenceTarget(
                      summary.targetSessionsPerWeek,
                    ),
                    value: summary.adherenceFraction == null
                        ? '—'
                        : '${(summary.adherenceFraction! * 100).round()}%',
                  ),
                ),
              ],
            ),
          ),
        );
  }
}

/// What the effort chart plots.
enum _EffortMetric { rpe, rest }

/// How hard the sessions were, and how long the rests: one chart with a
/// switch, an average for the range as its headline.
///
/// These were two tables of dates. Each listed the first eight sessions of
/// the range, oldest first, so a three-month view showed the sessions from
/// three months ago and none since.
class EffortSection extends ConsumerStatefulWidget {
  const EffortSection({super.key, required this.range});
  final ProgressRange range;

  @override
  ConsumerState<EffortSection> createState() => _EffortSectionState();
}

class _EffortSectionState extends ConsumerState<EffortSection> {
  _EffortMetric _metric = _EffortMetric.rpe;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final Widget header = SegmentedPills<_EffortMetric>(
      semanticLabel: l10n.progressChartMetricSemantic,
      segments: <PillSegment<_EffortMetric>>[
        PillSegment<_EffortMetric>(
          value: _EffortMetric.rpe,
          label: l10n.progressMetricEffort,
        ),
        PillSegment<_EffortMetric>(
          value: _EffortMetric.rest,
          label: l10n.progressMetricRest,
        ),
      ],
      selected: _metric,
      onChanged: (_EffortMetric metric) => setState(() => _metric = metric),
    );
    return switch (_metric) {
      _EffortMetric.rpe => _rpe(context, header),
      _EffortMetric.rest => _rest(context, header),
    };
  }

  Widget _empty(
    BuildContext context,
    Widget header,
    IconData icon,
    String message,
  ) =>
      ProgressChartCard(
        header: header,
        child: EmptyState(
          icon: icon,
          title: context.l10n.metricNoDataYet,
          message: message,
        ),
      );

  Widget _rpe(BuildContext context, Widget header) {
    final ProgressRange range = widget.range;
    final AppLocalizations l10n = context.l10n;
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    return ref.watch(rpeAnalyticsProvider(range)).when(
          loading: () => ProgressChartCard(
              header: header, child: const ProgressPlotLoading()),
          error: (e, _) => ProgressChartError(
            error: e,
            onRetry: () => ref.invalidate(rpeAnalyticsProvider(range)),
          ),
          data: (sessions) {
            if (sessions.isEmpty) {
              return _empty(
                context,
                header,
                Icons.speed_outlined,
                l10n.progressRpeEmpty,
              );
            }
            // Not empty, so there is an average.
            final double average = averageSessionRpe(sessions)!;
            return ProgressChartCard(
              header: header,
              headline:
                  l10n.progressAverageRpe(UnitFormatters.oneDecimal(average)),
              caption: l10n.sessionCount(sessions.length),
              child: DatedLineChart(
                ordered: <DatedPoint>[
                  for (final SessionRpe s in sessions)
                    DatedPoint(
                      date: s.date,
                      value: s.averageRpe,
                      // Effort next to the load it was spent on: a hard
                      // session with little volume reads differently.
                      tooltip: l10n.progressSessionRpeValue(
                        UnitFormatters.oneDecimal(s.averageRpe),
                        UnitFormatters.volume(s.volumeKg, unit, l10n),
                      ),
                    ),
                ],
                axisLabel: plainAxisTick,
              ),
            );
          },
        );
  }

  Widget _rest(BuildContext context, Widget header) {
    final ProgressRange range = widget.range;
    final AppLocalizations l10n = context.l10n;
    return ref.watch(restAnalyticsProvider(range)).when(
          loading: () => ProgressChartCard(
              header: header, child: const ProgressPlotLoading()),
          error: (e, _) => ProgressChartError(
            error: e,
            onRetry: () => ref.invalidate(restAnalyticsProvider(range)),
          ),
          data: (sessions) {
            if (sessions.isEmpty) {
              return _empty(
                context,
                header,
                Icons.timer_outlined,
                l10n.progressRestEmpty,
              );
            }
            // Weighted by the rests each session recorded; see
            // summarizeRest.
            final (:double? averageSeconds, restCount: int sets) =
                summarizeRest(sessions);
            if (averageSeconds == null) {
              return _empty(
                context,
                header,
                Icons.timer_outlined,
                l10n.progressRestEmpty,
              );
            }
            return ProgressChartCard(
              header: header,
              headline: l10n.progressAverageRestSeconds(averageSeconds.round()),
              // How many rests the average stands on, as text: in the
              // chart it is only in a tooltip, which a screen reader
              // cannot reach.
              caption: <String>[
                l10n.sessionCount(sessions.length),
                l10n.progressRestFromSets(sets),
              ].join(' · '),
              child: DatedLineChart(
                ordered: <DatedPoint>[
                  for (final SessionRest s in sessions)
                    DatedPoint(
                      date: s.date,
                      value: s.averageRestSeconds,
                      tooltip: l10n.progressAverageRestSeconds(
                        s.averageRestSeconds.round(),
                      ),
                      // The sample size is part of the number: a session
                      // where rest was recorded once is not a rest habit.
                      detail: l10n.progressRestFromSets(s.recordedSetCount),
                    ),
                ],
                axisLabel: plainAxisTick,
              ),
            );
          },
        );
  }
}

class WeekdaySection extends ConsumerWidget {
  const WeekdaySection({super.key, required this.range});
  final ProgressRange range;

  static String _weekdayKey(int weekday) => switch (weekday) {
        DateTime.monday => 'monday',
        DateTime.tuesday => 'tuesday',
        DateTime.wednesday => 'wednesday',
        DateTime.thursday => 'thursday',
        DateTime.friday => 'friday',
        DateTime.saturday => 'saturday',
        DateTime.sunday => 'sunday',
        _ => 'unknown',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    return ref.watch(weekdayDistributionProvider(range)).when(
          loading: () => const ProgressCardLoading(),
          error: (e, _) => ProgressChartError(
            error: e,
            onRetry: () => ref.invalidate(weekdayDistributionProvider(range)),
          ),
          data: (rows) => AppCard(
            child: WeekdayBars(
              days: <WeekdayBarData>[
                for (final WeekdayDistribution row in rows)
                  WeekdayBarData(
                    shortLabel:
                        l10n.progressWeekdayShort(_weekdayKey(row.weekday)),
                    semanticLabel: l10n.progressWeekdaySemantic(
                      l10n.progressWeekdayFull(_weekdayKey(row.weekday)),
                      row.trainingDayCount,
                      row.workoutCount,
                    ),
                    trainingDays: row.trainingDayCount,
                  ),
              ],
            ),
          ),
        );
  }
}

class FrequencySection extends ConsumerWidget {
  const FrequencySection({super.key, required this.range});

  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<WorkoutFrequency>> async =
        ref.watch(workoutFrequencySeriesProvider(range));

    return async.when(
      loading: () => const ProgressChartLoading(),
      error: (error, _) => ProgressChartError(
        error: error,
        onRetry: () => ref.invalidate(workoutFrequencySeriesProvider(range)),
      ),
      data: (points) {
        if (points.isEmpty) {
          return ProgressChartEmpty(
            icon: Icons.event_available_outlined,
            message: context.l10n.progressFrequencyEmpty,
          );
        }
        final (workouts: int total, :int activeWeeks) =
            summarizeWeeklyFrequency(points);
        // Per elapsed week of the range, not per week that happens to
        // contain a workout (which reports three sessions crammed into one
        // week, then two idle months, as "3.0 / week") and not per bucket
        // (see averageSessionsPerWeek).
        final double? average = averageSessionsPerWeek(
          weeks: points,
          rangeDays: range.days,
          now: ref.watch(localNowProvider),
        );

        return ProgressChartCard(
          headline: context.l10n.progressAveragePerWeek(
            average == null ? '—' : UnitFormatters.oneDecimal(average),
          ),
          caption: context.l10n.progressFrequencySummary(
            total,
            points.length,
            activeWeeks,
          ),
          child: WeeklyBarChart(
            axisLabel: plainAxisTick,
            wholeNumbers: true,
            weekStarts: <DateTime>[
              for (final WorkoutFrequency p in points) p.weekStart,
            ],
            values: <double>[
              for (final WorkoutFrequency p in points)
                p.workoutCount.toDouble(),
            ],
            tooltipValue: (int i) =>
                context.l10n.progressWorkoutCount(points[i].workoutCount),
          ),
        );
      },
    );
  }
}
