import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../../core/widgets/trend_badge.dart';

/// One dashboard tile.
///
/// M1 renders placeholder content. M6 swaps [metric] and [caption] for live
/// values from stream providers — the widget contract does not change.
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool compact = constraints.maxWidth < 180;
        return AppCard(
          onTap: onTap,
          padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
          semanticLabel: _semanticLabel(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
              _body(context, compact: compact),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, {bool compact = false}) {
    if (error != null) {
      return ErrorView(
        title: 'Could not load',
        details: error.toString(),
        compact: true,
      );
    }
    if (isLoading) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LoadingShimmer(width: 120, height: 28),
          SizedBox(height: AppSpacing.sm),
          LoadingShimmer(width: 80, height: 12),
        ],
      );
    }

    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              metric ?? '—',
              style: AppTypography.cardMetric(theme.colorScheme).copyWith(
                fontSize: compact ? 20 : 24,
              ),
            ),
            if (trend != null) ...<Widget>[
              const SizedBox(width: AppSpacing.xs),
              TrendBadge(direction: trend!),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          caption ?? 'No data yet',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
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
