/// Home's progress tiles: Est. 1RM, body weight, streak and average
/// duration, each with its own loading and error state.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/daos/workout_dao.dart';
import '../../../../core/database/database_providers.dart';
import '../../../../core/database/tables/body_metrics.dart';
import '../../../../core/formatters/date_formatters.dart';
import '../../../../core/formatters/unit_formatters.dart';
import '../../../../core/formatters/weight_unit_controller.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/trend_badge.dart';
import '../../../library/domain/exercise_catalogue_l10n.dart';
import '../../domain/dashboard_providers.dart';
import '../../domain/strength_headline.dart';
import '../widgets/summary_card.dart';

/// Priority three: four progress signals worth surfacing off-screen, as
/// an even two-by-two. (It was two tiles and a third stretched full width
/// under them, with its one short figure adrift in the middle.)
class ProgressSection extends StatelessWidget {
  const ProgressSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: context.l10n.navProgress),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: _OneRmCard()),
            SizedBox(width: AppSpacing.md),
            Expanded(child: _BodyWeightCard()),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: _StreakCard()),
            SizedBox(width: AppSpacing.md),
            Expanded(child: _AverageDurationCard()),
          ],
        ),
      ],
    );
  }
}

class _OneRmCard extends ConsumerWidget {
  const _OneRmCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<StrengthHeadline?> headlineAsync =
        ref.watch(dashboardStrengthHeadlineProvider);
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final Map<String, String> slugsById = ref.watch(exerciseSlugsByIdProvider);
    final StrengthHeadline? headline = headlineAsync.value;

    return SummaryCard(
      title: context.l10n.dashboardEstOneRm,
      icon: Icons.trending_up,
      onTap: () => context.goNamed(Routes.progressName),
      isLoading: headlineAsync.isLoading,
      error: headlineAsync.error,
      metric: headline == null
          ? null
          // Rounded like every other estimate in the app. "96.25 kg"
          // claimed a precision the Epley formula does not have, and
          // disagreed with the "96 kg" Progress shows for the same lift.
          : UnitFormatters.estimate(headline.bestKg, unit, context.l10n),
      caption: headline == null
          ? null
          : localizedExerciseName(
              context,
              slugsById,
              headline.exerciseId,
              headline.exerciseName,
            ),
      emptyCaption: context.l10n.dashboardLogALiftToSeeThis,
      trend: switch (headline?.trend) {
        null => null,
        OneRMTrend.up => TrendDirection.up,
        OneRMTrend.down => TrendDirection.down,
        OneRMTrend.flat => TrendDirection.flat,
      },
    );
  }
}

/// Consecutive trained weeks, over the whole history.
class _StreakCard extends ConsumerWidget {
  const _StreakCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<int> streak = ref.watch(dashboardStreakWeeksProvider);
    final int weeks = streak.value ?? 0;

    return SummaryCard(
      title: context.l10n.dashboardStatStreak,
      icon: Icons.local_fire_department_outlined,
      onTap: () => context.goNamed(Routes.progressName),
      isLoading: streak.isLoading,
      error: streak.error,
      metric: weeks == 0 ? null : context.l10n.dashboardStreakWeeks(weeks),
      emptyCaption: context.l10n.dashboardStreakEmpty,
    );
  }
}

class _AverageDurationCard extends ConsumerWidget {
  const _AverageDurationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<double?> durationAsync =
        ref.watch(dashboardAverageWorkoutDurationProvider);
    final double? averageSeconds = durationAsync.value;

    return SummaryCard(
      title: context.l10n.dashboardAverageDuration,
      icon: Icons.timelapse_outlined,
      onTap: () => context.goNamed(Routes.progressName),
      isLoading: durationAsync.isLoading,
      error: durationAsync.error,
      metric: averageSeconds == null
          ? null
          : UnitFormatters.durationShort(
              Duration(seconds: averageSeconds.round()),
              context.l10n,
            ),
      emptyCaption: context.l10n.dashboardAverageDurationEmpty,
    );
  }
}

class _BodyWeightCard extends ConsumerWidget {
  const _BodyWeightCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<BodyMetrics?> metricsAsync =
        ref.watch(dashboardLatestBodyMetricsProvider);
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    return SummaryCard(
      title: context.l10n.dashboardBodyWeight,
      icon: Icons.monitor_weight_outlined,
      // Straight to the weigh-ins, which is what the tile shows; that page
      // also logs one, empty or not. It used to open the top of Progress,
      // with the body chapter at the far end of the page.
      onTap: () => context.pushNamed(Routes.bodyMetricsHistoryName),
      isLoading: metricsAsync.isLoading,
      error: metricsAsync.error,
      metric: metricsAsync.value == null
          ? null
          : UnitFormatters.bodyWeight(
              metricsAsync.value!.weightKg, unit, context.l10n),
      caption: metricsAsync.value == null
          ? null
          : DateFormatters.of(context).relativeDay(metricsAsync.value!.date),
      emptyCaption: context.l10n.dashboardNotRecorded,
    );
  }
}
