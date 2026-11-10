/// The Strength chapter: strength change, relative strength and the
/// lift chart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/daos/workout_dao.dart';
import '../../../../core/database/database_providers.dart';
import '../../../../core/formatters/unit_formatters.dart';
import '../../../../core/formatters/weight_unit_controller.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/metric_explainer.dart';
import '../../../../core/widgets/segmented_pills.dart';
import '../../../../core/widgets/trend_badge.dart';
import '../../../../core/widgets/value_row.dart';
import '../../../library/domain/exercise_catalogue_l10n.dart';
import '../../domain/progress_providers.dart';
import '../../domain/strength_analytics.dart';
import '../progress_explainers.dart';
import '../widgets/lift_picker.dart';
import '../widgets/progress_charts.dart';

/// Per-lift strength comparison: the question "am I improving" answered
/// directly, rather than inferred from a volume figure.
///
/// Shows the first [_strengthPreview] lifts and folds the rest behind a
/// toggle: someone training fifteen exercises had a three-screen list here,
/// which pushed every other chapter out of reach.
class StrengthChangeSection extends ConsumerStatefulWidget {
  const StrengthChangeSection({super.key, required this.range});

  final ProgressRange range;

  @override
  ConsumerState<StrengthChangeSection> createState() =>
      _StrengthChangeSectionState();
}

const int _strengthPreview = 5;

class _StrengthChangeSectionState extends ConsumerState<StrengthChangeSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ProgressRange range = widget.range;
    final AsyncValue<List<StrengthChange>> async =
        ref.watch(strengthChangeProvider(range));
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final Map<String, String> slugsById = ref.watch(exerciseSlugsByIdProvider);

    return async.when(
      loading: () => const ProgressChartLoading(),
      error: (error, _) => ProgressChartError(
        error: error,
        onRetry: () => ref.invalidate(strengthChangeProvider(range)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return ProgressChartEmpty(
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

class RelativeStrengthSection extends ConsumerWidget {
  const RelativeStrengthSection({super.key, required this.range});
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
            child: ProgressChartError(
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
                              UnitFormatters.ratio(row.ratio),
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
                          : (row.comparedWithFirstSession
                              ? l10n.progressStrengthFirstSession
                              : l10n.progressStrengthPreviousBest)(
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
class LiftChartSection extends ConsumerStatefulWidget {
  const LiftChartSection({super.key, required this.range});

  final ProgressRange range;

  @override
  ConsumerState<LiftChartSection> createState() => _LiftChartSectionState();
}

class _LiftChartSectionState extends ConsumerState<LiftChartSection> {
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
      loading: () => const ProgressChartLoading(),
      error: (error, _) => ProgressChartError(
        error: error,
        onRetry: () => ref.invalidate(loggedExercisesProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return ProgressChartEmpty(
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

        final LoggedExercise chosen = items.firstWhere(
          (LoggedExercise i) => i.exerciseId == selected,
        );
        String nameOf(LoggedExercise item) => localizedExerciseName(
              context,
              slugsById,
              item.exerciseId,
              item.exerciseName,
            );
        final Widget header = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            LiftPickerField(
              selectedId: selected,
              label: l10n.progressExerciseWithSessions(
                nameOf(chosen),
                l10n.sessionCount(chosen.sessionCount),
              ),
              onTap: () async {
                final String? id = await showLiftPicker(
                  context,
                  selectedId: selected,
                  options: <LiftOption>[
                    for (final LoggedExercise item in items)
                      LiftOption(
                        id: item.exerciseId,
                        name: nameOf(item),
                        storedName: item.exerciseName,
                        sessions: l10n.sessionCount(item.sessionCount),
                      ),
                  ],
                );
                if (id != null && mounted) setState(() => _exerciseId = id);
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

  Widget _rangeEmpty(BuildContext context, Widget header) => ProgressChartCard(
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
          loading: () => ProgressChartCard(
              header: header, child: const ProgressPlotLoading()),
          error: (error, _) => ProgressChartError(
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

            return ProgressChartCard(
              header: header,
              headline: UnitFormatters.estimate(current, unit, l10n),
              caption: ordered.length == 1
                  ? l10n.progressOneDataPoint
                  : trendCaption,
              trend: ordered.length == 1 ? null : trendBetween(first, current),
              child: DatedLineChart(
                displayScale: unit.perKilogram,
                ordered: <DatedPoint>[
                  for (final OneRMSeriesPoint p in ordered)
                    DatedPoint(
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
          loading: () => ProgressChartCard(
              header: header, child: const ProgressPlotLoading()),
          error: (error, _) => ProgressChartError(
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
            return ProgressChartCard(
              header: header,
              headline: UnitFormatters.volume(latest, unit, l10n),
              caption: sessions.length == 1
                  ? l10n.progressOneDataPoint
                  : l10n.progressSessionVolumeSubtitle,
              trend: sessions.length == 1 ? null : trendBetween(first, latest),
              child: DatedLineChart(
                displayScale: unit.perKilogram,
                ordered: <DatedPoint>[
                  for (final SessionVolumeLoad session in sessions)
                    DatedPoint(
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
