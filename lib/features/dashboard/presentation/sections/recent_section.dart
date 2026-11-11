/// Home's recent activity: the last workout and the last timer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/tables/timer_sessions.dart';
import '../../../../core/database/tables/workouts.dart';
import '../../../../core/formatters/date_formatters.dart';
import '../../../../core/formatters/unit_formatters.dart';
import '../../../../core/formatters/weight_unit_controller.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../../core/widgets/section_header.dart';
import '../../domain/dashboard_providers.dart';

/// Priority four: what happened most recently. Compact rows, not tiles —
/// these are navigation affordances with a value attached, not metrics to
/// compare at a glance.
class RecentSection extends ConsumerWidget {
  const RecentSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Before a first workout there is no last workout to show ("Nothing
    // yet" was a dead row), and unless a timer has been used, nothing
    // recent at all: then the heading goes too.
    final bool isNewUser = ref.watch(dashboardIsNewUserProvider);
    final AsyncValue<TimerSession?> timer =
        ref.watch(dashboardLastTimerSessionProvider);
    if (isNewUser && timer.hasValue && timer.value == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: context.l10n.dashboardRecent),
        if (!isNewUser) const _LastWorkoutRow(),
        const _LastTimerRow(),
      ],
    );
  }
}

/// Shared shape for the two "recent activity" rows.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
    this.caption,
    this.isLoading = false,
    this.error,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? value;
  final String? caption;
  final bool isLoading;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = context.l10n;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      semanticLabel: error != null
          ? l10n.dashboardRowSemanticError(title)
          : isLoading
              ? l10n.dashboardRowSemanticLoading(title)
              : l10n.dashboardRowSemantic(
                  title,
                  value ?? l10n.dashboardRowSemanticNoData,
                  caption ?? '',
                ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xxs),
                if (error != null)
                  Text(
                    l10n.metricCouldNotLoad,
                    style: AppTypography.caption(theme)
                        .copyWith(color: scheme.error),
                  )
                else if (isLoading)
                  const LoadingShimmer(width: 120, height: 12)
                else
                  Text(
                    caption ?? l10n.dashboardNothingYet,
                    style: AppTypography.caption(theme),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (!isLoading && error == null && value != null) ...<Widget>[
            const SizedBox(width: AppSpacing.md),
            Text(
              value!,
              style: AppTypography.cardMetric(
                scheme,
                size: AppTypography.metricSizeSm,
              ),
            ),
          ],
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _LastWorkoutRow extends ConsumerWidget {
  const _LastWorkoutRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Workout?> workoutAsync =
        ref.watch(dashboardLastWorkoutProvider);
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final Workout? workout = workoutAsync.value;

    return _ActivityRow(
      icon: Icons.fitness_center_outlined,
      title: context.l10n.dashboardLastWorkout,
      // The row names one workout, so it opens that one. It used to open
      // the Workouts tab, where the reader had to find it again in the
      // history. With none yet, the Workouts tab is where one is started.
      onTap: workout == null
          ? () => context.goNamed(Routes.trackerName)
          : () => context.pushNamed(
                Routes.workoutDetailName,
                pathParameters: <String, String>{'id': workout.id},
              ),
      isLoading: workoutAsync.isLoading,
      error: workoutAsync.error,
      value: workout == null
          ? null
          : UnitFormatters.volume(workout.totalVolumeKg, unit, context.l10n),
      caption: workout == null
          ? null
          : <String>[
              DateFormatters.of(context).relativeDay(workout.startedAt),
              if (workout.durationSeconds case final int seconds)
                UnitFormatters.durationShort(
                    Duration(seconds: seconds), context.l10n),
            ].join(' · '),
    );
  }
}

class _LastTimerRow extends ConsumerWidget {
  const _LastTimerRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TimerSession?> sessionAsync =
        ref.watch(dashboardLastTimerSessionProvider);

    // Most people never use the standalone timer; a permanent "Last timer:
    // Nothing yet" row is a dead card on their home screen. It appears once
    // there is something to show (loading and errors still render).
    if (sessionAsync.hasValue && sessionAsync.value == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: _ActivityRow(
        icon: Icons.timer_outlined,
        title: context.l10n.dashboardLastTimer,
        onTap: () => context.goNamed(Routes.timerName),
        isLoading: sessionAsync.isLoading,
        error: sessionAsync.error,
        caption: sessionAsync.value == null
            ? null
            : '${sessionAsync.value!.presetName} · '
                '${DateFormatters.of(context).relativeDay(sessionAsync.value!.startedAt)}',
        value: sessionAsync.value?.actualDurationSeconds == null
            ? null
            // As a clock, minutes and seconds. In whole minutes a
            // twenty-second timer read "0m".
            : UnitFormatters.duration(
                Duration(seconds: sessionAsync.value!.actualDurationSeconds!),
              ),
      ),
    );
  }
}
