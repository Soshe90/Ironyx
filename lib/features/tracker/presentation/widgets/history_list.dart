/// The Workouts tab's history: month headings over rows, and the sheet
/// a calendar day with several workouts opens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/daos/workout_dao.dart';
import '../../../../core/database/database_providers.dart';
import '../../../../core/database/tables/workouts.dart';
import '../../../../core/formatters/date_formatters.dart';
import '../../../../core/formatters/unit_formatters.dart';
import '../../../../core/formatters/weight_unit_controller.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../library/domain/exercise_catalogue_l10n.dart';
import '../../domain/history_grouping.dart';
import 'history_row.dart';

class HistorySliverList extends ConsumerWidget {
  const HistorySliverList(
      {super.key, required this.workouts, required this.prWorkoutIds});

  final List<Workout> workouts;
  final Set<String> prWorkoutIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One query for every row's exercise names (see
    // WorkoutDao.watchExerciseNamesByWorkout); empty while it loads, when
    // rows fall back to their start time.
    final Map<String, List<WorkoutExerciseName>> namesByWorkout =
        ref.watch(workoutExerciseNamesProvider).value ?? const {};
    final Map<String, String> slugsById = ref.watch(exerciseSlugsByIdProvider);
    // Null while loading: rows keep their volume until the counts arrive.
    final Map<String, int>? setCounts =
        ref.watch(workoutSetCountsProvider).value;
    final List<HistoryEntry> entries = groupHistoryByMonth(workouts);

    return SliverList.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) => switch (entries[index]) {
        MonthEntry(:final month, :final workoutCount, :final volumeKg) =>
          _MonthHeader(
            month: month,
            workoutCount: workoutCount,
            volumeKg: volumeKg,
          ),
        WorkoutEntry(:final workout, :final firstInMonth) => Column(
            children: [
              if (!firstInMonth)
                const Divider(indent: historyDateTileWidth + AppSpacing.md),
              WorkoutHistoryTile(
                workout: workout,
                isPersonalRecord: prWorkoutIds.contains(workout.id),
                setCount: setCounts == null ? null : setCounts[workout.id] ?? 0,
                exerciseNames: _displayedNames(
                  context,
                  namesByWorkout[workout.id],
                  slugsById,
                ),
              ),
            ],
          ),
      },
    );
  }
}

/// A workout's exercise names as shown: localized, in logged order. Empty
/// while the names load, and for a workout with no exercises.
List<String> _displayedNames(
  BuildContext context,
  List<WorkoutExerciseName>? names,
  Map<String, String> slugsById,
) =>
    <String>[
      for (final WorkoutExerciseName e in names ?? const [])
        localizedExerciseName(context, slugsById, e.exerciseId, e.exerciseName),
    ];

/// The workouts of one calendar day, for choosing between them: the same
/// rows as the history list. Closes with the chosen workout's id.
class DayWorkoutsSheet extends ConsumerWidget {
  const DayWorkoutsSheet(
      {super.key, required this.date, required this.workouts});

  final DateTime date;
  final List<Workout> workouts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<String, List<WorkoutExerciseName>> namesByWorkout =
        ref.watch(workoutExerciseNamesProvider).value ?? const {};
    final Set<String> prWorkoutIds =
        ref.watch(personalRecordWorkoutIdsProvider).value ?? const <String>{};
    final Map<String, String> slugsById = ref.watch(exerciseSlugsByIdProvider);
    final Map<String, int>? setCounts =
        ref.watch(workoutSetCountsProvider).value;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        0,
        context.pageGutter,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              context.l10n.trackerDayWorkoutsTitle(
                DateFormatters.of(context).full(date),
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (int i = 0; i < workouts.length; i++) ...<Widget>[
            if (i > 0)
              const Divider(indent: historyDateTileWidth + AppSpacing.md),
            WorkoutHistoryTile(
              workout: workouts[i],
              isPersonalRecord: prWorkoutIds.contains(workouts[i].id),
              setCount:
                  setCounts == null ? null : setCounts[workouts[i].id] ?? 0,
              exerciseNames: _displayedNames(
                context,
                namesByWorkout[workouts[i].id],
                slugsById,
              ),
              onOpen: () => Navigator.pop(context, workouts[i].id),
            ),
          ],
        ],
      ),
    );
  }
}

/// `SEPTEMBER 2026 ........ 9 workouts · 62,106 kg`
class _MonthHeader extends ConsumerWidget {
  const _MonthHeader({
    required this.month,
    required this.workoutCount,
    required this.volumeKg,
  });

  final DateTime month;
  final int workoutCount;
  final double volumeKg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.lg,
          bottom: AppSpacing.sm,
        ),
        // A Wrap, not a Row: at a large text size, or with a long month
        // name and a six-figure volume, the two no longer fit on one line.
        // In a Row the summary could not shrink and ran off the edge; here
        // it drops to a second line.
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xxs,
          children: <Widget>[
            Text(
              DateFormatters.of(context).monthYear(month).toUpperCase(),
              style: AppTypography.eyebrow(theme),
            ),
            Text(
              l10n.trackerMonthSummary(
                l10n.progressWorkoutCount(workoutCount),
                UnitFormatters.volume(volumeKg, unit, context.l10n),
              ),
              style: AppTypography.caption(theme),
            ),
          ],
        ),
      ),
    );
  }
}
