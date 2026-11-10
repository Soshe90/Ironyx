/// The Volume chapter: weekly volume, muscle groups, training balance
/// and rep ranges.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/daos/workout_dao.dart';
import '../../../../core/formatters/unit_formatters.dart';
import '../../../../core/formatters/weight_unit_controller.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../library/domain/exercise_catalogue_l10n.dart';
import '../../domain/progress_providers.dart';
import '../../domain/progress_summaries.dart';
import '../widgets/progress_charts.dart';
import '../widgets/progress_visuals.dart';

class VolumeSection extends ConsumerWidget {
  const VolumeSection({super.key, required this.range});

  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<WeeklyVolume>> async =
        ref.watch(weeklyVolumeSeriesProvider(range));
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    return async.when(
      loading: () => const ProgressChartLoading(),
      error: (error, _) => ProgressChartError(
        error: error,
        onRetry: () => ref.invalidate(weeklyVolumeSeriesProvider(range)),
      ),
      data: (points) {
        if (points.isEmpty) {
          return ProgressChartEmpty(
            icon: Icons.bar_chart,
            message: context.l10n.progressVolumeEmpty,
          );
        }

        final (:double totalKg, :int activeWeeks) =
            summarizeWeeklyVolume(points);

        return ProgressChartCard(
          headline: UnitFormatters.volume(totalKg, unit, context.l10n),
          caption: context.l10n.progressVolumeActiveWeeks(
            activeWeeks,
            points.length,
          ),
          child: WeeklyBarChart(
            axisLabel: (double kg) => UnitFormatters.volume(
              kg,
              unit,
              context.l10n,
              withUnit: false,
            ),
            displayScale: unit.perKilogram,
            weekStarts: <DateTime>[
              for (final WeeklyVolume p in points) p.weekStart,
            ],
            values: <double>[
              for (final WeeklyVolume p in points) p.totalVolumeKg,
            ],
            tooltipValue: (int i) => UnitFormatters.volume(
                points[i].totalVolumeKg, unit, context.l10n),
          ),
        );
      },
    );
  }
}

/// Healthy range for both balance ratios; shaded on each gauge and named in
/// the card's footnote (`progressReferenceBand`).
const double _balanceBandLow = 0.75;
const double _balanceBandHigh = 1.33;

class BalanceSection extends ConsumerWidget {
  const BalanceSection({super.key, required this.range});
  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(balanceRatiosProvider(range)).when(
            loading: () => const ProgressCardLoading(),
            error: (e, _) => ProgressChartError(
              error: e,
              onRetry: () => ref.invalidate(balanceRatiosProvider(range)),
            ),
            data: (b) => AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _RatioLine(
                    label: context.l10n.progressPushPull,
                    ratio: b.pushPullRatio,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _RatioLine(
                    label: context.l10n.progressUpperLower,
                    ratio: b.upperLowerRatio,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    context.l10n.progressReferenceBand,
                    style: AppTypography.caption(Theme.of(context)),
                  ),
                ],
              ),
            ),
          );
}

class RepRangeSection extends ConsumerWidget {
  const RepRangeSection({super.key, required this.range});
  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const List<Color> series = AppColors.chartSeries;
    return ref.watch(repRangeDistributionProvider(range)).when(
          loading: () => const ProgressCardLoading(),
          error: (e, _) => ProgressChartError(
            error: e,
            onRetry: () => ref.invalidate(repRangeDistributionProvider(range)),
          ),
          data: (rows) => AppCard(
            child: ProportionBar(
              segments: <ProportionSegment>[
                for (final row in rows)
                  ProportionSegment(
                    label: switch (row.range) {
                      RepRange.oneToFive =>
                        context.l10n.progressRepRangeOneToFive,
                      RepRange.sixToTwelve =>
                        context.l10n.progressRepRangeSixToTwelve,
                      RepRange.thirteenPlus =>
                        context.l10n.progressRepRangeThirteenPlus,
                    },
                    value: context.l10n.programTargetSets(row.setCount),
                    count: row.setCount,
                    // Fixed per bucket, so a colour keeps its meaning when
                    // one bucket is empty and drops out of the bar.
                    color: switch (row.range) {
                      RepRange.oneToFive => series[0],
                      RepRange.sixToTwelve => series[1],
                      RepRange.thirteenPlus => series[2],
                    },
                  ),
              ],
            ),
          ),
        );
  }
}

class _RatioLine extends StatelessWidget {
  const _RatioLine({required this.label, required this.ratio});
  final String label;
  final double? ratio;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;
    final double? value = ratio;
    final bool inBand =
        value != null && value >= _balanceBandLow && value <= _balanceBandHigh;
    final String status = value == null
        ? l10n.progressRatioInsufficient
        : inBand
            ? l10n.progressRatioBalanced
            : l10n.progressRatioOutsideBand;
    final String? formattedRatio =
        value == null ? null : UnitFormatters.ratio(value);
    return Semantics(
      label: formattedRatio == null
          ? l10n.progressRatioInsufficientSemantic(label)
          : l10n.progressRatioSemantic(label, formattedRatio, status),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(label, style: theme.textTheme.titleSmall),
                ),
                if (formattedRatio != null)
                  Text(
                    formattedRatio,
                    style: AppTypography.cardMetric(
                      theme.colorScheme,
                      size: AppTypography.metricSizeSm,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(status, style: AppTypography.caption(theme)),
            const SizedBox(height: AppSpacing.sm),
            RatioGauge(
              ratio: value,
              bandLow: _balanceBandLow,
              bandHigh: _balanceBandHigh,
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the volume went, as a ranked list of share bars.
///
/// This was a vertical bar chart whose names sat under bars a few dp wide,
/// so "Shoulders" broke over two lines and the exact figures existed only
/// in a canvas tooltip. Horizontal bars give every name a full line and
/// every figure plain text, at the cost of a little height.
///
/// Tapping a group shows its week-by-week volume under the list. That was
/// a separate table of muscle, week and kilograms, which printed the first
/// twelve rows of the range (its oldest two weeks) and nothing newer.
class MuscleGroupSection extends ConsumerStatefulWidget {
  const MuscleGroupSection({super.key, required this.range});

  final ProgressRange range;

  @override
  ConsumerState<MuscleGroupSection> createState() => _MuscleGroupSectionState();
}

class _MuscleGroupSectionState extends ConsumerState<MuscleGroupSection> {
  /// The group whose weeks are showing; the largest until one is tapped.
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final ProgressRange range = widget.range;
    final AsyncValue<List<MuscleGroupVolume>> async =
        ref.watch(muscleGroupSeriesProvider(range));
    // Volumes arrive in kilograms like every other stored weight; this card
    // once printed them raw with a hardcoded "kg" suffix, so a pounds user
    // read kilogram figures on the one card that never converted (ADR-1).
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final ThemeData theme = Theme.of(context);

    return async.when(
      loading: () => const ProgressChartLoading(),
      error: (error, _) => ProgressChartError(
        error: error,
        onRetry: () => ref.invalidate(muscleGroupSeriesProvider(range)),
      ),
      data: (all) {
        // One group per palette colour, the rest folded into "Other";
        // see groupMuscleVolume.
        final (
          groups: List<MuscleGroupVolume> grouped,
          :double total,
          :double largest,
        ) = groupMuscleVolume(
          all,
          slots: AppColors.muscleGroupSlots,
          otherName: context.l10n.progressOtherMuscles,
        );
        if (grouped.isEmpty) {
          return ProgressChartEmpty(
            icon: Icons.pie_chart_outline,
            message: context.l10n.progressMuscleGroupEmpty,
          );
        }

        final List<Color> palette =
            AppColors.muscleGroupPalette(theme.brightness);
        Color colorFor(int index, String muscleId) =>
            muscleId == otherMuscleGroupId
                ? AppColors.muscleGroupOther
                : palette[index % palette.length];
        // Stored names are English; "Other" is already localized above.
        String nameOf(MuscleGroupVolume group) => group.muscleId ==
                otherMuscleGroupId
            ? group.muscleName
            : localizedMuscleName(context, group.muscleId, group.muscleName);

        // A group can leave the range (or fold into "Other") while it is
        // selected; fall back to the largest rather than show nothing.
        final int selectedIndex = grouped.indexWhere(
          (MuscleGroupVolume g) =>
              g.muscleId == _selectedId && g.muscleId != otherMuscleGroupId,
        );
        final int shownIndex = selectedIndex < 0 ? 0 : selectedIndex;
        final MuscleGroupVolume shown = grouped[shownIndex];
        final String shownVolume =
            UnitFormatters.volume(shown.totalVolumeKg, unit, context.l10n);

        return ProgressChartCard(
          headline: nameOf(shown),
          caption: shownIndex == 0
              ? context.l10n.progressMostTrained(shownVolume)
              : context.l10n.progressMuscleShare(
                  shownVolume,
                  total <= 0 ? 0 : (shown.totalVolumeKg / total * 100).round(),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < grouped.length; i++)
                ShareBarRow(
                  label: nameOf(grouped[i]),
                  value: UnitFormatters.volume(
                    grouped[i].totalVolumeKg,
                    unit,
                    context.l10n,
                  ),
                  share: total <= 0 ? 0 : grouped[i].totalVolumeKg / total,
                  relative:
                      largest <= 0 ? 0 : grouped[i].totalVolumeKg / largest,
                  color: colorFor(i, grouped[i].muscleId),
                  selected: i == shownIndex,
                  // "Other" is several groups; it has no weeks of its own.
                  onTap: grouped[i].muscleId == otherMuscleGroupId
                      ? null
                      : () => setState(
                            () => _selectedId = grouped[i].muscleId,
                          ),
                ),
              const SizedBox(height: AppSpacing.lg),
              _MuscleWeeks(
                range: range,
                muscleId: shown.muscleId,
                color: colorFor(shownIndex, shown.muscleId),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One muscle group's volume week by week, as the detail of the group
/// selected in [MuscleGroupSection].
///
/// Plotted on the same zero-filled weeks as the weekly-volume chart, so a
/// week the group was not trained is a gap in the right place rather than
/// two bars drawn side by side.
class _MuscleWeeks extends ConsumerWidget {
  const _MuscleWeeks({
    required this.range,
    required this.muscleId,
    required this.color,
  });

  final ProgressRange range;
  final String muscleId;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final List<WeeklyVolume> axis =
        ref.watch(weeklyVolumeSeriesProvider(range)).value ??
            const <WeeklyVolume>[];

    return ref.watch(weeklyMuscleGroupVolumeSeriesProvider(range)).when(
          loading: () => const LoadingShimmer(
            height: progressDetailChartHeight,
            radius: AppRadius.md,
          ),
          error: (Object error, _) => ErrorView(
            title: context.l10n.progressChartLoadFailed,
            details: error.toString(),
            compact: true,
            onRetry: () =>
                ref.invalidate(weeklyMuscleGroupVolumeSeriesProvider(range)),
          ),
          data: (List<WeeklyMuscleGroupVolume> all) {
            final (:List<DateTime> weeks, :List<double> values) =
                muscleWeeklySeries(muscleId: muscleId, rows: all, axis: axis);
            if (weeks.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  context.l10n.progressWeeklyVolumeTitle.toUpperCase(),
                  style: AppTypography.eyebrow(theme),
                ),
                const SizedBox(height: AppSpacing.md),
                WeeklyBarChart(
                  axisLabel: (double kg) => UnitFormatters.volume(
                    kg,
                    unit,
                    context.l10n,
                    withUnit: false,
                  ),
                  displayScale: unit.perKilogram,
                  height: progressDetailChartHeight,
                  color: color,
                  weekStarts: weeks,
                  values: values,
                  tooltipValue: (int i) =>
                      UnitFormatters.volume(values[i], unit, context.l10n),
                ),
              ],
            );
          },
        );
  }
}
