import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Direction of a trend, independent of any particular domain enum (e.g.
/// `OneRMTrend`) — callers map their own domain trend into this at the
/// presentation boundary, so `core/widgets` never depends on a feature.
enum TrendDirection { up, down, flat }

/// Small colored pill with a direction arrow and an optional label, for
/// showing "up/down/flat vs. last period" next to a headline metric.
class TrendBadge extends StatelessWidget {
  const TrendBadge({required this.direction, this.label, super.key});

  final TrendDirection direction;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final (Color color, IconData icon) = switch (direction) {
      TrendDirection.up => (AppColors.gain, Icons.arrow_upward_rounded),
      TrendDirection.down => (AppColors.loss, Icons.arrow_downward_rounded),
      TrendDirection.flat => (scheme.onSurfaceVariant, Icons.remove_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: color),
          if (label != null) ...<Widget>[
            const SizedBox(width: AppSpacing.xxs),
            Text(
              label!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
