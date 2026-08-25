import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../l10n/l10n_extension.dart';
import '../theme/app_spacing.dart';

/// Failure state with a retry affordance.
///
/// [details] is shown only in debug builds — a stack trace is noise to a
/// user and a support burden to you.
class ErrorView extends StatelessWidget {
  const ErrorView({
    this.title,
    this.details,
    this.onRetry,
    this.compact = false,
    super.key,
  });

  /// Defaults to the generic failure message. Null rather than a literal
  /// default because the fallback is localized, and a parameter default has
  /// to be `const` — there is no `context` to resolve it against yet.
  final String? title;
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
          title ?? context.l10n.commonError,
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
            TextButton(
              onPressed: onRetry,
              child: Text(context.l10n.actionRetry),
            )
          else
            FilledButton.tonal(
              onPressed: onRetry,
              child: Text(context.l10n.errorTryAgain),
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
