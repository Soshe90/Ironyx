import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/daos/workout_dao.dart';
import '../../../core/database/tables/body_metrics.dart';
import '../../../core/database/tables/profiles.dart';
import '../../../core/formatters/date_formatters.dart';
import '../../../core/formatters/unit_formatters.dart';
import '../../../core/formatters/weight_unit_controller.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/chart_gestures.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/page_body.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/trend_badge.dart';
import '../domain/bmi.dart';
import '../domain/progress_insights.dart';
import '../domain/progress_providers.dart';
import '../domain/strength_analytics.dart';
import 'widgets/body_metric_widgets.dart';

/// Height of a full chart. One value for all of them, so the page has a
/// consistent rhythm instead of three hand-picked heights.
const double _chartHeight = 220;
const double _axisReserved = 28;
const double _barWidth = 22;

/// Progress and analytics hub.
///
/// The range control is global and pinned at the top: every chart below
/// answers a question about the same window, and having it live inside one
/// section (as it used to) made that relationship invisible.
class ProgressPage extends ConsumerStatefulWidget {
  const ProgressPage({super.key});

  @override
  ConsumerState<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends ConsumerState<ProgressPage> {
  String? _exerciseId;

  @override
  Widget build(BuildContext context) {
    final ProgressRange range = ref.watch(progressRangeControllerProvider);

    final AppLocalizations l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navProgress)),
      body: PageBody(
        // Deliberately not a ListView. A lazy sliver estimates the extent
        // it has not built yet as `remaining children x average height of
        // the built ones`, and this page's children range from a 0px
        // SizedBox.shrink to a ~300px chart card. The average of whichever
        // handful is on screen predicts the rest badly, so maxScrollExtent
        // swung by 3000px as you scrolled; scrolling back up built the
        // short top sections, collapsed the estimate, and the position was
        // clamped against it — a flick upward moved the page *down*, and
        // the top became unreachable by dragging.
        //
        // Building every section up front makes the extent exact instead
        // of estimated. It costs one eager build of ~30 sections, which is
        // what the 8000px-surface test in progress_page_test.dart already
        // exercises. See test/widget/progress_scroll_test.dart.
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Column(
            // ListView stretched its children to the full width; Column
            // centres and shrink-wraps them unless told otherwise.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RangeSelector(range: range),
              const SizedBox(height: AppSpacing.md),
              _InsightsSection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: l10n.progressStrengthChangeTitle,
                subtitle: l10n.progressStrengthSubtitle(range.name),
              ),
              _StrengthChangeSection(range: range),
              _RelativeStrengthSection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: l10n.progressEstimatedOneRmTitle,
                subtitle: l10n.progressEstimatedOneRmSubtitle,
              ),
              _OneRmSection(
                range: range,
                exerciseId: _exerciseId,
                onExerciseChanged: (String? id) =>
                    setState(() => _exerciseId = id),
              ),
              _SessionVolumeSection(range: range, exerciseId: _exerciseId),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: l10n.progressWeeklyVolumeTitle,
                subtitle: l10n.progressWeeklyVolumeSubtitle(range.name),
              ),
              _VolumeSection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: l10n.progressConsistencyTitle),
              _ConsistencySection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: l10n.progressEffortRecoveryTitle),
              _RpeSection(range: range),
              _RestSection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: l10n.progressTrainingBalanceTitle),
              _BalanceSection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: l10n.progressWorkoutFrequencyTitle),
              _FrequencySection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: l10n.progressWeeklyVolumeByMuscleTitle),
              _WeeklyMuscleSection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: l10n.progressRepRangeDistributionTitle),
              _RepRangeSection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: l10n.progressTrainingDaysTitle),
              _WeekdaySection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: l10n.progressVolumeByMuscleGroupTitle),
              _MuscleGroupSection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: l10n.progressBodyMetricsTitle,
                subtitle: l10n.progressBodyMetricsSubtitle,
              ),
              _BodyMetricsSection(range: range),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

/// Per-lift strength comparison: the question "am I improving" answered
/// directly, rather than inferred from a volume figure.
class _StrengthChangeSection extends ConsumerWidget {
  const _StrengthChangeSection({required this.range});

  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<StrengthChange>> async =
        ref.watch(strengthChangeProvider(range));
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    return async.when(
      loading: () => const _ChartLoading(),
      error: (error, _) => _ChartError(
        error: error,
        onRetry: () => ref.invalidate(strengthChangeProvider(range)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return _ChartEmpty(
            icon: Icons.trending_up,
            message: context.l10n.progressStrengthEmpty,
          );
        }
        return AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            children: <Widget>[
              for (final StrengthChange row in rows)
                _StrengthRow(row: row, unit: unit),
            ],
          ),
        );
      },
    );
  }
}

class _RelativeStrengthSection extends ConsumerWidget {
  const _RelativeStrengthSection({required this.range});
  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(relativeStrengthsProvider(range)).when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (rows) => rows.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.progressRelativeStrengthTitle,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          context.l10n.progressRelativeStrengthSubtitle,
                          style: AppTypography.caption(Theme.of(context)),
                        ),
                        for (final row in rows.take(6))
                          ListTile(
                            dense: true,
                            title: Text(row.exerciseName),
                            trailing: Text(
                              context.l10n.progressRelativeStrengthRatio(
                                row.ratio.toStringAsFixed(2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        );
  }
}

class _StrengthRow extends StatelessWidget {
  const _StrengthRow({required this.row, required this.unit});

  final StrengthChange row;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = context.l10n;
    final double? change = row.change;
    final String currentEstimate =
        UnitFormatters.estimate(row.currentBestKg, unit);

    final TrendDirection? trend = change == null
        ? null
        : change > 0
            ? TrendDirection.up
            : change < 0
                ? TrendDirection.down
                : TrendDirection.flat;

    return Semantics(
      label: change == null
          ? l10n.progressStrengthSemanticNoChange(
              row.exerciseName,
              currentEstimate,
            )
          : l10n.progressStrengthSemantic(
              row.exerciseName,
              currentEstimate,
              change > 0 ? 'up' : 'down',
              (change.abs() * 100).round(),
            ),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      row.exerciseName,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      row.isNew
                          ? l10n.progressStrengthNewThisPeriod
                          : l10n.progressStrengthPreviousBest(
                              UnitFormatters.estimate(
                                row.previousBestKg!,
                                unit,
                              ),
                            ),
                      style: AppTypography.caption(theme),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                currentEstimate,
                style: AppTypography.cardMetric(
                  scheme,
                  size: AppTypography.metricSizeSm,
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
        ),
      ),
    );
  }
}

class _InsightsSection extends ConsumerWidget {
  const _InsightsSection({required this.range});
  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strength = ref.watch(strengthChangeProvider(range));
    final volume = ref.watch(weeklyVolumeSeriesProvider(range));
    final frequency = ref.watch(workoutFrequencySeriesProvider(range));
    final muscles = ref.watch(muscleGroupSeriesProvider(range));
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    if (strength.isLoading ||
        volume.isLoading ||
        frequency.isLoading ||
        muscles.isLoading) {
      return const _ChartLoading();
    }
    Object? error;
    for (final value in [strength, volume, frequency, muscles]) {
      if (value.hasError) {
        error = value.error;
        break;
      }
    }
    if (error != null) {
      return _ChartError(
        error: error,
        onRetry: () {
          ref.invalidate(strengthChangeProvider(range));
          ref.invalidate(weeklyVolumeSeriesProvider(range));
          ref.invalidate(workoutFrequencySeriesProvider(range));
          ref.invalidate(muscleGroupSeriesProvider(range));
        },
      );
    }

    final insights = buildProgressInsights(
      strengthChanges: strength.value ?? const [],
      volume: volume.value ?? const [],
      frequency: frequency.value ?? const [],
      currentMuscleVolume: muscles.value ?? const [],
      previousMuscleVolume: const [],
    );
    return Semantics(
      container: true,
      label: context.l10n.progressInsightsSemantic,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.progressInsightsTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            if (insights.isEmpty)
              Text(
                context.l10n.progressInsightsEmpty,
                style: AppTypography.caption(Theme.of(context)),
              )
            else
              for (final insight in insights)
                _InsightTile(insight: insight, unit: unit),
          ],
        ),
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({required this.insight, required this.unit});

  final ProgressInsight insight;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String target = switch (insight.target) {
      InsightTarget.strength => l10n.progressInsightTargetStrength,
      InsightTarget.volume => l10n.progressInsightTargetVolume,
      InsightTarget.consistency => l10n.progressInsightTargetConsistency,
      InsightTarget.balance => l10n.progressInsightTargetBalance,
    };
    final ({String headline, String figure}) text = switch (insight.kind) {
      InsightKind.strengthChange => (
          headline: l10n.progressInsightStrengthHeadline(
            insight.direction!.name,
            insight.subjectName!,
            insight.percentage!,
          ),
          figure: l10n.progressInsightStrengthFigure(
            UnitFormatters.estimate(insight.currentBestKg!, unit),
          ),
        ),
      InsightKind.consistencySlipping => (
          headline: l10n.progressInsightConsistencyHeadline,
          figure: l10n.progressInsightConsistencyFigure(
            insight.averageSessionsPerWeek!.toStringAsFixed(1),
          ),
        ),
      InsightKind.volumeTrendingDown => (
          headline: l10n.progressInsightVolumeHeadline,
          figure: l10n.progressInsightVolumeFigure(insight.percentage!),
        ),
      InsightKind.personalRecords => (
          headline: l10n.progressInsightPersonalRecordsHeadline,
          figure: l10n.progressInsightPersonalRecordsFigure(insight.count!),
        ),
      InsightKind.neglectedMuscle => (
          headline: l10n.progressInsightNeglectedHeadline(
            insight.subjectName!,
          ),
          figure: l10n.progressInsightNeglectedFigure,
        ),
    };
    return Semantics(
      container: true,
      label: l10n.progressInsightSemantic(
        text.headline,
        text.figure,
        target,
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(text.headline),
        subtitle: Text(l10n.progressInsightSubtitle(text.figure, target)),
        leading: Icon(
          insight.severity == InsightSeverity.actionable
              ? Icons.priority_high
              : insight.severity == InsightSeverity.negative
                  ? Icons.trending_down
                  : Icons.trending_up,
        ),
      ),
    );
  }
}

class _RangeSelector extends ConsumerWidget {
  const _RangeSelector({required this.range});

  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedButton<ProgressRange>(
      segments: <ButtonSegment<ProgressRange>>[
        for (final ProgressRange option in ProgressRange.values)
          ButtonSegment<ProgressRange>(
            value: option,
            label: Text(context.l10n.progressRangeLabel(option.name)),
          ),
      ],
      selected: <ProgressRange>{range},
      showSelectedIcon: false,
      onSelectionChanged: (Set<ProgressRange> selection) => ref
          .read(progressRangeControllerProvider.notifier)
          .set(selection.first),
    );
  }
}

/// Shared frame for a chart block: headline value, optional trend, then the
/// plot. Keeps the four sections visually identical rather than each one
/// inventing its own header.
class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.child,
    this.headline,
    this.caption,
    this.trend,
    this.header,
  });

  final Widget child;
  final String? headline;
  final String? caption;
  final TrendDirection? trend;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (header != null) ...<Widget>[
            header!,
            const SizedBox(height: AppSpacing.lg),
          ],
          if (headline != null) ...<Widget>[
            Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    headline!,
                    style: AppTypography.cardMetric(
                      scheme,
                      size: AppTypography.metricSizeLg,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trend != null) ...<Widget>[
                  const SizedBox(width: AppSpacing.sm),
                  TrendBadge(direction: trend!),
                ],
              ],
            ),
            if (caption != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              Text(caption!, style: AppTypography.caption(theme)),
            ],
            const SizedBox(height: AppSpacing.lg),
          ],
          child,
        ],
      ),
    );
  }
}

/// Skeleton sized to the real chart so the page does not jump when data
/// lands — an indeterminate bar would also never settle in a widget test.
class _ChartLoading extends StatelessWidget {
  const _ChartLoading();

  @override
  Widget build(BuildContext context) => const AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LoadingShimmer(width: 160, height: AppTypography.metricSizeLg),
            SizedBox(height: AppSpacing.lg),
            LoadingShimmer(height: _chartHeight, radius: AppRadius.md),
          ],
        ),
      );
}

class _ChartEmpty extends StatelessWidget {
  const _ChartEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => AppCard(
        child: EmptyState(
          icon: icon,
          title: context.l10n.metricNoDataYet,
          message: message,
        ),
      );
}

class _ChartError extends StatelessWidget {
  const _ChartError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AppCard(
        child: ErrorView(
          title: context.l10n.progressChartLoadFailed,
          details: error.toString(),
          compact: true,
          onRetry: onRetry,
        ),
      );
}

class _OneRmSection extends ConsumerWidget {
  const _OneRmSection({
    required this.range,
    required this.exerciseId,
    required this.onExerciseChanged,
  });

  final ProgressRange range;
  final String? exerciseId;
  final ValueChanged<String?> onExerciseChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only lifts with logged sets, most-trained first — not the whole
    // catalogue. The default selection is therefore the exercise the user
    // trains most, instead of whichever seeded exercise sorted first.
    final AsyncValue<List<LoggedExercise>> exercises =
        ref.watch(loggedExercisesProvider);
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    return exercises.when(
      loading: () => const _ChartLoading(),
      error: (error, _) => _ChartError(
        error: error,
        onRetry: () => ref.invalidate(loggedExercisesProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return _ChartEmpty(
            icon: Icons.show_chart,
            message: context.l10n.progressOneRmEmpty,
          );
        }

        final String selected =
            items.any((LoggedExercise i) => i.exerciseId == exerciseId)
                ? exerciseId!
                : items.first.exerciseId;
        if (exerciseId == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) onExerciseChanged(selected);
          });
        }

        final AsyncValue<List<OneRMSeriesPoint>> seriesAsync =
            ref.watch(oneRmSeriesProvider(selected, range));

        final Widget picker = DropdownButtonFormField<String>(
          initialValue: selected,
          decoration: InputDecoration(
            labelText: context.l10n.progressExerciseField,
          ),
          isExpanded: true,
          items: [
            for (final LoggedExercise item in items)
              DropdownMenuItem<String>(
                value: item.exerciseId,
                child: Text(
                  context.l10n.progressExerciseWithSessions(
                    item.exerciseName,
                    context.l10n.sessionCount(item.sessionCount),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onExerciseChanged,
        );

        return seriesAsync.when(
          loading: () => const _ChartLoading(),
          error: (error, _) => _ChartError(
            error: error,
            onRetry: () => ref.invalidate(oneRmSeriesProvider(selected, range)),
          ),
          data: (points) {
            if (points.isEmpty) {
              return _ChartCard(
                header: picker,
                child: EmptyState(
                  icon: Icons.show_chart,
                  title: context.l10n.metricNoDataYet,
                  message: context.l10n.progressExerciseRangeEmpty,
                ),
              );
            }

            // The DAO returns newest first; charts read left to right.
            final List<OneRMSeriesPoint> ordered = points.reversed.toList();
            final double current = ordered.last.estimated1RM;
            final double first = ordered.first.estimated1RM;
            final TrendDirection trend = current > first
                ? TrendDirection.up
                : current < first
                    ? TrendDirection.down
                    : TrendDirection.flat;
            final LinearTrend? regression = linearTrend(ordered);
            final String trendCaption = regression == null
                ? context.l10n.progressOneRmFromSessions(
                    UnitFormatters.estimate(first, unit),
                    ordered.length,
                  )
                : context.l10n.progressOneRmMonthlyTrend(
                    '${regression.slopeKgPerMonth >= 0 ? '+' : ''}'
                    '${UnitFormatters.weight(regression.slopeKgPerMonth, unit)}',
                    ordered.length,
                  );

            return _ChartCard(
              header: picker,
              headline: UnitFormatters.estimate(current, unit),
              caption: ordered.length == 1
                  ? context.l10n.progressOneDataPoint
                  : trendCaption,
              trend: ordered.length == 1 ? null : trend,
              child: _DatedLineChart(
                ordered: <_DatedPoint>[
                  for (final OneRMSeriesPoint p in ordered)
                    _DatedPoint(
                        date: p.date,
                        valueKg: p.estimated1RM,
                        isPersonalRecord: p.isPersonalRecord),
                ],
                unit: unit,
              ),
            );
          },
        );
      },
    );
  }
}

class _SessionVolumeSection extends ConsumerWidget {
  const _SessionVolumeSection({required this.range, required this.exerciseId});
  final ProgressRange range;
  final String? exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = exerciseId;
    if (id == null) return const SizedBox.shrink();
    final unit = ref.watch(weightUnitControllerProvider);
    return ref.watch(sessionVolumeLoadProvider(id, range)).when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (rows) => rows.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.progressSessionVolumeTitle,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          context.l10n.progressSessionVolumeSubtitle,
                          style: AppTypography.caption(Theme.of(context)),
                        ),
                        for (final row in rows.take(8))
                          ListTile(
                            dense: true,
                            title: Text(
                              DateFormatters.of(context).axisLabel(row.date),
                            ),
                            trailing:
                                Text(UnitFormatters.volume(row.volumeKg, unit)),
                          ),
                      ],
                    ),
                  ),
                ),
        );
  }
}

/// One dated value in kilograms — the shape both the estimated-1RM chart
/// and the body-weight chart plot.
class _DatedPoint {
  const _DatedPoint(
      {required this.date,
      required this.valueKg,
      this.isPersonalRecord = false});

  final DateTime date;
  final double valueKg;
  final bool isPersonalRecord;
}

/// Line chart over a dated series, plotted on a **time-proportional** x axis.
///
/// Both series used to be laid out by list index, which spaced three
/// sessions inside one week exactly like three sessions across six months —
/// and the slope of that line is the entire question these charts exist to
/// answer. X is now elapsed days from the first point, so a training gap
/// reads as a gap.
class _DatedLineChart extends StatelessWidget {
  const _DatedLineChart({required this.ordered, required this.unit});

  /// Oldest first.
  final List<_DatedPoint> ordered;
  final WeightUnit unit;

  static const double _minutesPerDay = 60 * 24;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final DateTime first = ordered.first.date;
    double xOf(DateTime date) =>
        date.difference(first).inMinutes / _minutesPerDay;

    final double span = xOf(ordered.last.date);
    // A lone point — or several sharing one instant — spans nothing, and
    // fl_chart cannot scale a zero-width axis. Pad a day either side and let
    // the dot sit in the middle.
    final bool degenerate = span <= 0;

    return SizedBox(
      height: _chartHeight,
      child: LineChart(
        LineChartData(
          minX: degenerate ? -1 : 0,
          maxX: degenerate ? 1 : span,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: scheme.outlineVariant,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: _axisReserved + AppSpacing.lg,
                getTitlesWidget: (double value, TitleMeta meta) =>
                    _valueAxisTick(context, value, meta, unit),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: _axisReserved,
                interval: _dayLabelInterval(span),
                getTitlesWidget: (double value, TitleMeta meta) {
                  if (degenerate) {
                    return value == 0
                        ? _axisDate(context, theme, first)
                        : const SizedBox.shrink();
                  }
                  if (value < 0 || value > span) {
                    return const SizedBox.shrink();
                  }
                  return _axisDate(
                    context,
                    theme,
                    first.add(
                      Duration(minutes: (value * _minutesPerDay).round()),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            longPressDuration: kChartNoLongPress,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => [
                for (final spot in spots)
                  LineTooltipItem(
                    '${UnitFormatters.weight(spot.y, unit)}\n',
                    theme.textTheme.labelMedium!.copyWith(
                      color: scheme.onInverseSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    children: [
                      TextSpan(
                        // Indexed by spot, not by x: x is now a day offset
                        // rather than a list position, so `x.toInt()` would
                        // read the wrong entry (or throw).
                        text: DateFormatters.of(context)
                            .full(ordered[spot.spotIndex].date),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onInverseSurface,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              // Plotted in kilograms; the axis and tooltip formatters do the
              // display conversion (ADR-1).
              spots: [
                for (final _DatedPoint p in ordered)
                  FlSpot(degenerate ? 0 : xOf(p.date), p.valueKg),
              ],
              isCurved: true,
              color: scheme.primary,
              barWidth: 3,
              dotData: FlDotData(
                show: ordered.length <= _dotThreshold,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                  radius: ordered[index].isPersonalRecord ? 5 : 3,
                  color: ordered[index].isPersonalRecord
                      ? scheme.tertiary
                      : scheme.primary,
                  strokeWidth: ordered[index].isPersonalRecord ? 2 : 0,
                  strokeColor: scheme.onSurface,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: scheme.primary.withValues(alpha: 0.10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _axisDate(BuildContext context, ThemeData theme, DateTime date) =>
    Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        DateFormatters.of(context).axisLabel(date),
        style: AppTypography.eyebrow(theme),
      ),
    );

/// Tick spacing in days for a time axis covering [span] days, targeting a
/// handful of labels rather than an unreadable row of them.
double _dayLabelInterval(double span) {
  const int maxLabels = 4;
  if (span <= 0) return 1;
  final double interval = (span / maxLabels).ceilToDouble();
  return interval < 1 ? 1 : interval;
}

/// Past this many points the per-point dots merge into noise.
const int _dotThreshold = 20;

/// Left-axis tick, with the two edge ticks suppressed.
///
/// fl_chart labels its computed intervals *and* the axis min/max. When the
/// min is not a round number the bottom pair collide and overprint (an
/// observed "110" sitting on top of "108.5"). Dropping the edges leaves
/// only the evenly spaced ticks.
Widget _valueAxisTick(
  BuildContext context,
  double value,
  TitleMeta meta,
  WeightUnit unit,
) {
  if (value == meta.min || value == meta.max) {
    return const SizedBox.shrink();
  }
  return Text(
    UnitFormatters.weight(value, unit, withUnit: false),
    style: AppTypography.eyebrow(Theme.of(context)),
  );
}

/// Keeps x-axis labels from colliding by showing at most a handful.
double _labelInterval(int count) {
  const int maxLabels = 4;
  if (count <= maxLabels) return 1;
  return (count / maxLabels).ceilToDouble();
}

class _VolumeSection extends ConsumerWidget {
  const _VolumeSection({required this.range});

  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<WeeklyVolume>> async =
        ref.watch(weeklyVolumeSeriesProvider(range));
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    return async.when(
      loading: () => const _ChartLoading(),
      error: (error, _) => _ChartError(
        error: error,
        onRetry: () => ref.invalidate(weeklyVolumeSeriesProvider(range)),
      ),
      data: (points) {
        if (points.isEmpty) {
          return _ChartEmpty(
            icon: Icons.bar_chart,
            message: context.l10n.progressVolumeEmpty,
          );
        }

        final double total = points.fold<double>(
          0,
          (double sum, WeeklyVolume p) => sum + p.totalVolumeKg,
        );
        // The series is zero-filled, so its length is elapsed weeks, not
        // trained ones — count the trained ones explicitly.
        final int activeWeeks =
            points.where((WeeklyVolume p) => p.totalVolumeKg > 0).length;

        return _ChartCard(
          headline: UnitFormatters.volume(total, unit),
          caption: context.l10n.progressVolumeActiveWeeks(
            activeWeeks,
            points.length,
          ),
          child: _WeeklyBarChart(
            weekStarts: <DateTime>[
              for (final WeeklyVolume p in points) p.weekStart,
            ],
            values: <double>[
              for (final WeeklyVolume p in points) p.totalVolumeKg,
            ],
            tooltipValue: (int i) =>
                UnitFormatters.volume(points[i].totalVolumeKg, unit),
          ),
        );
      },
    );
  }
}

class _ConsistencySection extends ConsumerWidget {
  const _ConsistencySection({required this.range});
  final ProgressRange range;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(consistencySummaryProvider(range)).when(
          loading: () => const _ChartLoading(),
          error: (e, _) => _ChartError(
              error: e,
              onRetry: () => ref.invalidate(consistencySummaryProvider(range))),
          data: (summary) => AppCard(
              child: Wrap(
                  alignment: WrapAlignment.spaceAround,
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.md,
                  children: [
                _Metric(
                  label: context.l10n.progressCurrentStreak,
                  value: context.l10n.dashboardStreakWeeks(
                    summary.currentStreakWeeks,
                  ),
                ),
                _Metric(
                  label: context.l10n.progressLongestStreak,
                  value: context.l10n.dashboardStreakWeeks(
                    summary.longestStreakWeeks,
                  ),
                ),
                _Metric(
                    label: context.l10n
                        .progressAdherenceTarget(summary.targetSessionsPerWeek),
                    value: summary.adherenceFraction == null
                        ? '—'
                        : '${(summary.adherenceFraction! * 100).round()}%'),
              ])),
        );
  }
}

class _RpeSection extends ConsumerWidget {
  const _RpeSection({required this.range});
  final ProgressRange range;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(rpeAnalyticsProvider(range)).when(
            loading: () => const _ChartLoading(),
            error: (e, _) => _ChartError(
                error: e,
                onRetry: () => ref.invalidate(rpeAnalyticsProvider(range))),
            data: (rows) => rows.isEmpty
                ? _ChartEmpty(
                    icon: Icons.speed_outlined,
                    message: context.l10n.progressRpeEmpty,
                  )
                : AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        Text(
                          context.l10n.progressSessionRpeTitle,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        for (final row in rows.take(8))
                          ListTile(
                              dense: true,
                              title: Text(
                                DateFormatters.of(context).axisLabel(row.date),
                              ),
                              trailing: Text(
                                context.l10n.progressSessionRpeValue(
                                  row.averageRpe.toStringAsFixed(1),
                                  UnitFormatters.volume(
                                    row.volumeKg,
                                    ref.watch(weightUnitControllerProvider),
                                  ),
                                ),
                              )),
                      ])),
          );
}

class _RestSection extends ConsumerWidget {
  const _RestSection({required this.range});
  final ProgressRange range;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(restAnalyticsProvider(range)).when(
            loading: () => const _ChartLoading(),
            error: (e, _) => _ChartError(
                error: e,
                onRetry: () => ref.invalidate(restAnalyticsProvider(range))),
            data: (rows) => rows.isEmpty
                ? _ChartEmpty(
                    icon: Icons.timer_outlined,
                    message: context.l10n.progressRestEmpty,
                  )
                : AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        Text(
                          context.l10n.progressRestTimeTitle,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        for (final row in rows.take(8))
                          ListTile(
                              dense: true,
                              title: Text(
                                DateFormatters.of(context).axisLabel(row.date),
                              ),
                              trailing: Text(
                                context.l10n.progressAverageRestSeconds(
                                  row.averageRestSeconds.round(),
                                ),
                              )),
                      ])),
          );
}

class _BalanceSection extends ConsumerWidget {
  const _BalanceSection({required this.range});
  final ProgressRange range;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(balanceRatiosProvider(range)).when(
            loading: () => const _ChartLoading(),
            error: (e, _) => _ChartError(
                error: e,
                onRetry: () => ref.invalidate(balanceRatiosProvider(range))),
            data: (b) => AppCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  _RatioLine(
                    label: context.l10n.progressPushPull,
                    ratio: b.pushPullRatio,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _RatioLine(
                    label: context.l10n.progressUpperLower,
                    ratio: b.upperLowerRatio,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    context.l10n.progressReferenceBand,
                    style: AppTypography.caption(Theme.of(context)),
                  ),
                ])),
          );
}

class _WeeklyMuscleSection extends ConsumerWidget {
  const _WeeklyMuscleSection({required this.range});
  final ProgressRange range;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(weeklyMuscleGroupVolumeSeriesProvider(range)).when(
            loading: () => const _ChartLoading(),
            error: (e, _) => _ChartError(
                error: e,
                onRetry: () => ref
                    .invalidate(weeklyMuscleGroupVolumeSeriesProvider(range))),
            data: (rows) => rows.isEmpty
                ? _ChartEmpty(
                    icon: Icons.groups_outlined,
                    message: context.l10n.progressWeeklyMuscleEmpty,
                  )
                : AppCard(
                    child: Column(children: [
                    for (final row in rows.take(12))
                      ListTile(
                          dense: true,
                          title: Text(row.muscleName),
                          subtitle: Text(
                            DateFormatters.of(context).axisLabel(row.weekStart),
                          ),
                          trailing: Text(
                            UnitFormatters.volume(
                              row.totalVolumeKg,
                              ref.watch(weightUnitControllerProvider),
                            ),
                          ))
                  ])),
          );
}

class _RepRangeSection extends ConsumerWidget {
  const _RepRangeSection({required this.range});
  final ProgressRange range;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(repRangeDistributionProvider(range))
      .when(
        loading: () => const _ChartLoading(),
        error: (e, _) => _ChartError(
            error: e,
            onRetry: () => ref.invalidate(repRangeDistributionProvider(range))),
        data: (rows) => AppCard(
            child: Column(children: [
          for (final row in rows)
            _DistributionLine(
                label: switch (row.range) {
                  RepRange.oneToFive => context.l10n.progressRepRangeOneToFive,
                  RepRange.sixToTwelve =>
                    context.l10n.progressRepRangeSixToTwelve,
                  RepRange.thirteenPlus =>
                    context.l10n.progressRepRangeThirteenPlus,
                },
                value: row.setCount)
        ])),
      );
}

class _WeekdaySection extends ConsumerWidget {
  const _WeekdaySection({required this.range});
  final ProgressRange range;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(weekdayDistributionProvider(range)).when(
            loading: () => const _ChartLoading(),
            error: (e, _) => _ChartError(
                error: e,
                onRetry: () =>
                    ref.invalidate(weekdayDistributionProvider(range))),
            data: (rows) => AppCard(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [for (final row in rows) _WeekdayBar(row: row)])),
          );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Semantics(
      label: context.l10n.progressMetricSemantic(label, value),
      child: Column(children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(label, style: AppTypography.caption(Theme.of(context)))
      ]));
}

class _RatioLine extends StatelessWidget {
  const _RatioLine({required this.label, required this.ratio});
  final String label;
  final double? ratio;
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String status = ratio == null
        ? l10n.progressRatioInsufficient
        : ratio! >= .75 && ratio! <= 1.33
            ? l10n.progressRatioBalanced
            : l10n.progressRatioOutsideBand;
    final String? formattedRatio = ratio?.toStringAsFixed(2);
    return Semantics(
        label: formattedRatio == null
            ? l10n.progressRatioInsufficientSemantic(label)
            : l10n.progressRatioSemantic(label, formattedRatio, status),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(
            formattedRatio == null
                ? status
                : l10n.progressRatioValueStatus(formattedRatio, status),
          )
        ]));
  }
}

class _DistributionLine extends StatelessWidget {
  const _DistributionLine({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        title: Text(label),
        trailing: Text(context.l10n.programTargetSets(value)),
      );
}

class _WeekdayBar extends StatelessWidget {
  const _WeekdayBar({required this.row});
  final WeekdayDistribution row;
  @override
  Widget build(BuildContext context) {
    final String weekday = switch (row.weekday) {
      DateTime.monday => 'monday',
      DateTime.tuesday => 'tuesday',
      DateTime.wednesday => 'wednesday',
      DateTime.thursday => 'thursday',
      DateTime.friday => 'friday',
      DateTime.saturday => 'saturday',
      DateTime.sunday => 'sunday',
      _ => 'unknown',
    };
    final String shortLabel = context.l10n.progressWeekdayShort(weekday);
    return Semantics(
        label: context.l10n.progressWeekdaySemantic(
          context.l10n.progressWeekdayFull(weekday),
          row.trainingDayCount,
          row.workoutCount,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              height: 72,
              child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                      width: 18,
                      height: 8.0 + row.trainingDayCount * 10,
                      color: Theme.of(context).colorScheme.primary))),
          const SizedBox(height: 4),
          Text(shortLabel),
          Text('${row.workoutCount}',
              style: Theme.of(context).textTheme.labelSmall)
        ]));
  }
}

class _FrequencySection extends ConsumerWidget {
  const _FrequencySection({required this.range});

  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<WorkoutFrequency>> async =
        ref.watch(workoutFrequencySeriesProvider(range));

    return async.when(
      loading: () => const _ChartLoading(),
      error: (error, _) => _ChartError(
        error: error,
        onRetry: () => ref.invalidate(workoutFrequencySeriesProvider(range)),
      ),
      data: (points) {
        if (points.isEmpty) {
          return _ChartEmpty(
            icon: Icons.event_available_outlined,
            message: context.l10n.progressFrequencyEmpty,
          );
        }
        final int total = points.fold<int>(
          0,
          (int sum, WorkoutFrequency p) => sum + p.workoutCount,
        );
        final int activeWeeks =
            points.where((WorkoutFrequency p) => p.workoutCount > 0).length;
        // Per *elapsed* week. Dividing by the number of weeks that happen to
        // contain a workout reports three sessions crammed into one week —
        // and nothing for the two months after it — as "3.0 / week".
        final double average = total / points.length;

        return _ChartCard(
          headline: context.l10n.progressAveragePerWeek(
            average.toStringAsFixed(1),
          ),
          caption: context.l10n.progressFrequencySummary(
            total,
            points.length,
            activeWeeks,
          ),
          child: _WeeklyBarChart(
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

/// Bar chart over consecutive weekly buckets.
///
/// Shared by weekly volume and weekly frequency: both plot one bar per week
/// of the selected range against the same zero-filled x axis, and having
/// them diverge in bar width or label spacing made two views of the same
/// weeks look like two unrelated charts.
class _WeeklyBarChart extends StatelessWidget {
  const _WeeklyBarChart({
    required this.weekStarts,
    required this.values,
    required this.tooltipValue,
  });

  final List<DateTime> weekStarts;
  final List<double> values;

  /// Formatted headline line of the tooltip for the bar at an index.
  final String Function(int index) tooltipValue;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return SizedBox(
      height: _chartHeight,
      // Bar width has to follow the bucket count now that untrained weeks
      // are included: a fixed 22dp rod was already tight, and an all-time
      // range can run to hundreds of weeks, where fixed-width rods overlap
      // into a solid block.
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = _barWidthFor(
            constraints.maxWidth,
            weekStarts.length,
          );
          return BarChart(
            BarChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: scheme.outlineVariant,
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                topTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: _axisReserved,
                    interval: _labelInterval(weekStarts.length),
                    getTitlesWidget: (double value, TitleMeta meta) {
                      final int i = value.toInt();
                      if (i < 0 || i >= weekStarts.length) {
                        return const SizedBox.shrink();
                      }
                      return _axisDate(context, theme, weekStarts[i]);
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                longPressDuration: kChartNoLongPress,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                      BarTooltipItem(
                    '${tooltipValue(group.x)}\n',
                    theme.textTheme.labelMedium!.copyWith(
                      color: scheme.onInverseSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    children: [
                      TextSpan(
                        text: context.l10n.progressWeekOf(
                          DateFormatters.of(context).full(weekStarts[group.x]),
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onInverseSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < values.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: values[i],
                        color: scheme.primary,
                        width: width,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppRadius.sm),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Rod width that keeps [count] bars inside [available] with a gap between
/// them, capped at the design width so a short range does not draw slabs.
double _barWidthFor(double available, int count) {
  if (count <= 0 || !available.isFinite || available <= 0) return _barWidth;
  const double minWidth = 1;
  // Two thirds of each slot is bar, one third is gap.
  final double perBar = (available / count) * (2 / 3);
  if (perBar > _barWidth) return _barWidth;
  return perBar < minWidth ? minWidth : perBar;
}

class _MuscleGroupSection extends ConsumerStatefulWidget {
  const _MuscleGroupSection({required this.range});

  final ProgressRange range;

  @override
  ConsumerState<_MuscleGroupSection> createState() =>
      _MuscleGroupSectionState();
}

class _MuscleGroupSectionState extends ConsumerState<_MuscleGroupSection> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<MuscleGroupVolume>> async =
        ref.watch(muscleGroupSeriesProvider(widget.range));
    // Volumes arrive in kilograms like every other stored weight; this card
    // used to print them raw with a hardcoded "kg" suffix, so a pounds user
    // read kilogram figures on the one card that never converted (ADR-1).
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return async.when(
      loading: () => const _ChartLoading(),
      error: (error, _) => _ChartError(
        error: error,
        onRetry: () => ref.invalidate(muscleGroupSeriesProvider(widget.range)),
      ),
      data: (points) {
        if (points.isEmpty) {
          return _ChartEmpty(
            icon: Icons.pie_chart_outline,
            message: context.l10n.progressMuscleGroupEmpty,
          );
        }

        final List<MuscleGroupVolume> grouped = <MuscleGroupVolume>[];
        if (points.length <= AppColors.muscleGroupSlots) {
          grouped.addAll(points);
        } else {
          grouped.addAll(points.take(AppColors.muscleGroupSlots));
          final double otherTotal = points
              .skip(AppColors.muscleGroupSlots)
              .fold<double>(0, (sum, p) => sum + p.totalVolumeKg);
          grouped.add(
            MuscleGroupVolume(
              muscleId: '_other',
              muscleName: context.l10n.progressOtherMuscles,
              totalVolumeKg: otherTotal,
            ),
          );
        }

        final List<Color> palette =
            AppColors.muscleGroupPalette(theme.brightness);
        Color colorFor(int index, String muscleId) => muscleId == '_other'
            ? AppColors.muscleGroupOther
            : palette[index % palette.length];

        final int? touched = _touchedIndex;

        return _ChartCard(
          headline: grouped.first.muscleName,
          caption: context.l10n.progressMostTrained(
            UnitFormatters.volume(grouped.first.totalVolumeKg, unit),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Mirrors the canvas tooltip as real text — canvas-painted
              // tooltips aren't reachable by screen readers or widget
              // tests, so every value the tooltip shows needs a plain-text
              // home too.
              Text(
                touched == null
                    ? context.l10n.progressChartInteractionHelp
                    : context.l10n.progressMuscleVolumeDetail(
                        grouped[touched].muscleName,
                        UnitFormatters.volume(
                          grouped[touched].totalVolumeKg,
                          unit,
                        ),
                      ),
                style: AppTypography.caption(theme),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: _chartHeight,
                child: BarChart(
                  BarChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: scheme.outlineVariant,
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      topTitles: const AxisTitles(),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: _axisReserved + AppSpacing.md,
                          getTitlesWidget: (double value, TitleMeta meta) {
                            final int index = value.toInt();
                            if (index < 0 || index >= grouped.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding:
                                  const EdgeInsets.only(top: AppSpacing.xs),
                              child: Text(
                                grouped[index].muscleName,
                                style: AppTypography.eyebrow(theme),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barTouchData: BarTouchData(
                      longPressDuration: kChartNoLongPress,
                      // handleBuiltInTouches keeps the canvas tooltip (mouse
                      // hover and touch tap both drive it, via fl_chart's
                      // shared FlTouchEvent pipeline); touchCallback
                      // additionally mirrors the touched bar into the
                      // plain-text readout above.
                      touchCallback: (event, response) {
                        final spot = response?.spot;
                        setState(() {
                          _touchedIndex =
                              event.isInterestedForInteractions && spot != null
                                  ? spot.touchedBarGroupIndex
                                  : null;
                        });
                      },
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final muscle = grouped[group.x];
                          return BarTooltipItem(
                            '${muscle.muscleName}\n',
                            theme.textTheme.labelMedium!.copyWith(
                              color: scheme.onInverseSurface,
                              fontWeight: FontWeight.w600,
                            ),
                            children: [
                              TextSpan(
                                text: UnitFormatters.volume(
                                  muscle.totalVolumeKg,
                                  unit,
                                ),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onInverseSurface,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < grouped.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: grouped[i].totalVolumeKg,
                              color: colorFor(i, grouped[i].muscleId),
                              width: _barWidth,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(AppRadius.sm),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// How many measurements the Progress page lists inline before deferring to
/// the full history page. The page's ListView builds its children eagerly,
/// so this list cannot be unbounded.
const int _inlineMetricEntries = 8;

class _BodyMetricsSection extends ConsumerWidget {
  const _BodyMetricsSection({required this.range});

  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<BodyMetrics>> async =
        ref.watch(bodyMetricsSeriesProvider(range));
    final AsyncValue<Profile?> profile = ref.watch(progressProfileProvider);
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    return async.when(
      loading: () => const _ChartLoading(),
      error: (error, _) => _ChartError(
        error: error,
        onRetry: () => ref.invalidate(bodyMetricsSeriesProvider(range)),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return AppCard(
            child: Column(
              children: <Widget>[
                EmptyState(
                  icon: Icons.monitor_weight_outlined,
                  title: context.l10n.progressNoMeasurementsTitle,
                  message: range == ProgressRange.all
                      ? context.l10n.progressNoMeasurementsMessage
                      : context.l10n.progressNoMeasurementsInRange(range.name),
                ),
                FilledButton.icon(
                  onPressed: () =>
                      showBodyMetricEditor(context, ref, unit: unit),
                  icon: const Icon(Icons.add),
                  label: Text(context.l10n.progressLogMeasurement),
                ),
              ],
            ),
          );
        }

        final BodyMetrics latest = entries.first;
        final double? heightCm = profile.value?.heightCm;
        final BmiResult? bmi = heightCm == null
            ? null
            : calculateBmi(weightKg: latest.weightKg, heightCm: heightCm);
        final List<BodyMetrics> shown =
            entries.take(_inlineMetricEntries).toList();
        final int hidden = entries.length - shown.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _ChartCard(
              headline: UnitFormatters.weight(latest.weightKg, unit),
              caption: [
                DateFormatters.of(context).relativeDay(latest.date),
                if (latest.bodyFatPercentage != null)
                  context.l10n.progressBodyFatValue(
                    latest.bodyFatPercentage!.toStringAsFixed(1),
                  ),
                if (bmi != null)
                  context.l10n.progressBmiSummary(
                    bmi.value.toStringAsFixed(1),
                    switch (bmi.category) {
                      BmiCategory.underweight =>
                        context.l10n.progressBmiUnderweight,
                      BmiCategory.healthy => context.l10n.progressBmiHealthy,
                      BmiCategory.overweight =>
                        context.l10n.progressBmiOverweight,
                      BmiCategory.obesity => context.l10n.progressBmiObesity,
                    },
                  ),
              ].join(' · '),
              child: entries.length >= 2
                  ? _DatedLineChart(
                      // Stored newest-first; charts read left to right.
                      ordered: <_DatedPoint>[
                        for (final BodyMetrics e in entries.reversed)
                          _DatedPoint(date: e.date, valueKg: e.weightKg),
                      ],
                      unit: unit,
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: () => showBodyMetricEditor(context, ref, unit: unit),
              icon: const Icon(Icons.add),
              label: Text(context.l10n.progressLogMeasurement),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final BodyMetrics entry in shown)
              BodyMetricTile(entry: entry, unit: unit),
            if (hidden > 0)
              TextButton(
                onPressed: () =>
                    context.pushNamed(Routes.bodyMetricsHistoryName),
                child: Text(
                  context.l10n.progressViewAllMeasurements(hidden),
                ),
              ),
          ],
        );
      },
    );
  }
}
