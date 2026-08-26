import 'package:flutter/material.dart';

import '../l10n/l10n_extension.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'sheet_handle.dart';

/// A plain-language explanation of one metric.
///
/// Half this app's vocabulary — 1RM, Epley, volume load, RPE — is gym jargon
/// that means nothing to someone who has not read a training textbook. Rather
/// than dumbing the metrics down or burying a glossary in Settings, every
/// jargon-named section carries an info button that opens one of these next
/// to the number it explains.
///
/// The fields are ordered the way the sheet reads: what it is, how it is
/// worked out, the same sum with real numbers, what to do with it, and what
/// not to trust it for.
class MetricExplainer {
  const MetricExplainer({
    required this.title,
    required this.summary,
    this.icon = Icons.insights_rounded,
    this.formula,
    this.example,
    this.points = const <String>[],
    this.caveat,
  });

  final String title;

  /// One or two sentences, in words a beginner would use. This is the part
  /// most people will read, so it carries the definition — the formula below
  /// is corroboration, not the explanation.
  final String summary;

  final IconData icon;

  /// The symbolic form, e.g. `1RM = weight × (1 + reps ÷ 30)`. Omit for
  /// metrics that are a description rather than a calculation.
  final String? formula;

  /// The same sum with real numbers substituted in, e.g.
  /// `80 kg × 8 reps → 101 kg`. Seeing one worked example does more than any
  /// amount of prose; supply it whenever [formula] is set.
  final String? example;

  /// "How to read it" — what a rising line means, which values are excluded,
  /// what a beginner should actually take away.
  final List<String> points;

  /// The honest limitation, shown last and muted. Every estimate in this app
  /// has one, and saying it out loud is cheaper than a support conversation.
  final String? caveat;
}

/// Opens [explainer] as a modal bottom sheet.
Future<void> showMetricExplainer(
  BuildContext context,
  MetricExplainer explainer,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    // Above the shell's navigator, not inside it. Nested, the scrim stops at
    // the bottom navigation bar and leaves it lit under a dimmed page, which
    // reads as a rendering fault rather than a deliberate layer.
    useRootNavigator: true,
    builder: (_) => _MetricExplainerSheet(explainer: explainer),
  );
}

/// The affordance that opens a [MetricExplainer].
///
/// The glyph is sized down to 18dp so it reads as secondary to the heading it
/// sits beside, but the box is held at [AppSpacing.minTapTarget] so the target
/// stays a comfortable 48dp regardless.
class MetricInfoButton extends StatelessWidget {
  const MetricInfoButton({required this.explainer, super.key});

  final MetricExplainer explainer;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return IconButton(
      icon: const Icon(Icons.info_outline_rounded, size: 18),
      color: scheme.onSurfaceVariant,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: AppSpacing.minTapTarget,
        height: AppSpacing.minTapTarget,
      ),
      tooltip: context.l10n.metricExplainerTooltip(explainer.title),
      onPressed: () => showMetricExplainer(context, explainer),
    );
  }
}

class _MetricExplainerSheet extends StatelessWidget {
  const _MetricExplainerSheet({required this.explainer});

  final MetricExplainer explainer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = context.l10n;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SheetHandle(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    explainer.icon,
                    size: 20,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    explainer.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              explainer.summary,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            if (explainer.formula != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              _FormulaCard(
                formula: explainer.formula!,
                example: explainer.example,
              ),
            ],
            if (explainer.points.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.metricExplainerHowToRead,
                style: AppTypography.eyebrow(theme),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final String point in explainer.points) _Point(text: point),
            ],
            if (explainer.caveat != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _Caveat(text: explainer.caveat!),
            ],
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.metricExplainerDismiss),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The formula, and the same formula with real numbers in it.
///
/// Forced left-to-right regardless of app locale: `weight × (1 + reps ÷ 30)`
/// is read left to right in Arabic too, and letting the bidi algorithm pick a
/// right-to-left base direction reorders the operands into nonsense.
class _FormulaCard extends StatelessWidget {
  const _FormulaCard({required this.formula, this.example});

  final String formula;
  final String? example;

  /// Lays out one whitespace-separated token per [Text].
  ///
  /// A single [Text] cannot render `1RM = الوزن × (1 + التكرارات ÷ 30)` in the
  /// order it was written. Forcing the paragraph to LTR settles which end the
  /// line starts at, but not what happens inside it: every Arabic word is a
  /// strong RTL run, the neutral operators around it get absorbed into that
  /// run, and the whole tail comes out mirrored — `= 1RM` migrates to the far
  /// right and the worked example scrambles outright.
  ///
  /// Splitting on spaces makes each token its own bidi paragraph, so a word
  /// still shapes correctly internally while the order between tokens belongs
  /// to the [Wrap] and its explicit direction. The spacing stands in for the
  /// spaces that were split out.
  Widget _tokens(String source, TextStyle style) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      textDirection: TextDirection.ltr,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        for (final String token in source.split(' '))
          if (token.isNotEmpty) Text(token, style: style),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _tokens(
              formula,
              AppTypography.numeric(
                theme.textTheme.titleMedium!.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
            if (example != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Divider(color: scheme.outlineVariant, height: 1),
              const SizedBox(height: AppSpacing.md),
              _tokens(
                example!,
                AppTypography.numeric(
                  theme.textTheme.bodyMedium!.copyWith(
                    color: scheme.primary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Nudged down to sit on the first line's baseline rather than its
          // ascender, which is where a top-aligned dot lands.
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _Caveat extends StatelessWidget {
  const _Caveat({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.lightbulb_outline_rounded,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
