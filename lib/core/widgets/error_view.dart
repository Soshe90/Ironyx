import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Failure state with a retry affordance.
///
/// [details] is shown only in debug builds — a stack trace is noise to a
/// user and a support burden to you.
class ErrorView extends StatelessWidget {
  const ErrorView({
    this.title = 'Something went wrong',
    this.details,
    this.onRetry,
    this.compact = false,
    super.key,
  });

  final String title;
  final String? details;
  final VoidCallback? onRetry;

  /// Dense variant for use inside a dashboard card, where a full-height
  /// error would blow out the grid.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool showDetails = kDebugMode && details != null;

    final Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: <Widget>[
        Icon(
          Icons.error_outline,
          size: compact ? 20 : 40,
          color: theme.colorScheme.error,
        ),
        SizedBox(height: compact ? AppSpacing.sm : AppSpacing.lg),
        Text(
          title,
          style:
              compact ? theme.textTheme.bodySmall : theme.textTheme.titleMedium,
          textAlign: compact ? TextAlign.start : TextAlign.center,
        ),
        if (showDetails) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            details!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: compact ? TextAlign.start : TextAlign.center,
          ),
        ],
        if (onRetry != null) ...<Widget>[
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.xl),
          if (compact)
            TextButton(onPressed: onRetry, child: const Text('Retry'))
          else
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
        ],
      ],
    );

    if (compact) {
      return body;
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: body,
      ),
    );
  }
}
