import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/daos/workout_dao.dart';
import '../../../core/database/database_providers.dart';
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
import '../../../core/widgets/metric_explainer.dart';
import '../../../core/widgets/page_body.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/trend_badge.dart';
import '../../../core/widgets/value_row.dart';
import '../../library/domain/exercise_catalogue_l10n.dart';
import '../domain/bmi.dart';
import '../domain/progress_insights.dart';
import '../domain/progress_providers.dart';
import '../domain/strength_analytics.dart';
import 'progress_explainers.dart';
import 'widgets/body_metric_widgets.dart';
import 'widgets/progress_visuals.dart';

/// Height of a full chart. One value for all of them, so the page has a
/// consistent rhythm instead of three hand-picked heights.
const double _chartHeight = 220;
const double _axisReserved = 28;
const double _barWidth = 22;

/// Dash pattern for chart gridlines: present enough to read values against,
/// quiet enough not to compete with the data.
const List<int> _gridDash = <int>[4, 4];

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

    // Nothing logged yet: one screen-level invitation instead of a dozen
    // identical "No data yet" cards. Body measurements stay, because they
    // can be recorded before any workout exists.
    final AsyncValue<List<LoggedExercise>> logged =
        ref.watch(loggedExercisesProvider);
    if (logged.hasValue && logged.value!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.navProgress)),
        body: PageBody(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EmptyState(
                  icon: Icons.insights_outlined,
                  title: l10n.progressEmptyTitle,
                  message: l10n.progressEmptyMessage,
                  actionLabel: l10n.dashboardStartWorkout,
                  onAction: () => context.pushNamed(Routes.activeWorkoutName),
                ),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(
                  title: l10n.progressBodyMetricsTitle,
                  subtitle: l10n.progressBodyMetricsSubtitle,
                ),
                _BodyMetricsSection(range: range),
              ],
            ),
          ),
        ),
      );
    }

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
              const SizedBox(height: AppSpacing.lg),
              ProgressOverviewHero(range: range),
              const SizedBox(height: AppSpacing.md),
              _InsightsSection(range: range),

              // ---- Strength: "am I getting stronger?" ----
              ProgressChapter(title: l10n.progressChapterStrength),
              SectionHeader(
                title: l10n.progressStrengthChangeTitle,
                subtitle: l10n.progressStrengthSubtitle(range.name),
                explainer: ProgressExplainers.strengthChange(l10n),
              ),
              _StrengthChangeSection(range: range),
              _RelativeStrengthSection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: l10n.progressEstimatedOneRmTitle,
                subtitle: l10n.progressEstimatedOneRmSubtitle,
                explainer: ProgressExplainers.oneRm(l10n),
              ),
              _OneRmSection(
                range: range,
                exerciseId: _exerciseId,
                onExerciseChanged: (String? id) =>
                    setState(() => _exerciseId = id),
              ),
              _SessionVolumeSection(range: range, exerciseId: _exerciseId),

              // ---- Volume: "how much work, and where did it go?" ----
              ProgressChapter(title: l10n.progressChapterVolume),
              SectionHeader(
                title: l10n.progressWeeklyVolumeTitle,
                subtitle: l10n.progressWeeklyVolumeSubtitle(range.name),
                explainer: ProgressExplainers.volume(l10n),
              ),
              _VolumeSection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: l10n.progressVolumeByMuscleGroupTitle),
              _MuscleGroupSection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: l10n.progressWeeklyVolumeByMuscleTitle),
              _WeeklyMuscleSection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: l10n.progressTrainingBalanceTitle,
                explainer: ProgressExplainers.balance(l10n),
              ),
              _BalanceSection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: l10n.progressRepRangeDistributionTitle,
                explainer: ProgressExplainers.repRange(l10n),
              ),
              _RepRangeSection(range: range),

              // ---- Habits: "am I showing up, and how hard?" ----
              ProgressChapter(title: l10n.progressChapterHabits),
              SectionHeader(
                title: l10n.progressConsistencyTitle,
                explainer: ProgressExplainers.consistency(l10n),
              ),
              _ConsistencySection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: l10n.progressWorkoutFrequencyTitle),
              _FrequencySection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: l10n.progressTrainingDaysTitle),
              _WeekdaySection(range: range),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: l10n.progressEffortRecoveryTitle,
                explainer: ProgressExplainers.rpe(l10n),
              ),
              _RpeSection(range: range),
              _RestSection(range: range),

              // ---- Body ----
              ProgressChapter(title: l10n.progressChapterBody),
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
///
/// Shows the first [_strengthPreview] lifts and folds the rest behind a
/// toggle: someone training fifteen exercises had a three-screen list here,
/// which pushed every other chapter out of reach.
class _StrengthChangeSection extends ConsumerStatefulWidget {
  const _StrengthChangeSection({required this.range});

  final ProgressRange range;

  @override
  ConsumerState<_StrengthChangeSection> createState() =>
      _StrengthChangeSectionState();
}

const int _strengthPreview = 5;

class _StrengthChangeSectionState
    extends ConsumerState<_StrengthChangeSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ProgressRange range = widget.range;
    final AsyncValue<List<StrengthChange>> async =
        ref.watch(strengthChangeProvider(range));
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final Map<String, String> slugsById = ref.watch(exerciseSlugsByIdProvider);

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
        final int hidden = rows.length - _strengthPreview;
        final List<StrengthChange> shown = _expanded || hidden <= 0
            ? rows
            : rows.take(_strengthPreview).toList();
        final Color divider = Theme.of(context).colorScheme.outlineVariant;
        return AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < shown.length; i++) ...<Widget>[
                if (i > 0) Divider(height: 1, thickness: 1, color: divider),
                _StrengthRow(
                  row: shown[i],
                  unit: unit,
                  displayName: localizedExerciseName(
                    context,
                    slugsById,
                    shown[i].exerciseId,
                    shown[i].exerciseName,
                  ),
                ),
              ],
              if (hidden > 0) ...<Widget>[
                Divider(height: 1, thickness: 1, color: divider),
                TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                  ),
                  label: Text(
                    _expanded
                        ? context.l10n.progressShowFewerLifts
                        : context.l10n.progressShowAllLifts(hidden),
                  ),
                ),
              ],
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
    final Map<String, String> slugsById = ref.watch(exerciseSlugsByIdProvider);
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                context.l10n.progressRelativeStrengthTitle,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            MetricInfoButton(
                              explainer: ProgressExplainers.relativeStrength(
                                context.l10n,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          context.l10n.progressRelativeStrengthSubtitle,
                          style: AppTypography.caption(Theme.of(context)),
                        ),
                        for (final row in rows.take(6))
                          ValueRow(
                            label: localizedExerciseName(
                              context,
                              slugsById,
                              row.exerciseId,
                              row.exerciseName,
                            ),
                            value: context.l10n.progressRelativeStrengthRatio(
                              row.ratio.toStringAsFixed(2),
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
  const _StrengthRow({
    required this.row,
    required this.unit,
    required this.displayName,
  });

  final StrengthChange row;
  final WeightUnit unit;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = context.l10n;
    final double? change = row.change;
    final String currentEstimate =
        UnitFormatters.estimate(row.currentBestKg, unit, context.l10n);

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
              displayName,
              currentEstimate,
            )
          : l10n.progressStrengthSemantic(
              displayName,
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
                      displayName,
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
                                context.l10n,
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
    final previousMuscles = ref.watch(previousMuscleGroupSeriesProvider(range));
    final personalRecords = ref.watch(recentPersonalRecordsProvider(range));
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    if (strength.isLoading ||
        volume.isLoading ||
        frequency.isLoading ||
        muscles.isLoading ||
        previousMuscles.isLoading ||
        personalRecords.isLoading) {
      return const _ChartLoading();
    }
    Object? error;
    for (final value in [
      strength,
      volume,
      frequency,
      muscles,
      previousMuscles,
      personalRecords,
    ]) {
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
          ref.invalidate(previousMuscleGroupSeriesProvider(range));
          ref.invalidate(recentPersonalRecordsProvider(range));
        },
      );
    }

    final insights = buildProgressInsights(
      strengthChanges: strength.value ?? const [],
      volume: volume.value ?? const [],
      frequency: frequency.value ?? const [],
      currentMuscleVolume: muscles.value ?? const [],
      previousMuscleVolume: previousMuscles.value ?? const [],
      recentPersonalRecords: personalRecords.value ?? 0,
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
            UnitFormatters.estimate(insight.currentBestKg!, unit, context.l10n),
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
    final ThemeData theme = Theme.of(context);
    final bool light = theme.brightness == Brightness.light;
    // Records read amber everywhere (PrBadge); gains green, slips red, and a
    // prompt to act in the brand colour rather than a third alarm hue.
    final (IconData icon, Color color) = switch ((
      insight.kind,
      insight.severity,
    )) {
      (InsightKind.personalRecords, _) => (
          Icons.emoji_events_rounded,
          light ? AppColors.personalRecordInkLight : AppColors.personalRecord,
        ),
      (_, InsightSeverity.actionable) => (
          Icons.flag_rounded,
          theme.colorScheme.primary,
        ),
      (_, InsightSeverity.negative) => (
          Icons.trending_down_rounded,
          light ? AppColors.lossInkLight : AppColors.loss,
        ),
      _ => (
          Icons.trending_up_rounded,
          light ? AppColors.gainInkLight : AppColors.gain,
        ),
    };
    return Semantics(
      container: true,
      label: l10n.progressInsightSemantic(
        text.headline,
        text.figure,
        target,
      ),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ProgressIconChip(icon: icon, color: color),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(text.headline, style: theme.textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      l10n.progressInsightSubtitle(text.figure, target),
                      style: AppTypography.caption(theme),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
    final Map<String, String> slugsById = ref.watch(exerciseSlugsByIdProvider);

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
                    localizedExerciseName(
                      context,
                      slugsById,
                      item.exerciseId,
                      item.exerciseName,
                    ),
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
                    UnitFormatters.estimate(first, unit, context.l10n),
                    ordered.length,
                  )
                : context.l10n.progressOneRmMonthlyTrend(
                    '${regression.slopeKgPerMonth >= 0 ? '+' : ''}'
                    '${UnitFormatters.weightRate(regression.slopeKgPerMonth, unit, context.l10n)}',
                    ordered.length,
                  );

            return _ChartCard(
              header: picker,
              headline: UnitFormatters.estimate(current, unit, context.l10n),
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
                          ValueRow(
                            label:
                                DateFormatters.of(context).axisLabel(row.date),
                            value: UnitFormatters.volume(
                                row.volumeKg, unit, context.l10n),
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
              dashArray: _gridDash,
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
                  // fl_chart always labels the axis maximum as well as each
                  // interval, so the last interval label can land on top of
                  // it ("21 Sep 24 Sep"). Keep the maximum — the latest
                  // session is the date people look for — and drop the
                  // interval label crowding it.
                  if (value != meta.max &&
                      meta.max - value < meta.appliedInterval * 0.6) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    // Keeps the edge labels inside the card instead of
                    // clipping half a date off the right edge.
                    fitInside: SideTitleFitInsideData.fromTitleMeta(
                      meta,
                      distanceFromEdge: 0,
                    ),
                    child: _axisDate(
                      context,
                      theme,
                      first.add(
                        Duration(minutes: (value * _minutesPerDay).round()),
                      ),
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
                    '${UnitFormatters.weight(spot.y, unit, context.l10n)}\n',
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
                  // Records are amber everywhere else (PrBadge); a ring in
                  // the card colour separates the dot from the line.
                  color: ordered[index].isPersonalRecord
                      ? AppColors.personalRecord
                      : scheme.primary,
                  strokeWidth: ordered[index].isPersonalRecord ? 2 : 0,
                  strokeColor: theme.brightness == Brightness.light
                      ? scheme.surfaceContainerLowest
                      : scheme.surfaceContainerLow,
                ),
              ),
              // Fades to nothing at the baseline so the area reads as the
              // line's shadow rather than a filled block.
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    scheme.primary.withValues(alpha: 0.28),
                    scheme.primary.withValues(alpha: 0),
                  ],
                ),
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

/// Weekly bars represent Monday through Sunday, so a start date alone can
/// make a Sunday workout appear to have been logged on the prior Monday.
Widget _weeklyAxisDate(
  BuildContext context,
  ThemeData theme,
  DateTime weekStart,
) {
  final formatter = DateFormatters.of(context);
  final weekEnd = weekStart.add(const Duration(days: 6));
  return Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs),
    child: Text(
      '${formatter.axisLabel(weekStart)}–${formatter.axisLabel(weekEnd)}',
      style: AppTypography.eyebrow(theme),
      textAlign: TextAlign.center,
    ),
  );
}

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
    UnitFormatters.weight(value, unit, context.l10n, withUnit: false),
    style: AppTypography.eyebrow(Theme.of(context)),
  );
}

/// Keeps x-axis labels from colliding by showing at most a handful.
double _labelInterval(int count, {int maxLabels = 4}) {
  if (count <= maxLabels) return 1;
  return (count / maxLabels).ceilToDouble();
}

/// Horizontal room one week-range label ("24 Aug–30 Aug") needs, gap
/// included. A fixed four labels fitted on a tablet but ran two ranges
/// together on a phone once the edge labels were kept inside the card.
const double _weekLabelSlot = 120;

/// How many week-range labels fit across [available] width, never fewer
/// than two so the first and a later week are always anchored.
int _weekLabelsThatFit(double available) =>
    (available ~/ _weekLabelSlot).clamp(2, 4);

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
          headline: UnitFormatters.volume(total, unit, context.l10n),
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
            tooltipValue: (int i) => UnitFormatters.volume(
                points[i].totalVolumeKg, unit, context.l10n),
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
    final ThemeData theme = Theme.of(context);
    final bool light = theme.brightness == Brightness.light;
    final AppLocalizations l10n = context.l10n;
    return ref.watch(consistencySummaryProvider(range)).when(
          loading: () => const ProgressCardLoading(),
          error: (e, _) => _ChartError(
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

/// A titled card of dated rows: the shape both effort and rest take.
class _DatedListCard extends StatelessWidget {
  const _DatedListCard({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final Color divider = Theme.of(context).colorScheme.outlineVariant;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          for (int i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0) Divider(height: 1, thickness: 1, color: divider),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _RpeSection extends ConsumerWidget {
  const _RpeSection({required this.range});
  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    return ref.watch(rpeAnalyticsProvider(range)).when(
          loading: () => const ProgressCardLoading(),
          error: (e, _) => _ChartError(
            error: e,
            onRetry: () => ref.invalidate(rpeAnalyticsProvider(range)),
          ),
          data: (rows) => rows.isEmpty
              ? _ChartEmpty(
                  icon: Icons.speed_outlined,
                  message: context.l10n.progressRpeEmpty,
                )
              : _DatedListCard(
                  title: context.l10n.progressSessionRpeTitle,
                  rows: <Widget>[
                    for (final row in rows.take(8))
                      ValueRow(
                        label: DateFormatters.of(context).axisLabel(row.date),
                        value: context.l10n.progressSessionRpeValue(
                          row.averageRpe.toStringAsFixed(1),
                          UnitFormatters.volume(
                            row.volumeKg,
                            unit,
                            context.l10n,
                          ),
                        ),
                      ),
                  ],
                ),
        );
  }
}

class _RestSection extends ConsumerWidget {
  const _RestSection({required this.range});
  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget content = ref.watch(restAnalyticsProvider(range)).when(
          loading: () => const ProgressCardLoading(),
          error: (e, _) => _ChartError(
            error: e,
            onRetry: () => ref.invalidate(restAnalyticsProvider(range)),
          ),
          data: (rows) => rows.isEmpty
              ? _ChartEmpty(
                  icon: Icons.timer_outlined,
                  message: context.l10n.progressRestEmpty,
                )
              : _DatedListCard(
                  title: context.l10n.progressRestTimeTitle,
                  rows: <Widget>[
                    for (final row in rows.take(8))
                      ValueRow(
                        label: DateFormatters.of(context).axisLabel(row.date),
                        // The sample size is part of the number: a session
                        // where rest was recorded once reads as that
                        // session's rest habit without it. It sits under the
                        // date rather than beside the average, which
                        // overflows a narrow phone.
                        caption: context.l10n.progressRestFromSets(
                          row.recordedSetCount,
                        ),
                        value: context.l10n.progressAverageRestSeconds(
                          row.averageRestSeconds.round(),
                        ),
                      ),
                  ],
                ),
        );
    // Stacked under the effort card; without a gap the two read as one.
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: content,
    );
  }
}

/// Healthy range for both balance ratios; shaded on each gauge and named in
/// the card's footnote (`progressReferenceBand`).
const double _balanceBandLow = 0.75;
const double _balanceBandHigh = 1.33;

class _BalanceSection extends ConsumerWidget {
  const _BalanceSection({required this.range});
  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(balanceRatiosProvider(range)).when(
            loading: () => const ProgressCardLoading(),
            error: (e, _) => _ChartError(
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

class _WeeklyMuscleSection extends ConsumerWidget {
  const _WeeklyMuscleSection({required this.range});
  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    return ref.watch(weeklyMuscleGroupVolumeSeriesProvider(range)).when(
          loading: () => const ProgressCardLoading(),
          error: (e, _) => _ChartError(
            error: e,
            onRetry: () =>
                ref.invalidate(weeklyMuscleGroupVolumeSeriesProvider(range)),
          ),
          data: (all) {
            // A muscle the week did not train is listed by the query at
            // 0 kg; a column of zeros said nothing and pushed the real
            // figures down, so only trained groups are shown.
            final rows = all.where((r) => r.totalVolumeKg > 0).toList();
            if (rows.isEmpty) {
              return _ChartEmpty(
                icon: Icons.groups_outlined,
                message: context.l10n.progressWeeklyMuscleEmpty,
              );
            }
            final Color divider = Theme.of(context).colorScheme.outlineVariant;
            final List<Widget> lines = <Widget>[
              for (final row in rows.take(12))
                ValueRow(
                  label: row.muscleName,
                  caption: DateFormatters.of(context).axisLabel(row.weekStart),
                  value: UnitFormatters.volume(
                    row.totalVolumeKg,
                    unit,
                    context.l10n,
                  ),
                ),
            ];
            return AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < lines.length; i++) ...<Widget>[
                    if (i > 0) Divider(height: 1, thickness: 1, color: divider),
                    lines[i],
                  ],
                ],
              ),
            );
          },
        );
  }
}

class _RepRangeSection extends ConsumerWidget {
  const _RepRangeSection({required this.range});
  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const List<Color> series = AppColors.chartSeries;
    return ref.watch(repRangeDistributionProvider(range)).when(
          loading: () => const ProgressCardLoading(),
          error: (e, _) => _ChartError(
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

class _WeekdaySection extends ConsumerWidget {
  const _WeekdaySection({required this.range});
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
          error: (e, _) => _ChartError(
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
    final String? formattedRatio = value?.toStringAsFixed(2);
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
          final int labelStep = _labelInterval(
            weekStarts.length,
            maxLabels: _weekLabelsThatFit(constraints.maxWidth),
          ).round();
          return BarChart(
            BarChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: scheme.outlineVariant,
                  strokeWidth: 1,
                  dashArray: _gridDash,
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
                    interval: labelStep.toDouble(),
                    getTitlesWidget: (double value, TitleMeta meta) {
                      final int i = value.toInt();
                      if (i < 0 || i >= weekStarts.length) {
                        return const SizedBox.shrink();
                      }
                      // fl_chart's `BarChart` does not reliably honor
                      // `interval` on a discrete per-bar axis the way
                      // `LineChart` does on a continuous one (see
                      // `_dayLabelInterval`'s usage above, which needs no
                      // such check) — without filtering here too, every bar
                      // gets a label regardless of `interval`, and on a
                      // range with more than a handful of weeks they
                      // overlap into an unreadable smear.
                      //
                      // Counted back from the newest week so the most recent
                      // bars, the ones people look at, always carry a date.
                      if ((weekStarts.length - 1 - i) % labelStep != 0) {
                        return const SizedBox.shrink();
                      }
                      // A week range is wider than one bar, so the first
                      // and last labels hung off the card and were clipped
                      // ("2 Jun–28 Jun" lost its first digit).
                      return SideTitleWidget(
                        axisSide: meta.axisSide,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(
                          meta,
                          distanceFromEdge: 0,
                        ),
                        child: _weeklyAxisDate(context, theme, weekStarts[i]),
                      );
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
                        // The newest week is the one being judged; earlier
                        // weeks are context, so they step back.
                        color: i == values.length - 1
                            ? scheme.primary
                            : scheme.primary.withValues(alpha: 0.45),
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

/// Where the volume went, as a ranked list of share bars.
///
/// This was a vertical bar chart whose names sat under bars a few dp wide,
/// so "Shoulders" broke over two lines and the exact figures existed only
/// in a canvas tooltip. Horizontal bars give every name a full line and
/// every figure plain text, at the cost of a little height.
class _MuscleGroupSection extends ConsumerWidget {
  const _MuscleGroupSection({required this.range});

  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<MuscleGroupVolume>> async =
        ref.watch(muscleGroupSeriesProvider(range));
    // Volumes arrive in kilograms like every other stored weight; this card
    // once printed them raw with a hardcoded "kg" suffix, so a pounds user
    // read kilogram figures on the one card that never converted (ADR-1).
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final ThemeData theme = Theme.of(context);

    return async.when(
      loading: () => const _ChartLoading(),
      error: (error, _) => _ChartError(
        error: error,
        onRetry: () => ref.invalidate(muscleGroupSeriesProvider(range)),
      ),
      data: (all) {
        // A group linked only through bodyweight sets totals 0 kg; as a
        // ranked bar it is an empty track that reads like missing data.
        final List<MuscleGroupVolume> points = <MuscleGroupVolume>[
          for (final MuscleGroupVolume p in all)
            if (p.totalVolumeKg > 0) p,
        ];
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

        final double total =
            grouped.fold<double>(0, (sum, p) => sum + p.totalVolumeKg);
        final double largest = grouped.fold<double>(
          0,
          (max, p) => p.totalVolumeKg > max ? p.totalVolumeKg : max,
        );

        return _ChartCard(
          headline: grouped.first.muscleName,
          caption: context.l10n.progressMostTrained(
            UnitFormatters.volume(
                grouped.first.totalVolumeKg, unit, context.l10n),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < grouped.length; i++)
                ShareBarRow(
                  label: grouped[i].muscleName,
                  value: UnitFormatters.volume(
                    grouped[i].totalVolumeKg,
                    unit,
                    context.l10n,
                  ),
                  share: total <= 0 ? 0 : grouped[i].totalVolumeKg / total,
                  relative:
                      largest <= 0 ? 0 : grouped[i].totalVolumeKg / largest,
                  color: colorFor(i, grouped[i].muscleId),
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
              headline:
                  UnitFormatters.weight(latest.weightKg, unit, context.l10n),
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
