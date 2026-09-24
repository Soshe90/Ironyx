import 'package:flutter/material.dart';

import '../l10n/l10n_extension.dart';
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
    final Color ink = theme.brightness == Brightness.light
        ? AppColors.personalRecordInkLight
        : AppColors.personalRecord;

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
          Icon(Icons.military_tech, size: 12, color: ink),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            context.l10n.prBadge,
            style: theme.textTheme.labelSmall?.copyWith(
              color: ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
