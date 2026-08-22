import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/metric_block.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../../core/widgets/trend_badge.dart';

/// One dashboard metric tile: [MetricBlock] on an [AppCard].
///
/// Each card owns its own loading and error state so that one failing query
/// degrades a single tile instead of blanking the dashboard.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    required this.title,
    required this.icon,
    required this.onTap,
    this.metric,
    this.caption,
    this.trend,
    this.isLoading = false,
    this.error,
    this.emptyCaption = 'No data yet',
    super.key,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final String? metric;
  final String? caption;

  /// Optional up/down/flat indicator shown next to the metric.
  final TrendDirection? trend;
  final bool isLoading;
  final Object? error;

  /// Shown in place of [caption] when there is no data. Phrasing it per
  /// tile ("Log a lift to see this") turns an empty tile into a prompt
  /// rather than a dead end.
  final String emptyCaption;

  @override
  Widget build(BuildContext context) {
    // Two tiles share a phone's width, so step the metric down there rather
    // than let a formatted weight ellipsize. Keyed off the breakpoint and
    // not a LayoutBuilder: callers place these in an IntrinsicHeight row to
    // equalise tile heights, and LayoutBuilder cannot report intrinsics.
    final bool compact = context.breakpoint == Breakpoint.compact;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      semanticLabel: _semanticLabel(),
      child: MetricBlock(
        label: title,
        icon: icon,
        value: metric,
        caption: caption,
        trend: trend,
        isLoading: isLoading,
        error: error,
        emptyCaption: emptyCaption,
        size: compact ? AppTypography.metricSizeSm : AppTypography.metricSizeMd,
      ),
    );
  }

  String _semanticLabel() {
    if (error != null) {
      return '$title, failed to load';
    }
    if (isLoading) {
      return '$title, loading';
    }
    return '$title, ${metric ?? 'no data'}, ${caption ?? ''}';
  }
}
