import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Marks a workout that set a new estimated-1RM personal record.
///
/// Uses the dedicated [AppColors.personalRecord] accent rather than the
/// scheme's tertiary container, so a PR reads the same everywhere it
/// appears and never collides with the primary action colour.
class PrBadge extends StatelessWidget {
  const PrBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.personalRecord.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.military_tech,
            size: 12,
            color: AppColors.personalRecord,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            'PR',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.personalRecord,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
