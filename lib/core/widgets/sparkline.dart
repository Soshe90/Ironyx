import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// A minimal, axis-free trend line for embedding in a card — not a full
/// chart. Use `progress/presentation`'s `LineChart` usages directly when
/// axes, tooltips, or touch interaction are actually needed.
class Sparkline extends StatelessWidget {
  const Sparkline({
    required this.values,
    this.color,
    this.height = 36,
    super.key,
  });

  final List<double> values;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(height: height);
    }

    final Color lineColor = color ?? Theme.of(context).colorScheme.primary;
    double lo = values.first;
    double hi = values.first;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    // Flat series (or a single repeated value) would otherwise collapse
    // minY == maxY, which fl_chart can't lay out.
    if (lo == hi) {
      lo -= 1;
      hi += 1;
    }
    final double pad = (hi - lo) * 0.1;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: lo - pad,
          maxY: hi + pad,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: <LineChartBarData>[
            LineChartBarData(
              spots: <FlSpot>[
                for (var i = 0; i < values.length; i++)
                  FlSpot(i.toDouble(), values[i]),
              ],
              isCurved: true,
              color: lineColor,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: lineColor.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
