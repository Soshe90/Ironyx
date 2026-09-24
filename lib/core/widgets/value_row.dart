import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// One "label … value" line inside a card: a date and its volume, an
/// exercise and its ratio, a muscle and its sets.
///
/// The single style for these rows. Before it, each list on the Progress
/// page borrowed a dense `ListTile`, whose own 16dp inset misaligned the
/// rows with their card's heading and whose unstyled trailing text shrank
/// the value — the thing being read — below the label.
class ValueRow extends StatelessWidget {
  const ValueRow({
    required this.label,
    required this.value,
    this.caption,
    super.key,
  });

  final String label;

  /// Already formatted for display.
  final String value;

  /// Optional second line under [label], e.g. a sample size or a date.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(label, style: theme.textTheme.bodyMedium),
                  if (caption != null)
                    Text(caption!, style: AppTypography.caption(theme)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Flexible(
              flex: 2,
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: AppTypography.numeric(
                  theme.textTheme.titleSmall!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
