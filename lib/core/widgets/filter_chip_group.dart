import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A labelled row of single-select filter chips, plus an "All" chip that
/// clears the filter. Shared by the Library page and the exercise picker
/// sheet so both filter identically. Works for plain enums (movement
/// pattern) and value-equal data classes alike (muscle/equipment) — it
/// only needs `==` and a label function, not `Enum` specifically.
class FilterChipGroup<T extends Object> extends StatelessWidget {
  const FilterChipGroup({
    required this.label,
    required this.value,
    required this.options,
    required this.getLabel,
    required this.onChanged,
    super.key,
  });

  final String label;
  final T? value;
  final List<T> options;
  final String Function(T) getLabel;
  final void Function(T?) onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            FilterChip(
              label: const Text('All'),
              selected: value == null,
              onSelected: (_) => onChanged(null),
              showCheckmark: false,
            ),
            for (final option in options)
              FilterChip(
                label: Text(getLabel(option)),
                selected: value == option,
                onSelected: (_) => onChanged(option),
                showCheckmark: false,
              ),
          ],
        ),
      ],
    );
  }
}
