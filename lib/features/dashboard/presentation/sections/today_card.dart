/// Home's first card: today's session, started or resumed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/tables/workouts.dart';
import '../../../../core/formatters/date_formatters.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/services/clock.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../tracker/domain/active_workout_notifier.dart';
import '../../domain/dashboard_providers.dart';

/// Priority one: today's session. Resumes an in-progress draft when there
/// is one, otherwise starts a new workout.
///
/// A draft left open is the single most important thing the dashboard can
/// tell the user, so it takes over this card entirely rather than appearing
/// as a separate banner they might scroll past.
class TodayCard extends ConsumerWidget {
  const TodayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(activeWorkoutProvider);
    final DateTime today = ref.watch(todayProvider);
    // Loading and failure both read as "no last workout" here; the Recent
    // row below owns this query's loading and error states.
    final Workout? lastWorkout = ref.watch(dashboardLastWorkoutProvider).value;
    final ThemeData theme = Theme.of(context);
    final bool inProgress = draft != null;
    final AppLocalizations l10n = context.l10n;

    final int loggedSets = draft == null
        ? 0
        : draft.exercises.fold<int>(
            0,
            (int total, e) => total + e.sets.where((s) => s.isCompleted).length,
          );

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[AppColors.workoutHero, AppColors.workoutHeroEnd],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  DateFormatters.of(context).dayHeadline(today).toUpperCase(),
                  style: AppTypography.eyebrow(
                    theme,
                    color: AppColors.workoutHeroAccent,
                  ),
                ),
              ),
              if (inProgress)
                // Status is carried by the label, not the dot alone.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.fiber_manual_record,
                      size: 10,
                      color: AppColors.workoutHeroAccent,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      l10n.dashboardInProgressBadge,
                      style: AppTypography.eyebrow(
                        theme,
                        color: AppColors.workoutHeroAccent,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  inProgress
                      ? l10n.dashboardWorkoutInProgress
                      : l10n.dashboardReadyToTrain,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: AppColors.workoutHeroForeground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.workoutHeroAccent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  inProgress ? Icons.play_arrow_rounded : Icons.bolt_rounded,
                  color: AppColors.workoutHeroAccent,
                  size: 28,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            inProgress
                ? _draftSummary(l10n, draft.exercises.length, loggedSets)
                // How long since the last session is the one fact that
                // bears on starting another. The fixed sentence it replaces
                // was read once and never again.
                : lastWorkout == null
                    ? l10n.dashboardReadyToTrainCaption
                    : l10n.dashboardLastTrained(
                        DateFormatters.of(context)
                            .relativeDay(lastWorkout.startedAt, now: today),
                      ),
            style: AppTypography.caption(theme).copyWith(
              color: AppColors.workoutHeroCaption,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (context.isAtLeast(Breakpoint.medium))
            Row(
              children: <Widget>[
                Expanded(child: _primaryAction(context, l10n, inProgress)),
                if (!inProgress) ...<Widget>[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _secondaryAction(context, l10n)),
                ],
              ],
            )
          else ...<Widget>[
            _primaryAction(context, l10n, inProgress),
            if (!inProgress) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              _secondaryAction(context, l10n),
            ],
          ],
        ],
      ),
    );
  }

  Widget _primaryAction(
    BuildContext context,
    AppLocalizations l10n,
    bool inProgress,
  ) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.workoutHeroAccent,
        foregroundColor: AppColors.workoutHero,
      ),
      onPressed: () => context.pushNamed(Routes.activeWorkoutName),
      icon: Icon(inProgress ? Icons.play_arrow : Icons.add),
      label: Text(
        inProgress ? l10n.dashboardResumeWorkout : l10n.dashboardStartWorkout,
      ),
    );
  }

  /// The other way to begin. A text button, not a second outlined one in
  /// the accent colour: two bordered buttons of equal weight made the card
  /// ask a question before it offered an action.
  Widget _secondaryAction(BuildContext context, AppLocalizations l10n) =>
      TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.workoutHeroCaption,
          minimumSize: const Size.fromHeight(AppSpacing.minTapTarget),
        ),
        onPressed: () => context.goNamed(Routes.trackerName),
        icon: const Icon(Icons.event_note_outlined),
        label: Text(l10n.dashboardStartFromProgram),
      );

  String _draftSummary(AppLocalizations l10n, int exercises, int sets) {
    if (exercises == 0) return l10n.dashboardNoExercisesYet;
    return l10n.dashboardDraftSummary(
      l10n.exerciseCount(exercises),
      l10n.setsLoggedCount(sets),
    );
  }
}
