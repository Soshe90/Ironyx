import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'metric_value.dart';

/// One cell in a [StatStrip].
class Stat {
  const Stat({required this.label, required this.value, this.emphasis = false});

  final String label;

  /// Already formatted. Callers pass '—' for a genuinely absent value.
  final String value;

  /// Renders this cell at the next step up the metric ramp. At most one
  /// cell per strip should set it — that is the point of the strip.
  final bool emphasis;
}

/// A row of small stats separated by hairline rules.
///
/// Used for the "volume / sets / duration" summaries that appear on the
/// workout detail, tracker and active-workout screens. Wraps to a second
/// line rather than shrinking text below legibility on narrow phones.
class StatStrip extends StatelessWidget {
  const StatStrip({required this.stats, super.key});

  final List<Stat> stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < stats.length; i++) ...<Widget>[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                ),
                child: VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: scheme.outlineVariant,
                ),
              ),
            Expanded(
              child: Semantics(
                label: '${stats[i].label}, ${stats[i].value}',
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        stats[i].label.toUpperCase(),
                        style: AppTypography.eyebrow(theme),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      MetricValue(
                        stats[i].value,
                        style: AppTypography.cardMetric(
                          scheme,
                          size: stats[i].emphasis
                              ? AppTypography.metricSizeMd
                              : AppTypography.metricSizeSm,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
