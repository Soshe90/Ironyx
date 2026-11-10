/// The Insights card at the top of the Progress page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/formatters/unit_formatters.dart';
import '../../../../core/formatters/week_start_controller.dart';
import '../../../../core/formatters/weight_unit_controller.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/services/clock.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../library/domain/exercise_catalogue_l10n.dart';
import '../../domain/progress_insights.dart';
import '../../domain/progress_providers.dart';
import '../widgets/progress_charts.dart';
import '../widgets/progress_visuals.dart';

class InsightsSection extends ConsumerWidget {
  const InsightsSection({super.key, required this.range});
  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strength = ref.watch(strengthChangeProvider(range));
    final volume = ref.watch(weeklyVolumeSeriesProvider(range));
    final frequency = ref.watch(workoutFrequencySeriesProvider(range));
    final muscles = ref.watch(muscleGroupSeriesProvider(range));
    final previousMuscles = ref.watch(previousMuscleGroupSeriesProvider(range));
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final Map<String, String> slugsById = ref.watch(exerciseSlugsByIdProvider);

    if (strength.isLoading ||
        volume.isLoading ||
        frequency.isLoading ||
        muscles.isLoading ||
        previousMuscles.isLoading) {
      return const ProgressChartLoading();
    }
    Object? error;
    for (final value in [
      strength,
      volume,
      frequency,
      muscles,
      previousMuscles,
    ]) {
      if (value.hasError) {
        error = value.error;
        break;
      }
    }
    if (error != null) {
      return ProgressChartError(
        error: error,
        onRetry: () {
          ref.invalidate(strengthChangeProvider(range));
          ref.invalidate(weeklyVolumeSeriesProvider(range));
          ref.invalidate(workoutFrequencySeriesProvider(range));
          ref.invalidate(muscleGroupSeriesProvider(range));
          ref.invalidate(previousMuscleGroupSeriesProvider(range));
        },
      );
    }

    final insights = buildProgressInsights(
      strengthChanges: strength.value ?? const [],
      volume: volume.value ?? const [],
      frequency: frequency.value ?? const [],
      currentMuscleVolume: muscles.value ?? const [],
      previousMuscleVolume: previousMuscles.value ?? const [],
      // The same week settings the series were bucketed with.
      weekStart: ref.watch(weekStartControllerProvider),
      utcOffset: ref.watch(todayProvider).timeZoneOffset,
      now: ref.watch(localNowProvider),
    );
    return Semantics(
      container: true,
      label: context.l10n.progressInsightsSemantic,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.progressInsightsTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            if (insights.isEmpty)
              Text(
                context.l10n.progressInsightsEmpty,
                style: AppTypography.caption(Theme.of(context)),
              )
            else
              for (final insight in insights)
                _InsightTile(
                  insight: insight,
                  unit: unit,
                  // The insight carries the stored English name; show the
                  // user's language, as every other card on the page does.
                  subjectName: switch ((insight.kind, insight.subjectId)) {
                    (InsightKind.strengthChange, final String id) =>
                      localizedExerciseName(
                        context,
                        slugsById,
                        id,
                        insight.subjectName ?? '',
                      ),
                    (InsightKind.neglectedMuscle, final String id) =>
                      localizedMuscleName(
                        context,
                        id,
                        insight.subjectName ?? '',
                      ),
                    _ => insight.subjectName,
                  },
                ),
          ],
        ),
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({
    required this.insight,
    required this.unit,
    required this.subjectName,
  });

  final ProgressInsight insight;
  final WeightUnit unit;

  /// The insight's exercise or muscle group, already in the user's language.
  final String? subjectName;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String target = switch (insight.target) {
      InsightTarget.strength => l10n.progressInsightTargetStrength,
      InsightTarget.volume => l10n.progressInsightTargetVolume,
      InsightTarget.consistency => l10n.progressInsightTargetConsistency,
      InsightTarget.balance => l10n.progressInsightTargetBalance,
    };
    final ({String headline, String figure}) text = switch (insight.kind) {
      InsightKind.strengthChange => (
          headline: l10n.progressInsightStrengthHeadline(
            insight.direction!.name,
            subjectName!,
            insight.percentage!,
          ),
          figure: l10n.progressInsightStrengthFigure(
            UnitFormatters.estimate(insight.currentBestKg!, unit, context.l10n),
          ),
        ),
      InsightKind.consistencySlipping => (
          headline: l10n.progressInsightConsistencyHeadline,
          figure: l10n.progressInsightConsistencyFigure(
            UnitFormatters.oneDecimal(insight.averageSessionsPerWeek!),
          ),
        ),
      InsightKind.volumeTrendingDown => (
          headline: l10n.progressInsightVolumeHeadline,
          figure: l10n.progressInsightVolumeFigure(insight.percentage!),
        ),
      InsightKind.neglectedMuscle => (
          headline: l10n.progressInsightNeglectedHeadline(subjectName!),
          figure: l10n.progressInsightNeglectedFigure,
        ),
    };
    final ThemeData theme = Theme.of(context);
    final bool light = theme.brightness == Brightness.light;
    // Gains green, slips red, and a prompt to act in the brand colour
    // rather than a third alarm hue.
    final (IconData icon, Color color) = switch (insight.severity) {
      InsightSeverity.actionable => (
          Icons.flag_rounded,
          theme.colorScheme.primary,
        ),
      InsightSeverity.negative => (
          Icons.trending_down_rounded,
          light ? AppColors.lossInkLight : AppColors.loss,
        ),
      _ => (
          Icons.trending_up_rounded,
          light ? AppColors.gainInkLight : AppColors.gain,
        ),
    };
    return Semantics(
      container: true,
      label: l10n.progressInsightSemantic(
        text.headline,
        text.figure,
        target,
      ),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ProgressIconChip(icon: icon, color: color),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(text.headline, style: theme.textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      l10n.progressInsightSubtitle(text.figure, target),
                      style: AppTypography.caption(theme),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
