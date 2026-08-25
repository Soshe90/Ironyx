import 'package:flutter/material.dart';

import '../l10n/l10n_extension.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'error_view.dart';
import 'loading_shimmer.dart';
import 'trend_badge.dart';

/// Eyebrow label, big tabular number, caption, optional trend — the shape
/// every fitness metric in this app takes.
///
/// Deliberately *not* a card. The dashboard wraps it in [AppCard], but the
/// tracker summary bar and workout detail header render it directly on the
/// surface, which is what keeps those screens from nesting cards purely to
/// display a number.
class MetricBlock extends StatelessWidget {
  const MetricBlock({
    required this.label,
    this.value,
    this.caption,
    this.trend,
    this.icon,
    this.size = AppTypography.metricSizeMd,
    this.isLoading = false,
    this.error,
    this.emptyCaption,
    super.key,
  });

  final String label;

  /// Already formatted for display. Null renders the em-dash placeholder,
  /// which is what "no data" looks like — not a zero, which would read as
  /// a real measurement.
  final String? value;
  final String? caption;
  final TrendDirection? trend;
  final IconData? icon;

  /// A step off [AppTypography]'s metric ramp.
  final double size;

  final bool isLoading;
  final Object? error;

  /// Defaults to the generic "no data yet" caption; see [ErrorView.title] for
  /// why this is nullable rather than a literal default.
  final String? emptyCaption;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    if (error != null) {
      return ErrorView(
        title: context.l10n.metricCouldNotLoad,
        details: error.toString(),
        compact: true,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.xs),
            ],
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: AppTypography.eyebrow(theme),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (isLoading)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LoadingShimmer(width: 120, height: size),
              const SizedBox(height: AppSpacing.sm),
              const LoadingShimmer(width: 80, height: 12),
            ],
          )
        else ...<Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: Text(
                  value ?? '—',
                  style: AppTypography.cardMetric(scheme, size: size),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trend != null) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                TrendBadge(direction: trend!),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            caption ?? emptyCaption ?? context.l10n.metricNoDataYet,
            style: AppTypography.caption(theme),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
