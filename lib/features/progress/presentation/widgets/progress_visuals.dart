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
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../../core/widgets/metric_value.dart';
import '../../domain/progress_providers.dart';

/// Presentational building blocks for the Progress page.
///
/// They live here rather than in `progress_page.dart` so the page reads as
/// a list of sections, and rather than in `core/widgets` because each one
/// encodes a Progress-specific idea (a reference band, a share of volume).
/// Everything below is drawn with plain widgets, not `fl_chart`, so every
/// value is real text a screen reader and a widget test can reach.

/// Height of the hero's weekly strip.
const double _heroStripHeight = 40;

/// Thickness of a share bar's track and of the proportion bar.
const double _barThickness = 8;

/// Height of the training-days plot area, above the weekday labels.
const double _weekdayPlotHeight = 88;

/// Diameter of the marker on a [RatioGauge].
const double _gaugeMarker = 14;

/// Labels a group of sections, so a twelve-section page reads as four
/// chapters instead of one undifferentiated stack.
class ProgressChapter extends StatelessWidget {
  const ProgressChapter({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.xxl,
          bottom: AppSpacing.lg,
        ),
        child: Row(
          children: <Widget>[
            // A short bar in the brand colour, then the name at heading
            // size. The old small-capitals eyebrow was the quietest text on
            // the page while marking its biggest division.
            Container(
              width: AppSpacing.xs,
              height: AppSpacing.xl,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(title, style: theme.textTheme.headlineSmall),
            ),
          ],
        ),
      ),
    );
  }
}

/// The chapters of the Progress page as a row of tabs: tapping one asks the
/// page to scroll there, and [active] follows the reader's position.
///
/// Not a `TabBar`: the chapters are one scrolling page, not separate views,
/// and no tab is selected above the first chapter. The cells share the
/// width, so the row never scrolls sideways.
class ProgressChapterTabs<T> extends StatelessWidget {
  const ProgressChapterTabs({
    required this.chapters,
    required this.active,
    required this.onSelected,
    super.key,
  });

  /// Value and already-localized label, in page order.
  final List<(T, String)> chapters;

  /// The chapter being read, or null above the first one.
  final T? active;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return SizedBox(
      height: AppSpacing.minTapTarget,
      child: Row(
        children: <Widget>[
          for (final (T value, String label) in chapters)
            Expanded(
              child: Semantics(
                button: true,
                selected: value == active,
                label: label,
                onTap: () => onSelected(value),
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: () => onSelected(value),
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                            ),
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: value == active
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                    fontWeight: value == active
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        AnimatedContainer(
                          duration: AppDuration.fast,
                          height: AppSpacing.xxs,
                          margin: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          decoration: BoxDecoration(
                            color: value == active
                                ? scheme.primary
                                : scheme.primary.withValues(alpha: 0),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The answer to "how am I doing over this window?" before any chart:
/// total volume, a strip of the weeks behind it, then workouts, weekly
/// average and records.
///
/// Reads the same providers the sections below already watch, so it adds
/// no query. A failed or loading provider shows the em-dash rather than an
/// error here; the section that owns that data reports the failure once.
class ProgressOverviewHero extends ConsumerWidget {
  const ProgressOverviewHero({required this.range, super.key});

  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final AsyncValue<List<WeeklyVolume>> volume =
        ref.watch(weeklyVolumeSeriesProvider(range));
    final AsyncValue<List<WorkoutFrequency>> frequency =
        ref.watch(workoutFrequencySeriesProvider(range));
    final AsyncValue<int> records =
        ref.watch(recentPersonalRecordsProvider(range));

    final List<WeeklyVolume>? weeks = volume.value;
    final List<WorkoutFrequency>? sessions = frequency.value;

    final String? totalVolume = weeks == null
        ? null
        : UnitFormatters.volume(
            weeks.fold<double>(0, (double sum, w) => sum + w.totalVolumeKg),
            unit,
            l10n,
          );
    final int? workoutTotal = sessions?.fold<int>(
      0,
      (int sum, WorkoutFrequency f) => sum + f.workoutCount,
    );
    // Per elapsed week, matching the frequency card's own headline.
    final String? perWeek = workoutTotal == null || sessions!.isEmpty
        ? null
        : (workoutTotal / sessions.length).toStringAsFixed(1);

    final bool loading = volume.isLoading && weeks == null;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      gradient: const LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: <Color>[AppColors.workoutHero, AppColors.workoutHeroEnd],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.progressOverviewRange(range.name).toUpperCase(),
                  style: AppTypography.eyebrow(
                    theme,
                    color: AppColors.workoutHeroAccent,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.workoutHeroAccent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  size: 20,
                  color: AppColors.workoutHeroAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            label: l10n.progressMetricSemantic(
              l10n.progressOverviewTotalVolume,
              totalVolume ?? '—',
            ),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (loading)
                    const LoadingShimmer(
                      width: 180,
                      height: AppTypography.metricSizeXl,
                    )
                  else
                    MetricValue(
                      totalVolume ?? '—',
                      style: AppTypography.cardMetric(
                        theme.colorScheme,
                        size: AppTypography.metricSizeXl,
                      ).copyWith(color: AppColors.workoutHeroForeground),
                    ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.progressOverviewTotalVolume,
                    style: AppTypography.caption(theme).copyWith(
                      color: AppColors.workoutHeroCaption,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (weeks != null && weeks.length >= 2) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            _WeekStrip(
              values: <double>[
                for (final WeeklyVolume w in weeks) w.totalVolumeKg,
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Divider(
            height: 1,
            thickness: 1,
            color: AppColors.workoutHeroForeground.withValues(alpha: 0.12),
          ),
          const SizedBox(height: AppSpacing.lg),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _HeroStat(
                  label: l10n.progressOverviewWorkouts,
                  value: workoutTotal?.toString(),
                ),
                const _HeroRule(),
                _HeroStat(
                  label: l10n.progressOverviewPerWeek,
                  value: perWeek,
                ),
                const _HeroRule(),
                _HeroStat(
                  label: l10n.progressOverviewRecords,
                  value: records.value?.toString(),
                  accent: (records.value ?? 0) > 0,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, this.value, this.accent = false});

  final String label;
  final String? value;

  /// Draws the value in the record colour, for a figure worth celebrating.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String shown = value ?? '—';
    return Expanded(
      child: Semantics(
        label: context.l10n.progressMetricSemantic(label, shown),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              MetricValue(
                shown,
                style: AppTypography.cardMetric(
                  theme.colorScheme,
                  size: AppTypography.metricSizeMd,
                ).copyWith(
                  color: accent
                      ? AppColors.personalRecord
                      : AppColors.workoutHeroForeground,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                label.toUpperCase(),
                style: AppTypography.eyebrow(
                  theme,
                  color: AppColors.workoutHeroCaption,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroRule extends StatelessWidget {
  const _HeroRule();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: VerticalDivider(
          width: 1,
          thickness: 1,
          color: AppColors.workoutHeroForeground.withValues(alpha: 0.12),
        ),
      );
}

/// One slim bar per week, newest at the end and lit; the rest dimmed.
///
/// Decorative: the exact figures live in the Weekly volume chart, so this
/// is excluded from semantics rather than read out as a dozen numbers.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final double peak = values.fold<double>(0, (a, b) => b > a ? b : a);
    return ExcludeSemantics(
      child: SizedBox(
        height: _heroStripHeight,
        child: Row(
          // Time runs left to right in every chart on this page, Arabic
          // included (fl_chart does not mirror), so the strip matches them
          // rather than flipping under RTL.
          textDirection: TextDirection.ltr,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (int i = 0; i < values.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: FractionallySizedBox(
                  alignment: Alignment.bottomCenter,
                  // An untrained week keeps a sliver so the week still
                  // reads as a slot rather than a gap in the strip.
                  heightFactor:
                      peak <= 0 ? 0.06 : (values[i] / peak).clamp(0.06, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: i == values.length - 1
                          ? AppColors.workoutHeroAccent
                          : AppColors.workoutHeroAccent.withValues(
                              alpha: 0.32,
                            ),
                      borderRadius: BorderRadius.circular(AppSpacing.xxs),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A tinted circular icon chip, the leading mark on insights and stat
/// tiles. Colour carries the meaning; the text beside it always says it too.
class ProgressIconChip extends StatelessWidget {
  const ProgressIconChip({
    required this.icon,
    required this.color,
    super.key,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: color),
      );
}

/// Icon, number and label in a column: the consistency figures.
class ProgressStatTile extends StatelessWidget {
  const ProgressStatTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    super.key,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      label: context.l10n.progressMetricSemantic(label, value),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ProgressIconChip(icon: icon, color: color),
            const SizedBox(height: AppSpacing.md),
            MetricValue(
              value,
              style: AppTypography.cardMetric(
                theme.colorScheme,
                size: AppTypography.metricSizeMd,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              label,
              style: AppTypography.caption(theme),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// A rounded track filled to [fraction], drawn from the reading start so
/// it mirrors correctly in Arabic.
class _Track extends StatelessWidget {
  const _Track({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BorderRadius radius = BorderRadius.circular(AppRadius.pill);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: _barThickness,
        child: ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: fraction.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, borderRadius: radius),
            ),
          ),
        ),
      ),
    );
  }
}

/// One ranked line of a share breakdown: name, value, percentage and a bar
/// scaled to the largest entry (not to 100%, which would leave every bar
/// short when the volume is spread across many groups).
class ShareBarRow extends StatelessWidget {
  const ShareBarRow({
    required this.label,
    required this.value,
    required this.share,
    required this.relative,
    required this.color,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final String label;

  /// Already formatted.
  final String value;

  /// This entry's share of the total, 0–1.
  final double share;

  /// This entry relative to the largest entry, 0–1. Sets the bar length.
  final double relative;
  final Color color;

  /// Marks the row whose detail is showing elsewhere on the card.
  final bool selected;

  /// Makes the row a button that picks this entry. Null leaves it plain.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;
    final int percent = (share * 100).round();
    final BorderRadius radius = BorderRadius.circular(AppRadius.md);
    return Semantics(
      label: l10n.progressShareSemantic(label, value, percent),
      button: onTap != null,
      selected: onTap != null ? selected : null,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          // The same tint the navigation bar uses for "selected", so the
          // chosen row reads as chosen without a second accent colour.
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: AppSpacing.sm,
                        height: AppSpacing.sm,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          label,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        value,
                        style: AppTypography.numeric(
                          theme.textTheme.bodyMedium!
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(
                        width: AppSpacing.xxl + AppSpacing.sm,
                        child: Text(
                          l10n.progressShareOfTotal(percent),
                          textAlign: TextAlign.end,
                          style: AppTypography.numeric(
                            AppTypography.caption(theme),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _Track(fraction: relative, color: color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One segment of a [ProportionBar].
class ProportionSegment {
  const ProportionSegment({
    required this.label,
    required this.value,
    required this.count,
    required this.color,
  });

  final String label;

  /// Already formatted ("104 sets").
  final String value;
  final int count;
  final Color color;
}

/// A single bar split into coloured segments, with a legend underneath that
/// carries every figure as text.
class ProportionBar extends StatelessWidget {
  const ProportionBar({required this.segments, super.key});

  final List<ProportionSegment> segments;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;
    final int total = segments.fold<int>(0, (int sum, s) => sum + s.count);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: SizedBox(
              height: _barThickness + AppSpacing.xs,
              child: total == 0
                  ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
                  : Row(
                      // Childless boxes take their minimum height unless
                      // the row hands them the bar's full height.
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (final ProportionSegment s in segments)
                          if (s.count > 0)
                            Expanded(
                              flex: s.count,
                              child: ColoredBox(color: s.color),
                            ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final ProportionSegment s in segments)
          Builder(builder: (BuildContext context) {
            final int percent =
                total == 0 ? 0 : (s.count / total * 100).round();
            return Semantics(
              label: l10n.progressShareSemantic(s.label, s.value, percent),
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: AppSpacing.md,
                        height: AppSpacing.md,
                        decoration: BoxDecoration(
                          color: s.color,
                          borderRadius: BorderRadius.circular(AppSpacing.xxs),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(s.label, style: theme.textTheme.bodyMedium),
                      ),
                      Text(
                        s.value,
                        style: AppTypography.numeric(
                          theme.textTheme.bodyMedium!
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(
                        width: AppSpacing.xxl + AppSpacing.sm,
                        child: Text(
                          l10n.progressShareOfTotal(percent),
                          textAlign: TextAlign.end,
                          style: AppTypography.numeric(
                            AppTypography.caption(theme),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

/// A ratio on a fixed 0–[scaleMax] scale with the healthy band shaded and a
/// marker at the value: in or out of the band is visible at a glance, and
/// the text above it still says so for anyone who cannot see the colour.
class RatioGauge extends StatelessWidget {
  const RatioGauge({
    required this.ratio,
    required this.bandLow,
    required this.bandHigh,
    this.scaleMax = 2,
    super.key,
  });

  /// Null when there is not enough data; the track then shows the band only.
  final double? ratio;
  final double bandLow;
  final double bandHigh;
  final double scaleMax;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool light = scheme.brightness == Brightness.light;
    final double? value = ratio;
    final bool inBand = value != null && value >= bandLow && value <= bandHigh;
    final Color markerColor = inBand
        ? (light ? AppColors.gainInkLight : AppColors.gain)
        : (light ? AppColors.personalRecordInkLight : AppColors.personalRecord);

    return ExcludeSemantics(
      child: SizedBox(
        height: _gaugeMarker,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double width = constraints.maxWidth;
            double at(double v) => (v / scaleMax).clamp(0.0, 1.0) * width;
            return Stack(
              alignment: AlignmentDirectional.centerStart,
              children: <Widget>[
                Container(
                  height: _barThickness,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                PositionedDirectional(
                  start: at(bandLow),
                  width: at(bandHigh) - at(bandLow),
                  child: Container(
                    height: _barThickness,
                    decoration: BoxDecoration(
                      color: AppColors.gain.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
                if (value != null)
                  PositionedDirectional(
                    start: (at(value) - _gaugeMarker / 2)
                        .clamp(0.0, width - _gaugeMarker),
                    child: Container(
                      width: _gaugeMarker,
                      height: _gaugeMarker,
                      decoration: BoxDecoration(
                        color: markerColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: light
                              ? scheme.surfaceContainerLowest
                              : scheme.surfaceContainerLow,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One weekday column of [WeekdayBars].
class WeekdayBarData {
  const WeekdayBarData({
    required this.shortLabel,
    required this.semanticLabel,
    required this.trainingDays,
  });

  final String shortLabel;
  final String semanticLabel;
  final int trainingDays;
}

/// Seven columns scaled to the busiest weekday, with that day lit.
class WeekdayBars extends StatelessWidget {
  const WeekdayBars({required this.days, super.key});

  final List<WeekdayBarData> days;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int peak = days.fold<int>(
        0, (int a, d) => d.trainingDays > a ? d.trainingDays : a);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (final WeekdayBarData day in days)
          Expanded(
            child: Semantics(
              label: day.semanticLabel,
              child: ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (day.trainingDays > 0)
                      Text(
                        '${day.trainingDays}',
                        style: AppTypography.numeric(
                          theme.textTheme.labelSmall!.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      height: _weekdayPlotHeight,
                      child: FractionallySizedBox(
                        alignment: Alignment.bottomCenter,
                        widthFactor: 0.56,
                        heightFactor: peak == 0
                            ? 0.04
                            : (day.trainingDays / peak).clamp(0.04, 1.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: day.trainingDays == 0
                                ? scheme.surfaceContainerHighest
                                : day.trainingDays == peak
                                    ? scheme.primary
                                    : scheme.primary.withValues(alpha: 0.45),
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm / 2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      day.shortLabel,
                      style: AppTypography.eyebrow(theme),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Loading placeholder for a plain card section, sized like a short list.
class ProgressCardLoading extends StatelessWidget {
  const ProgressCardLoading({super.key});

  @override
  Widget build(BuildContext context) => const AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LoadingShimmer(width: 140, height: AppSpacing.lg),
            SizedBox(height: AppSpacing.lg),
            LoadingShimmer(height: AppSpacing.xxxl),
          ],
        ),
      );
}
