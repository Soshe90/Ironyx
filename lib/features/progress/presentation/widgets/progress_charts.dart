/// The chart frame and plots shared by the Progress sections: the card
/// with its headline, its loading, empty and error states, the dated line
/// chart and the weekly bar chart, and the axis rules they share.
///
/// Split out of `progress_page.dart`, where all of this sat with the page
/// and every section in one 2,600-line file.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/formatters/date_formatters.dart';
import '../../../../core/formatters/unit_formatters.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/chart_gestures.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../../core/widgets/trend_badge.dart';
import 'chart_axis.dart';

/// Height of a full chart. One value for all of them, so the page has a
/// consistent rhythm instead of three hand-picked heights.
const double progressChartHeight = 220;

/// Height of a chart that sits inside another card as detail (one muscle
/// group's weeks), where a full-height plot would bury the list above it.
const double progressDetailChartHeight = 140;

const double _axisReserved = 28;

/// Width of the shimmer standing in for a card's headline figure.
const double _headlineShimmerWidth = 160;

/// Stroke of a line chart's line.
const double _lineWidth = 3;

/// A line chart's point, and a personal record's larger point with the
/// ring that lifts it off the line.
const double _dotRadius = 3;
const double _recordDotRadius = 5;
const double _recordDotRing = 2;

/// Width kept for value-axis labels ("1,250", "242.5").
const double _valueAxisReserved = _axisReserved + AppSpacing.lg;
const double _barWidth = 22;

/// Dash pattern for chart gridlines: present enough to read values against,
/// quiet enough not to compete with the data.
const List<int> _gridDash = <int>[4, 4];

/// Shared frame for a chart block: headline value, optional trend, then the
/// plot. Keeps the four sections visually identical rather than each one
/// inventing its own header.
class ProgressChartCard extends StatelessWidget {
  const ProgressChartCard({
    super.key,
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
class ProgressChartLoading extends StatelessWidget {
  const ProgressChartLoading({super.key});

  @override
  Widget build(BuildContext context) =>
      const AppCard(child: ProgressPlotLoading());
}

/// The plot area of a card whose header (a picker, a metric switch) is
/// already known: the header stays put and only the chart shimmers.
class ProgressPlotLoading extends StatelessWidget {
  const ProgressPlotLoading({super.key});

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LoadingShimmer(
            width: _headlineShimmerWidth,
            height: AppTypography.metricSizeLg,
          ),
          SizedBox(height: AppSpacing.lg),
          LoadingShimmer(height: progressChartHeight, radius: AppRadius.md),
        ],
      );
}

class ProgressChartEmpty extends StatelessWidget {
  const ProgressChartEmpty(
      {super.key, required this.icon, required this.message});

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

class ProgressChartError extends StatelessWidget {
  const ProgressChartError(
      {super.key, required this.error, required this.onRetry});

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

TrendDirection trendBetween(double first, double last) => last > first
    ? TrendDirection.up
    : last < first
        ? TrendDirection.down
        : TrendDirection.flat;

/// One dated value — the shape every line chart on the page plots.
class DatedPoint {
  const DatedPoint({
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
class DatedLineChart extends StatelessWidget {
  const DatedLineChart({
    super.key,
    required this.ordered,
    required this.axisLabel,
    this.displayScale = 1,
  });

  /// Oldest first.
  final List<DatedPoint> ordered;

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
    DatedPoint lowest = ordered.first;
    DatedPoint highest = ordered.first;
    for (final DatedPoint p in ordered) {
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
          height: progressChartHeight,
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
                    for (final DatedPoint p in ordered)
                      FlSpot(degenerate ? 0 : xOf(p.date), p.value),
                  ],
                  isCurved: true,
                  // Without this the smoothing swings past the points it joins:
                  // the line dipped under a lift's lowest logged estimate, a
                  // value no session ever had.
                  preventCurveOverShooting: true,
                  color: scheme.primary,
                  barWidth: _lineWidth,
                  dotData: FlDotData(
                    show: ordered.length <= _dotThreshold,
                    getDotPainter: (spot, percent, bar, index) =>
                        FlDotCirclePainter(
                      radius: ordered[index].isPersonalRecord
                          ? _recordDotRadius
                          : _dotRadius,
                      // Records are amber everywhere else (PrBadge); a ring in
                      // the card colour separates the dot from the line.
                      color: ordered[index].isPersonalRecord
                          ? AppColors.personalRecord
                          : scheme.primary,
                      strokeWidth:
                          ordered[index].isPersonalRecord ? _recordDotRing : 0,
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

/// A unitless axis tick: whole numbers plain, anything else to one decimal.
String plainAxisTick(double value) => value == value.roundToDouble()
    ? UnitFormatters.plain(value)
    : UnitFormatters.oneDecimal(value);

/// Bar chart over consecutive weekly buckets.
///
/// Shared by weekly volume and weekly frequency: both plot one bar per week
/// of the selected range against the same zero-filled x axis, and having
/// them diverge in bar width or label spacing made two views of the same
/// weeks look like two unrelated charts.
class WeeklyBarChart extends StatelessWidget {
  const WeeklyBarChart({
    super.key,
    required this.weekStarts,
    required this.values,
    required this.tooltipValue,
    required this.axisLabel,
    this.displayScale = 1,
    this.wholeNumbers = false,
    this.height = progressChartHeight,
    this.color,
  });

  final List<DateTime> weekStarts;
  final List<double> values;
  final double height;

  /// Formats a value-axis tick, without a unit. The bars used to have
  /// gridlines and no values, so a bar's height could only be read by
  /// touching it.
  final String Function(double value) axisLabel;

  /// As [DatedLineChart.displayScale].
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
              // All zero (a range with nothing in it after a break): one
              // step of headroom, or the axis would span nothing.
              maxY: highest > 0 ? null : valueStep,
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
