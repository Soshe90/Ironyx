import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Minimum width for a content-sized button sitting next to Row siblings.
const double _pillMinWidth = 72;

/// One labelled row of the Personal Details form: icon, label, and a tappable
/// pill showing the current value.
class ValuePillRow extends StatelessWidget {
  const ValuePillRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;

  /// Rendered inside the pill. Callers pass a placeholder such as "Set" when
  /// the value is still empty.
  final String value;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Semantics(
      button: true,
      label: '$label, $value',
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.tonal(
                // `AppTheme`'s filledButtonTheme sets an *infinite*-width
                // minimum, which is correct for full-width CTAs and fatal
                // for a content-sized button in a Row: the Row already
                // hands down an unbounded max-width, and the two infinities
                // combine into a hard layout crash. Same override, and the
                // same reason, as the Start button on the program detail
                // page.
                style: FilledButton.styleFrom(
                  minimumSize: const Size(
                    _pillMinWidth,
                    AppSpacing.minTapTarget,
                  ),
                ),
                onPressed: onPressed,
                child: Text(value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
