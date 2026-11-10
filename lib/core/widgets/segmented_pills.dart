import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// One choice in a [SegmentedPills].
class PillSegment<T> {
  const PillSegment({required this.value, required this.label});

  final T value;

  /// Already localized.
  final String label;
}

/// A single-select control: a quiet filled track with the chosen segment
/// tinted in the brand colour, the same "selected" look as the navigation
/// bar's indicator.
///
/// Use it to switch what one view shows (a date range, which metric a chart
/// plots). It is not navigation and not a filter: `FilterChipGroup` filters
/// a list, and a tab bar changes the page.
///
/// Segments share the width equally and a long label scales down rather
/// than wrapping, so keep labels to a word or two. Every segment is a full
/// 48 dp tap target even though the track is drawn slimmer.
class SegmentedPills<T> extends StatelessWidget {
  const SegmentedPills({
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });

  final List<PillSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Names the group for a screen reader ("Date range").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: SizedBox(
        height: AppSpacing.minTapTarget,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
            ),
            Row(
              children: <Widget>[
                for (final PillSegment<T> segment in segments)
                  Expanded(
                    child: _Pill(
                      label: segment.label,
                      selected: segment.value == selected,
                      onTap: () => onChanged(segment.value),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: label,
      // The ink well below is excluded from semantics along with its text,
      // so the action is restated here for a screen reader.
      onTap: selected ? null : onTap,
      child: ExcludeSemantics(
        child: InkWell(
          // Choosing the chosen segment again is a no-op, so it is not
          // offered as an action.
          onTap: selected ? null : onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm,
            ),
            child: AnimatedContainer(
              duration: AppDuration.fast,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.16)
                    : scheme.primary.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
