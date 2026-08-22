import 'package:drift/drift.dart' show Value;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/exercise_dao.dart';
import '../../../core/database/daos/workout_dao.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/database/tables/body_metrics.dart';
import '../../../core/formatters/date_formatters.dart';
import '../../../core/formatters/unit_formatters.dart';
import '../../../core/formatters/weight_unit_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/page_body.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/trend_badge.dart';
import '../domain/progress_providers.dart';

const _uuid = Uuid();

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

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          children: [
            _RangeSelector(range: range),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(
              title: 'Estimated 1RM',
              subtitle: 'Epley estimate from your heaviest logged sets',
            ),
            _OneRmSection(
              range: range,
              exerciseId: _exerciseId,
              onExerciseChanged: (String? id) =>
                  setState(() => _exerciseId = id),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(title: 'Weekly volume'),
            _VolumeSection(range: range),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(title: 'Workout frequency'),
            _FrequencySection(range: range),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(title: 'Volume by muscle group'),
            _MuscleGroupSection(range: range),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(
              title: 'Body metrics',
              subtitle: 'Weight and body fat over time',
            ),
            const _BodyMetricsSection(),
            const SizedBox(height: AppSpacing.xl),
          ],
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
            label: Text(option.label),
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
          title: 'No data yet',
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
          title: 'Could not load this chart',
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
    final AsyncValue<List<ExerciseSummary>> exercises =
        ref.watch(allExercisesStreamProvider);
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    return exercises.when(
      loading: () => const _ChartLoading(),
      error: (error, _) => _ChartError(
        error: error,
        onRetry: () => ref.invalidate(allExercisesStreamProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const _ChartEmpty(
            icon: Icons.show_chart,
            message: 'Complete weighted sets to see strength trends.',
          );
        }

        final String selected =
            items.any((ExerciseSummary i) => i.exercise.id == exerciseId)
                ? exerciseId!
                : items.first.exercise.id;

        final AsyncValue<List<OneRMSeriesPoint>> seriesAsync =
            ref.watch(oneRmSeriesProvider(selected, range));

        final Widget picker = DropdownButtonFormField<String>(
          initialValue: selected,
          decoration: const InputDecoration(labelText: 'Exercise'),
          isExpanded: true,
          items: [
            for (final ExerciseSummary item in items)
              DropdownMenuItem<String>(
                value: item.exercise.id,
                child: Text(
                  item.exercise.name,
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
            onRetry: () =>
                ref.invalidate(oneRmSeriesProvider(selected, range)),
          ),
          data: (points) {
            if (points.isEmpty) {
              return _ChartCard(
                header: picker,
                child: const EmptyState(
                  icon: Icons.show_chart,
                  title: 'No data yet',
                  message: 'No completed sets for this exercise in range.',
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

            return _ChartCard(
              header: picker,
              headline: UnitFormatters.weight(current, unit),
              caption: ordered.length == 1
                  ? 'One data point in this range'
                  : 'From ${UnitFormatters.weight(first, unit)} over '
                      '${ordered.length} sessions',
              trend: ordered.length == 1 ? null : trend,
              child: _OneRmChart(ordered: ordered, unit: unit),
            );
          },
        );
      },
    );
  }
}

class _OneRmChart extends StatelessWidget {
  const _OneRmChart({required this.ordered, required this.unit});

  final List<OneRMSeriesPoint> ordered;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return SizedBox(
      height: _chartHeight,
      child: LineChart(
        LineChartData(
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
                getTitlesWidget: (double value, TitleMeta meta) => Text(
                  UnitFormatters.weight(value, unit, withUnit: false),
                  style: AppTypography.eyebrow(theme),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: _axisReserved,
                interval: _labelInterval(ordered.length),
                getTitlesWidget: (double value, TitleMeta meta) {
                  final int i = value.toInt();
                  if (i < 0 || i >= ordered.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      DateFormatters.relativeDay(ordered[i].date),
                      style: AppTypography.eyebrow(theme),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
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
                        text:
                            DateFormatters.full(ordered[spot.x.toInt()].date),
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
              spots: [
                for (var i = 0; i < ordered.length; i++)
                  FlSpot(i.toDouble(), ordered[i].estimated1RM),
              ],
              isCurved: true,
              color: scheme.primary,
              barWidth: 3,
              dotData: FlDotData(show: ordered.length <= _dotThreshold),
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

/// Past this many points the per-point dots merge into noise.
const int _dotThreshold = 20;

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
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return async.when(
      loading: () => const _ChartLoading(),
      error: (error, _) => _ChartError(
        error: error,
        onRetry: () => ref.invalidate(weeklyVolumeSeriesProvider(range)),
      ),
      data: (points) {
        if (points.isEmpty) {
          return const _ChartEmpty(
            icon: Icons.bar_chart,
            message: 'Complete a workout to see volume.',
          );
        }

        final double total = points.fold<double>(
          0,
          (double sum, WeeklyVolume p) => sum + p.totalVolumeKg,
        );

        return _ChartCard(
          headline: UnitFormatters.volume(total, unit),
          caption: 'Across ${points.length} active '
              'week${points.length == 1 ? '' : 's'}',
          child: SizedBox(
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
                      reservedSize: _axisReserved,
                      interval: _labelInterval(points.length),
                      getTitlesWidget: (double value, TitleMeta meta) {
                        final int i = value.toInt();
                        if (i < 0 || i >= points.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text(
                            DateFormatters.relativeDay(points[i].weekStart),
                            style: AppTypography.eyebrow(theme),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                        BarTooltipItem(
                      '${UnitFormatters.volume(points[group.x].totalVolumeKg, unit)}\n',
                      theme.textTheme.labelMedium!.copyWith(
                        color: scheme.onInverseSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        TextSpan(
                          text: 'Week of '
                              '${DateFormatters.full(points[group.x].weekStart)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onInverseSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < points.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: points[i].totalVolumeKg,
                          color: scheme.primary,
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
        );
      },
    );
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
          return const _ChartEmpty(
            icon: Icons.event_available_outlined,
            message: 'Complete workouts to see your weekly frequency.',
          );
        }
        final int total = points.fold<int>(
          0,
          (int sum, WorkoutFrequency p) => sum + p.workoutCount,
        );
        final double average = total / points.length;

        return _ChartCard(
          headline: '${average.toStringAsFixed(1)} / week',
          caption: '$total workout${total == 1 ? '' : 's'} across '
              '${points.length} active week${points.length == 1 ? '' : 's'}',
          child: const SizedBox.shrink(),
        );
      },
    );
  }
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
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return async.when(
      loading: () => const _ChartLoading(),
      error: (error, _) => _ChartError(
        error: error,
        onRetry: () =>
            ref.invalidate(muscleGroupSeriesProvider(widget.range)),
      ),
      data: (points) {
        if (points.isEmpty) {
          return const _ChartEmpty(
            icon: Icons.pie_chart_outline,
            message: 'Complete a workout to see your muscle-group split.',
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
              muscleName: 'Other',
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
          caption: 'Most trained · '
              '${grouped.first.totalVolumeKg.toStringAsFixed(0)} kg',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Mirrors the canvas tooltip as real text — canvas-painted
              // tooltips aren't reachable by screen readers or widget
              // tests, so every value the tooltip shows needs a plain-text
              // home too.
              Text(
                touched == null
                    ? 'Tap or hover a bar for details.'
                    : '${grouped[touched].muscleName}: '
                        '${grouped[touched].totalVolumeKg.toStringAsFixed(0)} kg',
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
                                text:
                                    '${muscle.totalVolumeKg.toStringAsFixed(0)} kg',
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

class _BodyMetricsSection extends ConsumerWidget {
  const _BodyMetricsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<BodyMetrics>> async =
        ref.watch(bodyMetricsSeriesProvider);
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final ThemeData theme = Theme.of(context);

    return async.when(
      loading: () => const _ChartLoading(),
      error: (error, _) => _ChartError(
        error: error,
        onRetry: () => ref.invalidate(bodyMetricsSeriesProvider),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return AppCard(
            child: Column(
              children: <Widget>[
                const EmptyState(
                  icon: Icons.monitor_weight_outlined,
                  title: 'No measurements yet',
                  message: 'Track weight and body fat over time.',
                ),
                FilledButton.icon(
                  onPressed: () => _edit(context, ref, unit: unit),
                  icon: const Icon(Icons.add),
                  label: const Text('Log measurement'),
                ),
              ],
            ),
          );
        }

        final BodyMetrics latest = entries.first;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _ChartCard(
              headline: UnitFormatters.weight(latest.weightKg, unit),
              caption: latest.bodyFatPercentage == null
                  ? DateFormatters.relativeDay(latest.date)
                  : '${DateFormatters.relativeDay(latest.date)} · '
                      '${latest.bodyFatPercentage!.toStringAsFixed(1)}% body fat',
              child: entries.length >= 2
                  ? _BodyWeightChart(entries: entries, unit: unit)
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: () => _edit(context, ref, unit: unit),
              icon: const Icon(Icons.add),
              label: const Text('Log measurement'),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final BodyMetrics entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xs,
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      UnitFormatters.weight(entry.weightKg, unit),
                      style: AppTypography.numeric(
                        theme.textTheme.titleSmall ?? const TextStyle(),
                      ),
                    ),
                    subtitle: Text(
                      '${DateFormatters.full(entry.date)}'
                      '${entry.bodyFatPercentage == null ? '' : ' · ${entry.bodyFatPercentage!.toStringAsFixed(1)}% body fat'}',
                      style: AppTypography.caption(theme),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'edit') {
                          _edit(context, ref, entry: entry, unit: unit);
                        }
                        if (action == 'delete') {
                          ref
                              .read(bodyMetricsDaoProvider)
                              .deleteByDate(entry.date);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Weight is entered and shown in the user's display unit and converted
  /// to kilograms on save — ADR-1's boundary. The dialog used to be
  /// hard-labelled "kg" and stored the raw number, so a pounds user
  /// silently recorded pounds as kilograms.
  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    required WeightUnit unit,
    BodyMetrics? entry,
  }) async {
    final TextEditingController weight = TextEditingController(
      text: entry == null
          ? ''
          : UnitFormatters.plain(
              UnitFormatters.fromKg(entry.weightKg, unit),
            ),
    );
    final TextEditingController bodyFat = TextEditingController(
      text: entry?.bodyFatPercentage == null
          ? ''
          : UnitFormatters.plain(entry!.bodyFatPercentage!),
    );
    final DateTime date = entry?.date ?? DateTime.now();

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry == null ? 'Log measurement' : 'Edit measurement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormatters.full(date),
              style: AppTypography.caption(Theme.of(context)),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: weight,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Weight (${unit.label})',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: bodyFat,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Body fat % (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;

    final double? entered = double.tryParse(weight.text);
    if (entered == null || entered <= 0) return;
    final double weightKg = UnitFormatters.toKg(entered, unit);
    final double? fat = double.tryParse(bodyFat.text);

    await ref.read(bodyMetricsDaoProvider).upsert(
          BodyMetricsTableCompanion.insert(
            id: entry?.id ?? _uuid.v4(),
            date: date,
            weightKg: weightKg,
            bodyFatPercentage: Value(fat),
          ),
        );
  }
}

class _BodyWeightChart extends StatelessWidget {
  const _BodyWeightChart({required this.entries, required this.unit});

  final List<BodyMetrics> entries;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    // Stored newest-first; charts read left to right.
    final List<BodyMetrics> ordered = entries.reversed.toList();

    return SizedBox(
      height: _chartHeight,
      child: LineChart(
        LineChartData(
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
                getTitlesWidget: (double value, TitleMeta meta) => Text(
                  UnitFormatters.weight(value, unit, withUnit: false),
                  style: AppTypography.eyebrow(theme),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: _axisReserved,
                interval: _labelInterval(ordered.length),
                getTitlesWidget: (double value, TitleMeta meta) {
                  final int i = value.toInt();
                  if (i < 0 || i >= ordered.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      DateFormatters.relativeDay(ordered[i].date),
                      style: AppTypography.eyebrow(theme),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
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
                        text:
                            DateFormatters.full(ordered[spot.x.toInt()].date),
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
              // Plotted in kilograms; the axis and tooltip formatters do
              // the display conversion, exactly as the 1RM chart does.
              spots: [
                for (var i = 0; i < ordered.length; i++)
                  FlSpot(i.toDouble(), ordered[i].weightKg),
              ],
              isCurved: true,
              color: scheme.primary,
              barWidth: 3,
              dotData: FlDotData(show: ordered.length <= _dotThreshold),
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
