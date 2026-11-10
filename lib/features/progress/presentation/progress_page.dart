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
import '../../../core/formatters/week_start_controller.dart';
import '../../../core/formatters/weight_unit_controller.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/router/routes.dart';
import '../../../core/services/clock.dart';
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
import '../../../core/widgets/segmented_pills.dart';
import '../../../core/widgets/trend_badge.dart';
import '../../../core/widgets/value_row.dart';
import '../../library/domain/exercise_catalogue_l10n.dart';
import '../domain/bmi.dart';
import '../domain/consistency_calculators.dart';
import '../domain/progress_insights.dart';
import '../domain/progress_providers.dart';
import '../domain/progress_summaries.dart';
import '../domain/strength_analytics.dart';
import 'progress_explainers.dart';
import 'widgets/body_metric_widgets.dart';
import 'widgets/chart_axis.dart';
import 'widgets/progress_visuals.dart';

/// Height of a full chart. One value for all of them, so the page has a
/// consistent rhythm instead of three hand-picked heights.
const double _chartHeight = 220;

/// Height of a chart that sits inside another card as detail (one muscle
/// group's weeks), where a full-height plot would bury the list above it.
const double _detailChartHeight = 140;

/// How far below the top of the scroll view a chapter heading may sit and
/// still count as the chapter being read.
const double _chapterReadLine = AppSpacing.xxxl;

/// The page's chapters, in order. The tab row and the scroll position both
/// speak in these.
enum _Chapter { strength, volume, habits, body }

const double _axisReserved = 28;

/// Width kept for value-axis labels ("1,250", "242.5").
const double _valueAxisReserved = _axisReserved + AppSpacing.lg;
const double _barWidth = 22;

/// Dash pattern for chart gridlines: present enough to read values against,
/// quiet enough not to compete with the data.
const List<int> _gridDash = <int>[4, 4];

/// Progress and analytics hub.
///
/// The range control is global and pinned above the scroll view: every
/// chart below answers a question about the same window, so it has to stay
/// in reach from any of them. (It used to scroll away with the first
/// section.) Under it, a row of chapter tabs jumps to a chapter and follows
/// the reader's position, because the page is several screens long.
class ProgressPage extends ConsumerStatefulWidget {
  const ProgressPage({super.key});

  @override
  ConsumerState<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends ConsumerState<ProgressPage> {
  final GlobalKey _viewportKey = GlobalKey();
  final Map<_Chapter, GlobalKey> _chapterKeys = <_Chapter, GlobalKey>{
    for (final _Chapter chapter in _Chapter.values) chapter: GlobalKey(),
  };

  /// The chapter being read, or null above the first one.
  ///
  /// This and [_scrolled] are notifiers rather than `setState` fields: they
  /// change while the reader scrolls, and only the pinned tab row and its
  /// hairline show them. As page state, every chapter boundary crossed
  /// rebuilt all thirty sections and every chart, mid-fling.
  final ValueNotifier<_Chapter?> _active = ValueNotifier<_Chapter?>(null);

  /// True while a tab tap is scrolling to its chapter, so the chapters
  /// passed on the way do not each light up in turn. Read only by
  /// [_onScroll], never by `build`, so changing it needs no rebuild.
  bool _jumping = false;

  /// Counts tab taps, so a jump that a later tap has overtaken does not
  /// end the later one's [_jumping] when it finishes.
  int _jump = 0;

  /// Whether anything has scrolled under the pinned controls.
  final ValueNotifier<bool> _scrolled = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _active.dispose();
    _scrolled.dispose();
    super.dispose();
  }

  /// The last chapter whose heading has reached the top of the scroll view.
  _Chapter? _chapterAtTop() {
    final RenderObject? viewport =
        _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox) return null;
    _Chapter? current;
    for (final _Chapter chapter in _Chapter.values) {
      final RenderObject? heading =
          _chapterKeys[chapter]!.currentContext?.findRenderObject();
      if (heading is! RenderBox || !heading.attached) continue;
      final double top =
          heading.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top <= _chapterReadLine) current = chapter;
    }
    return current;
  }

  bool _onScroll(ScrollNotification notification) {
    // Depth 0 is the page itself; anything deeper is a scrollable inside it.
    if (notification.depth != 0) return false;
    final ScrollMetrics metrics = notification.metrics;
    _Chapter? chapter = _active.value;
    if (!_jumping) {
      chapter = _chapterAtTop();
      // The last chapter can be too short for its heading ever to reach
      // the top, so the end of the page counts as reading it.
      if (metrics.maxScrollExtent > 0 &&
          metrics.pixels >= metrics.maxScrollExtent - 1) {
        chapter = _Chapter.values.last;
      }
    }
    // A notifier only notifies when its value really changes.
    _active.value = chapter;
    _scrolled.value = metrics.pixels > 0;
    return false;
  }

  Future<void> _jumpTo(_Chapter chapter) async {
    final BuildContext? heading = _chapterKeys[chapter]!.currentContext;
    if (heading == null) return;
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final int jump = ++_jump;
    _active.value = chapter;
    _jumping = true;
    await Scrollable.ensureVisible(
      heading,
      duration: reduceMotion ? Duration.zero : AppDuration.slow,
      curve: Curves.easeOutCubic,
    );
    if (mounted && jump == _jump) _jumping = false;
  }

  @override
  Widget build(BuildContext context) {
    final ProgressRange range = ref.watch(progressRangeControllerProvider);

    final AppLocalizations l10n = context.l10n;

    // Nothing logged yet: one screen-level invitation instead of a dozen
    // identical "No data yet" cards. Body measurements stay, because they
    // can be recorded before any workout exists.
    //
    // Selected down to the one fact the page needs: the list itself changes
    // with every set logged, and the whole page rebuilt with it.
    final bool nothingLogged = ref.watch(
      loggedExercisesProvider.select(
        (AsyncValue<List<LoggedExercise>> logged) =>
            logged.value?.isEmpty ?? false,
      ),
    );
    if (nothingLogged) {
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
                _BodyHeader(range: range),
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
        child: Column(
          children: <Widget>[
            _RangeSelector(range: range),
            ValueListenableBuilder<_Chapter?>(
              valueListenable: _active,
              builder: (BuildContext context, _Chapter? active, _) =>
                  ProgressChapterTabs<_Chapter>(
                chapters: <(_Chapter, String)>[
                  (_Chapter.strength, l10n.progressChapterStrength),
                  (_Chapter.volume, l10n.progressChapterVolume),
                  (_Chapter.habits, l10n.progressChapterHabits),
                  (_Chapter.body, l10n.progressChapterBody),
                ],
                active: active,
                onSelected: _jumpTo,
              ),
            ),
            // A hairline once content slides under the pinned controls, so
            // they read as a layer above it rather than part of it.
            ValueListenableBuilder<bool>(
              valueListenable: _scrolled,
              builder: (BuildContext context, bool scrolled, _) => Divider(
                height: 1,
                thickness: 1,
                color: scrolled
                    ? Theme.of(context).colorScheme.outlineVariant
                    : Colors.transparent,
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: SingleChildScrollView(
                  key: _viewportKey,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Column(
                    // ListView stretched its children to the full width; Column
                    // centres and shrink-wraps them unless told otherwise.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ProgressOverviewHero(range: range),
                      const SizedBox(height: AppSpacing.md),
                      _InsightsSection(range: range),

                      // ---- Strength: "am I getting stronger?" ----
                      ProgressChapter(
                        key: _chapterKeys[_Chapter.strength],
                        title: l10n.progressChapterStrength,
                        first: true,
                      ),
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
                      _OneRmSection(range: range),

                      // ---- Volume: "how much work, and where did it go?" ----
                      const SizedBox(height: ProgressChapter.gapBefore),
                      ProgressChapter(
                        key: _chapterKeys[_Chapter.volume],
                        title: l10n.progressChapterVolume,
                      ),
                      SectionHeader(
                        title: l10n.progressWeeklyVolumeTitle,
                        subtitle: l10n.progressWeeklyVolumeSubtitle(range.name),
                        explainer: ProgressExplainers.volume(l10n),
                      ),
                      _VolumeSection(range: range),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(
                          title: l10n.progressVolumeByMuscleGroupTitle),
                      _MuscleGroupSection(range: range),
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
                      const SizedBox(height: ProgressChapter.gapBefore),
                      ProgressChapter(
                        key: _chapterKeys[_Chapter.habits],
                        title: l10n.progressChapterHabits,
                      ),
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
                      _EffortSection(range: range),

                      // ---- Body ----
                      const SizedBox(height: ProgressChapter.gapBefore),
                      ProgressChapter(
                        key: _chapterKeys[_Chapter.body],
                        title: l10n.progressChapterBody,
                      ),
                      _BodyHeader(range: range),
                      _BodyMetricsSection(range: range),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Body chapter's heading. Logging is offered here, as a quiet action,
/// once there is something logged; with nothing logged the empty card below
/// carries the button instead, so it is never shown twice.
///
/// Its own widget so that a new measurement rebuilds this heading, not the
/// page around it.
class _BodyHeader extends ConsumerWidget {
  const _BodyHeader({required this.range});

  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final bool hasEntries = ref.watch(
      bodyMetricsSeriesProvider(range).select(
        (AsyncValue<List<BodyMetrics>> entries) =>
            entries.value?.isNotEmpty ?? false,
      ),
    );
    return SectionHeader(
      title: l10n.progressBodyMetricsTitle,
      subtitle: l10n.progressBodyMetricsSubtitle,
      actionLabel: hasEntries ? l10n.progressLogMeasurement : null,
      onAction: hasEntries
          ? () => showBodyMetricEditor(
                context,
                ref,
                unit: ref.read(weightUnitControllerProvider),
              )
          : null,
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
          // A supplement to the card above: nothing while it loads, rather
          // than a second shimmer.
          loading: () => const SizedBox.shrink(),
          // But a failure says so. It used to vanish as if there were no
          // recent weigh-in, which hid the error and offered no retry.
          error: (Object error, _) => Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: _ChartError(
              error: error,
              onRetry: () => ref.invalidate(relativeStrengthsProvider(range)),
            ),
          ),
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

    // Judged on the rounded figure the row prints, so the arrow, the
    // number and the spoken sentence agree. A change that rounds to 0%
    // was "up 0%" (or, exactly zero, "down 0 percent" to a screen
    // reader); it is unchanged.
    final int percent = change == null ? 0 : (change.abs() * 100).round();
    final TrendDirection? trend = change == null
        ? null
        : percent == 0
            ? TrendDirection.flat
            : change > 0
                ? TrendDirection.up
                : TrendDirection.down;

    return Semantics(
      label: trend == null
          ? l10n.progressStrengthSemanticNoChange(
              displayName,
              currentEstimate,
            )
          : l10n.progressStrengthSemantic(
              displayName,
              currentEstimate,
              trend.name,
              percent,
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
                TrendBadge(direction: trend, label: '$percent%'),
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
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final Map<String, String> slugsById = ref.watch(exerciseSlugsByIdProvider);

    if (strength.isLoading ||
        volume.isLoading ||
        frequency.isLoading ||
        muscles.isLoading ||
        previousMuscles.isLoading) {
      return const _ChartLoading();
    }
    Object? error;
    for (final value in [
      strength,
      volume,
      frequency,
      muscles,
      previousMuscles,
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
        },
      );
    }

    final insights = buildProgressInsights(
      strengthChanges: strength.value ?? const [],
      volume: volume.value ?? const [],
      frequency: frequency.value ?? const [],
      currentMuscleVolume: muscles.value ?? const [],
      previousMuscleVolume: previousMuscles.value ?? const [],
      // The same week settings the series were bucketed with.
      weekStart: ref.watch(weekStartControllerProvider),
      utcOffset: ref.watch(todayProvider).timeZoneOffset,
      now: ref.watch(localNowProvider),
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
                _InsightTile(
                  insight: insight,
                  unit: unit,
                  // The insight carries the stored English name; show the
                  // user's language, as every other card on the page does.
                  subjectName: switch ((insight.kind, insight.subjectId)) {
                    (InsightKind.strengthChange, final String id) =>
                      localizedExerciseName(
                        context,
                        slugsById,
                        id,
                        insight.subjectName ?? '',
                      ),
                    (InsightKind.neglectedMuscle, final String id) =>
                      localizedMuscleName(
                        context,
                        id,
                        insight.subjectName ?? '',
                      ),
                    _ => insight.subjectName,
                  },
                ),
          ],
        ),
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({
    required this.insight,
    required this.unit,
    required this.subjectName,
  });

  final ProgressInsight insight;
  final WeightUnit unit;

  /// The insight's exercise or muscle group, already in the user's language.
  final String? subjectName;

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
            subjectName!,
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
      InsightKind.neglectedMuscle => (
          headline: l10n.progressInsightNeglectedHeadline(subjectName!),
          figure: l10n.progressInsightNeglectedFigure,
        ),
    };
    final ThemeData theme = Theme.of(context);
    final bool light = theme.brightness == Brightness.light;
    // Gains green, slips red, and a prompt to act in the brand colour
    // rather than a third alarm hue.
    final (IconData icon, Color color) = switch (insight.severity) {
      InsightSeverity.actionable => (
          Icons.flag_rounded,
          theme.colorScheme.primary,
        ),
      InsightSeverity.negative => (
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
    return SegmentedPills<ProgressRange>(
      semanticLabel: context.l10n.progressRangeSemantic,
      segments: <PillSegment<ProgressRange>>[
        for (final ProgressRange option in ProgressRange.values)
          PillSegment<ProgressRange>(
            value: option,
            label: context.l10n.progressRangeLabel(option.name),
          ),
      ],
      selected: range,
      onChanged: (ProgressRange selection) =>
          ref.read(progressRangeControllerProvider.notifier).set(selection),
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

/// The plot area of a card whose header (a picker, a metric switch) is
/// already known: the header stays put and only the chart shimmers.
class _PlotLoading extends StatelessWidget {
  const _PlotLoading();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LoadingShimmer(width: 160, height: AppTypography.metricSizeLg),
          SizedBox(height: AppSpacing.lg),
          LoadingShimmer(height: _chartHeight, radius: AppRadius.md),
        ],
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

/// What the lift chart plots for the chosen exercise.
enum _LiftMetric { oneRm, volume }

/// One lift over time: its estimated 1RM, or the volume of each session.
///
/// Both are the same sessions on the same time axis, so they share a card
/// and a switch. The volume used to be a separate table of dates under the
/// chart, which listed the oldest eight sessions of the range and so never
/// reached the current week.
///
/// The chosen lift is this card's own state. It used to live on the page,
/// which only this card read, and choosing a lift rebuilt every section.
class _OneRmSection extends ConsumerStatefulWidget {
  const _OneRmSection({required this.range});

  final ProgressRange range;

  @override
  ConsumerState<_OneRmSection> createState() => _OneRmSectionState();
}

class _OneRmSectionState extends ConsumerState<_OneRmSection> {
  _LiftMetric _metric = _LiftMetric.oneRm;

  /// The lift being shown. Pinned to the most-trained lift on first build,
  /// so a change in which lift is trained most does not swap the chart
  /// under the reader.
  String? _exerciseId;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
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
            message: l10n.progressOneRmEmpty,
          );
        }

        // A lift can stop being listed (its workouts deleted); fall back to
        // the most-trained one rather than show nothing. Assigned without
        // setState: this build already shows it, and the field only
        // remembers the choice for the next one.
        if (!items.any((LoggedExercise i) => i.exerciseId == _exerciseId)) {
          _exerciseId = items.first.exerciseId;
        }
        final String selected = _exerciseId!;

        final Widget header = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DropdownButtonFormField<String>(
              // initialValue is read once; keyed so a fallback to another
              // lift resets the field instead of leaving it on an id that
              // is no longer one of its items (an assertion failure).
              key: ValueKey<String>(selected),
              initialValue: selected,
              decoration: InputDecoration(
                labelText: l10n.progressExerciseField,
              ),
              isExpanded: true,
              items: [
                for (final LoggedExercise item in items)
                  DropdownMenuItem<String>(
                    value: item.exerciseId,
                    child: Text(
                      l10n.progressExerciseWithSessions(
                        localizedExerciseName(
                          context,
                          slugsById,
                          item.exerciseId,
                          item.exerciseName,
                        ),
                        l10n.sessionCount(item.sessionCount),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (String? id) {
                if (id != null) setState(() => _exerciseId = id);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            SegmentedPills<_LiftMetric>(
              semanticLabel: l10n.progressChartMetricSemantic,
              segments: <PillSegment<_LiftMetric>>[
                PillSegment<_LiftMetric>(
                  value: _LiftMetric.oneRm,
                  label: l10n.progressMetricOneRm,
                ),
                PillSegment<_LiftMetric>(
                  value: _LiftMetric.volume,
                  label: l10n.progressMetricVolume,
                ),
              ],
              selected: _metric,
              onChanged: (_LiftMetric metric) =>
                  setState(() => _metric = metric),
            ),
          ],
        );

        return switch (_metric) {
          _LiftMetric.oneRm => _oneRm(context, selected, header, unit),
          _LiftMetric.volume => _volume(context, selected, header, unit),
        };
      },
    );
  }

  Widget _rangeEmpty(BuildContext context, Widget header) => _ChartCard(
        header: header,
        child: EmptyState(
          icon: Icons.show_chart,
          title: context.l10n.metricNoDataYet,
          message: context.l10n.progressExerciseRangeEmpty,
        ),
      );

  Widget _oneRm(
    BuildContext context,
    String selected,
    Widget header,
    WeightUnit unit,
  ) {
    final ProgressRange range = widget.range;
    final AppLocalizations l10n = context.l10n;
    return ref.watch(oneRmSeriesProvider(selected, range)).when(
          loading: () =>
              _ChartCard(header: header, child: const _PlotLoading()),
          error: (error, _) => _ChartError(
            error: error,
            onRetry: () => ref.invalidate(oneRmSeriesProvider(selected, range)),
          ),
          data: (points) {
            if (points.isEmpty) return _rangeEmpty(context, header);

            // The DAO returns newest first; charts read left to right.
            final List<OneRMSeriesPoint> ordered = points.reversed.toList();
            final double current = ordered.last.estimated1RM;
            final double first = ordered.first.estimated1RM;
            final LinearTrend? regression = linearTrend(ordered);
            final String trendCaption = regression == null
                ? l10n.progressOneRmFromSessions(
                    UnitFormatters.estimate(first, unit, l10n),
                    ordered.length,
                  )
                : l10n.progressOneRmMonthlyTrend(
                    '${regression.slopeKgPerMonth >= 0 ? '+' : ''}'
                    '${UnitFormatters.weightRate(regression.slopeKgPerMonth, unit, l10n)}',
                    ordered.length,
                  );

            return _ChartCard(
              header: header,
              headline: UnitFormatters.estimate(current, unit, l10n),
              caption: ordered.length == 1
                  ? l10n.progressOneDataPoint
                  : trendCaption,
              trend: ordered.length == 1 ? null : _trendOf(first, current),
              child: _DatedLineChart(
                displayScale: unit.perKilogram,
                ordered: <_DatedPoint>[
                  for (final OneRMSeriesPoint p in ordered)
                    _DatedPoint(
                      date: p.date,
                      value: p.estimated1RM,
                      tooltip:
                          UnitFormatters.weight(p.estimated1RM, unit, l10n),
                      isPersonalRecord: p.isPersonalRecord,
                    ),
                ],
                axisLabel: (double kg) =>
                    UnitFormatters.weight(kg, unit, l10n, withUnit: false),
              ),
            );
          },
        );
  }

  Widget _volume(
    BuildContext context,
    String selected,
    Widget header,
    WeightUnit unit,
  ) {
    final ProgressRange range = widget.range;
    final AppLocalizations l10n = context.l10n;
    return ref.watch(sessionVolumeLoadProvider(selected, range)).when(
          loading: () =>
              _ChartCard(header: header, child: const _PlotLoading()),
          error: (error, _) => _ChartError(
            error: error,
            onRetry: () =>
                ref.invalidate(sessionVolumeLoadProvider(selected, range)),
          ),
          data: (sessions) {
            if (sessions.isEmpty) return _rangeEmpty(context, header);

            // Oldest first from the DAO, which is the order a chart wants;
            // the headline is the newest session.
            final double first = sessions.first.volumeKg;
            final double latest = sessions.last.volumeKg;
            return _ChartCard(
              header: header,
              headline: UnitFormatters.volume(latest, unit, l10n),
              caption: sessions.length == 1
                  ? l10n.progressOneDataPoint
                  : l10n.progressSessionVolumeSubtitle,
              trend: sessions.length == 1 ? null : _trendOf(first, latest),
              child: _DatedLineChart(
                displayScale: unit.perKilogram,
                ordered: <_DatedPoint>[
                  for (final SessionVolumeLoad session in sessions)
                    _DatedPoint(
                      date: session.date,
                      value: session.volumeKg,
                      tooltip:
                          UnitFormatters.volume(session.volumeKg, unit, l10n),
                    ),
                ],
                axisLabel: (double kg) =>
                    UnitFormatters.weight(kg, unit, l10n, withUnit: false),
              ),
            );
          },
        );
  }
}

TrendDirection _trendOf(double first, double last) => last > first
    ? TrendDirection.up
    : last < first
        ? TrendDirection.down
        : TrendDirection.flat;

/// One dated value — the shape every line chart on the page plots.
class _DatedPoint {
  const _DatedPoint({
    required this.date,
    required this.value,
    required this.tooltip,
    this.detail,
    this.isPersonalRecord = false,
  });

  final DateTime date;

  /// Plotted as stored (kilograms, seconds, RPE); the axis and tooltip
  /// text do any display conversion (ADR-1).
  final double value;

  /// The value as the tooltip states it, already formatted.
  final String tooltip;

  /// Optional second fact for the tooltip, beside the date.
  final String? detail;
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
  const _DatedLineChart({
    required this.ordered,
    required this.axisLabel,
    this.displayScale = 1,
  });

  /// Oldest first.
  final List<_DatedPoint> ordered;

  /// Formats a value-axis tick, without a unit.
  final String Function(double value) axisLabel;

  /// Display units per plotted unit: the weight unit's per-kilogram factor
  /// for a weight, 1 for a count or a score. The axis step is chosen round
  /// in display units (see [niceAxisStep]).
  final double displayScale;

  static const double _minutesPerDay = 60 * 24;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) =>
            _chart(context, constraints.maxWidth),
      );

  Widget _chart(BuildContext context, double width) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    // Headroom above and below the data. Left to itself fl_chart fits the
    // axis to the exact minimum and maximum, which draws the extreme points
    // on the card's edge, and gives a series of equal values no height at
    // all: two identical weigh-ins were a line along the bottom border.
    _DatedPoint lowest = ordered.first;
    _DatedPoint highest = ordered.first;
    for (final _DatedPoint p in ordered) {
      if (p.value < lowest.value) lowest = p;
      if (p.value > highest.value) highest = p;
    }
    final double low = lowest.value;
    final double high = highest.value;
    final double spread = high - low;
    final double pad = spread > 0
        ? spread * 0.15
        : (high.abs() * 0.05).clamp(1.0, double.infinity);
    // No measure on this page is negative, so the padding never invents a
    // negative axis for a small value.
    final double minY = low - pad < 0 && low >= 0 ? 0 : low - pad;
    final double maxY = high + pad;
    // Round in what the reader sees, converted back to what is plotted.
    final double valueStep =
        niceAxisStep((maxY - minY) * displayScale) / displayScale;

    final DateTime first = ordered.first.date;
    double xOf(DateTime date) =>
        date.difference(first).inMinutes / _minutesPerDay;

    final double span = xOf(ordered.last.date);
    // A lone point — or several sharing one instant — spans nothing, and
    // fl_chart cannot scale a zero-width axis. Pad a day either side and let
    // the dot sit in the middle.
    final bool degenerate = span <= 0;
    final DateFormatters dates = DateFormatters.of(context);

    // The plot is a canvas: its points exist for a finger, not for a
    // screen reader. The sections this chart replaced were tables of text,
    // so the summary a reader needs is stated here instead.
    return Semantics(
      container: true,
      image: true,
      label: context.l10n.progressChartSemantic(
        dates.full(ordered.first.date),
        dates.full(ordered.last.date),
        ordered.last.tooltip,
        lowest.tooltip,
        highest.tooltip,
      ),
      // The axis ticks would otherwise be read out after the summary, as a
      // string of bare dates and numbers.
      child: ExcludeSemantics(
        child: SizedBox(
          height: _chartHeight,
          child: LineChart(
            LineChartData(
              minX: degenerate ? -1 : 0,
              maxX: degenerate ? 1 : span,
              minY: minY,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: valueStep,
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
                    reservedSize: _valueAxisReserved,
                    interval: valueStep,
                    getTitlesWidget: (double value, TitleMeta meta) =>
                        _valueAxisTick(context, value, meta, axisLabel),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: _axisReserved,
                    interval:
                        _dayLabelInterval(span, _dateLabelsThatFit(width)),
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
                        '${ordered[spot.spotIndex].tooltip}\n',
                        theme.textTheme.labelMedium!.copyWith(
                          color: scheme.onInverseSurface,
                          fontWeight: FontWeight.w600,
                        ),
                        children: [
                          TextSpan(
                            // Indexed by spot, not by x: x is now a day offset
                            // rather than a list position, so `x.toInt()` would
                            // read the wrong entry (or throw).
                            text: <String>[
                              DateFormatters.of(context)
                                  .full(ordered[spot.spotIndex].date),
                              if (ordered[spot.spotIndex].detail != null)
                                ordered[spot.spotIndex].detail!,
                            ].join(' · '),
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
                    for (final _DatedPoint p in ordered)
                      FlSpot(degenerate ? 0 : xOf(p.date), p.value),
                  ],
                  isCurved: true,
                  // Without this the smoothing swings past the points it joins:
                  // the line dipped under a lift's lowest logged estimate, a
                  // value no session ever had.
                  preventCurveOverShooting: true,
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

/// Weekly bars represent seven days from the first day of the week chosen
/// in Settings (Monday unless changed), so a start date alone can
/// make a workout on the last of them appear to have been logged on the
/// first.
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

/// Horizontal room one axis date ("24 Aug", "24 أغسطس") needs, gap
/// included. Arabic month names are wider than English abbreviations, and
/// a fixed four labels printed two of them on top of each other on a phone.
const double _dateLabelSlot = 88;

/// How many axis dates fit across [available] width: the first, the last,
/// and up to two between them.
int _dateLabelsThatFit(double available) =>
    available.isFinite ? (available ~/ _dateLabelSlot).clamp(2, 4) : 4;

/// Tick spacing in days for a time axis covering [span] days that shows
/// [labels] evenly spaced dates, the first and the last included.
double _dayLabelInterval(double span, int labels) {
  if (span <= 0) return 1;
  return span / (labels - 1);
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
  String Function(double value) label,
) {
  if (value == meta.min || value == meta.max) {
    return const SizedBox.shrink();
  }
  return Text(label(value), style: AppTypography.eyebrow(Theme.of(context)));
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

        final (:double totalKg, :int activeWeeks) =
            summarizeWeeklyVolume(points);

        return _ChartCard(
          headline: UnitFormatters.volume(totalKg, unit, context.l10n),
          caption: context.l10n.progressVolumeActiveWeeks(
            activeWeeks,
            points.length,
          ),
          child: _WeeklyBarChart(
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

/// What the effort chart plots.
enum _EffortMetric { rpe, rest }

/// How hard the sessions were, and how long the rests: one chart with a
/// switch, an average for the range as its headline.
///
/// These were two tables of dates. Each listed the first eight sessions of
/// the range, oldest first, so a three-month view showed the sessions from
/// three months ago and none since.
class _EffortSection extends ConsumerStatefulWidget {
  const _EffortSection({required this.range});
  final ProgressRange range;

  @override
  ConsumerState<_EffortSection> createState() => _EffortSectionState();
}

class _EffortSectionState extends ConsumerState<_EffortSection> {
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
      _ChartCard(
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
          loading: () =>
              _ChartCard(header: header, child: const _PlotLoading()),
          error: (e, _) => _ChartError(
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
            return _ChartCard(
              header: header,
              headline: l10n.progressAverageRpe(average.toStringAsFixed(1)),
              caption: l10n.sessionCount(sessions.length),
              child: _DatedLineChart(
                ordered: <_DatedPoint>[
                  for (final SessionRpe s in sessions)
                    _DatedPoint(
                      date: s.date,
                      value: s.averageRpe,
                      // Effort next to the load it was spent on: a hard
                      // session with little volume reads differently.
                      tooltip: l10n.progressSessionRpeValue(
                        s.averageRpe.toStringAsFixed(1),
                        UnitFormatters.volume(s.volumeKg, unit, l10n),
                      ),
                    ),
                ],
                axisLabel: _plainTick,
              ),
            );
          },
        );
  }

  Widget _rest(BuildContext context, Widget header) {
    final ProgressRange range = widget.range;
    final AppLocalizations l10n = context.l10n;
    return ref.watch(restAnalyticsProvider(range)).when(
          loading: () =>
              _ChartCard(header: header, child: const _PlotLoading()),
          error: (e, _) => _ChartError(
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
            return _ChartCard(
              header: header,
              headline: l10n.progressAverageRestSeconds(averageSeconds.round()),
              // How many rests the average stands on, as text: in the
              // chart it is only in a tooltip, which a screen reader
              // cannot reach.
              caption: <String>[
                l10n.sessionCount(sessions.length),
                l10n.progressRestFromSets(sets),
              ].join(' · '),
              child: _DatedLineChart(
                ordered: <_DatedPoint>[
                  for (final SessionRest s in sessions)
                    _DatedPoint(
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
                axisLabel: _plainTick,
              ),
            );
          },
        );
  }
}

/// A unitless axis tick: whole numbers plain, anything else to one decimal.
String _plainTick(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

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

        return _ChartCard(
          headline: context.l10n.progressAveragePerWeek(
            average?.toStringAsFixed(1) ?? '—',
          ),
          caption: context.l10n.progressFrequencySummary(
            total,
            points.length,
            activeWeeks,
          ),
          child: _WeeklyBarChart(
            axisLabel: _plainTick,
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
    required this.axisLabel,
    this.displayScale = 1,
    this.wholeNumbers = false,
    this.height = _chartHeight,
    this.color,
  });

  final List<DateTime> weekStarts;
  final List<double> values;
  final double height;

  /// Formats a value-axis tick, without a unit. The bars used to have
  /// gridlines and no values, so a bar's height could only be read by
  /// touching it.
  final String Function(double value) axisLabel;

  /// As [_DatedLineChart.displayScale].
  final double displayScale;

  /// Steps of whole numbers only, for counts such as workouts.
  final bool wholeNumbers;

  /// Bar colour; the brand colour unless the chart belongs to one series
  /// that already has a colour on the card (a muscle group).
  final Color? color;

  /// Formatted headline line of the tooltip for the bar at an index.
  final String Function(int index) tooltipValue;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color barColor = color ?? scheme.primary;

    return SizedBox(
      height: height,
      // Bar width has to follow the bucket count now that untrained weeks
      // are included: a fixed 22dp rod was already tight, and an all-time
      // range can run to hundreds of weeks, where fixed-width rods overlap
      // into a solid block.
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // The value axis takes its width from the plot.
          final double plotWidth = constraints.maxWidth - _valueAxisReserved;
          final double width = _barWidthFor(plotWidth, weekStarts.length);
          final int labelStep = _labelInterval(
            weekStarts.length,
            maxLabels: _weekLabelsThatFit(plotWidth),
          ).round();
          final double highest = values.fold<double>(
            0,
            (double max, double v) => v > max ? v : max,
          );
          final double valueStep = niceAxisStep(
                highest * displayScale,
                wholeNumbers: wholeNumbers,
              ) /
              displayScale;
          return BarChart(
            BarChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: valueStep,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: scheme.outlineVariant,
                  strokeWidth: 1,
                  dashArray: _gridDash,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: _valueAxisReserved,
                    interval: valueStep,
                    getTitlesWidget: (double value, TitleMeta meta) =>
                        _valueAxisTick(context, value, meta, axisLabel),
                  ),
                ),
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
                            ? barColor
                            : barColor.withValues(alpha: 0.45),
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
///
/// Tapping a group shows its week-by-week volume under the list. That was
/// a separate table of muscle, week and kilograms, which printed the first
/// twelve rows of the range (its oldest two weeks) and nothing newer.
class _MuscleGroupSection extends ConsumerStatefulWidget {
  const _MuscleGroupSection({required this.range});

  final ProgressRange range;

  @override
  ConsumerState<_MuscleGroupSection> createState() =>
      _MuscleGroupSectionState();
}

class _MuscleGroupSectionState extends ConsumerState<_MuscleGroupSection> {
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
      loading: () => const _ChartLoading(),
      error: (error, _) => _ChartError(
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
          return _ChartEmpty(
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

        return _ChartCard(
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
/// selected in [_MuscleGroupSection].
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
            height: _detailChartHeight,
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
                _WeeklyBarChart(
                  axisLabel: (double kg) => UnitFormatters.volume(
                    kg,
                    unit,
                    context.l10n,
                    withUnit: false,
                  ),
                  displayScale: unit.perKilogram,
                  height: _detailChartHeight,
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
                      displayScale: unit.perKilogram,
                      // Stored newest-first; charts read left to right.
                      ordered: <_DatedPoint>[
                        for (final BodyMetrics e in entries.reversed)
                          _DatedPoint(
                            date: e.date,
                            value: e.weightKg,
                            tooltip: UnitFormatters.weight(
                              e.weightKg,
                              unit,
                              context.l10n,
                            ),
                          ),
                      ],
                      axisLabel: (double kg) => UnitFormatters.weight(
                        kg,
                        unit,
                        context.l10n,
                        withUnit: false,
                      ),
                    )
                  : const SizedBox.shrink(),
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
