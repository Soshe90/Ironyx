import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database_providers.dart';
import '../../../core/database/tables/workouts.dart';
import '../../../core/formatters/date_formatters.dart';
import '../../../core/formatters/unit_formatters.dart';
import '../../../core/formatters/weight_unit_controller.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../programs/domain/program_providers.dart';
import '../../programs/presentation/program_import_action.dart';
import '../domain/active_workout_notifier.dart';
import 'widgets/history_calendar.dart';
import 'widgets/workout_xlsx_import_action.dart';

/// Tracker tab landing page: start/resume a workout, browse past ones.
///
/// The active session itself is a root-level route (ADR-3) so the bottom
/// bar can never be visible mid-set.
class TrackerPage extends ConsumerStatefulWidget {
  const TrackerPage({super.key});

  @override
  ConsumerState<TrackerPage> createState() => _TrackerPageState();
}

class _TrackerPageState extends ConsumerState<TrackerPage> {
  DateTime _visibleMonth = _monthOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final WidgetRef ref = this.ref;
    final draft = ref.watch(activeWorkoutProvider);
    final programsAsync = ref.watch(programSummariesProvider);
    final historyAsync = ref.watch(workoutHistoryStreamProvider);
    final prWorkoutIds =
        ref.watch(personalRecordWorkoutIdsProvider).value ?? const <String>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Tracker')),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            sliver: SliverToBoxAdapter(
              child: draft == null
                  ? FilledButton.icon(
                      onPressed: () =>
                          context.pushNamed(Routes.activeWorkoutName),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start workout'),
                    )
                  : _ResumeWorkoutBanner(exerciseCount: draft.exercises.length),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Programs',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'New program',
                    onPressed: () => context.pushNamed(Routes.programNewName),
                  ),
                  const ProgramImportAction(),
                ],
              ),
            ),
          ),
          programsAsync.when(
            data: (programs) => programs.isEmpty
                ? const SliverToBoxAdapter(child: SizedBox.shrink())
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    sliver: SliverList.builder(
                      itemCount: programs.length,
                      itemBuilder: (context, index) {
                        final summary = programs[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: AppCard(
                            onTap: () => _openProgram(
                              context,
                              ref,
                              summary.program.id,
                            ),
                            semanticLabel:
                                '${summary.program.name}, ${summary.dayCount} days',
                            child: Row(
                              children: [
                                const Icon(Icons.event_note),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        summary.program.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                      if (summary.program.description
                                          case final d?)
                                        Text(
                                          d,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
            loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (_, __) =>
                const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'History',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const WorkoutXlsxImportAction(),
                ],
              ),
            ),
          ),
          historyAsync.when(
            data: (workouts) => workouts.isEmpty
                ? const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.history,
                      title: 'No workouts yet',
                      message: 'Finish a workout and it will show up here.',
                    ),
                  )
                : SliverMainAxisGroup(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          0,
                          AppSpacing.lg,
                          AppSpacing.md,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: AppCard(
                            child: HistoryCalendar(
                              visibleMonth: _visibleMonth,
                              markedDates: {
                                for (final workout in workouts)
                                  _dateOnly(workout.startedAt),
                              },
                              onMonthChanged: (month) => setState(() {
                                _visibleMonth = _monthOnly(month);
                              }),
                              onDayTap: (date) => _openWorkoutForDay(
                                context,
                                workouts,
                                date,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          0,
                          AppSpacing.lg,
                          AppSpacing.lg,
                        ),
                        sliver: _HistorySliverList(
                          workouts: workouts,
                          prWorkoutIds: prWorkoutIds,
                        ),
                      ),
                    ],
                  ),
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorView(
                title: 'Failed to load history',
                details: error.toString(),
                onRetry: () => ref.invalidate(workoutHistoryStreamProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openWorkoutForDay(
    BuildContext context,
    List<Workout> workouts,
    DateTime date,
  ) {
    for (final workout in workouts) {
      if (_dateOnly(workout.startedAt) != date) continue;
      if (!context.mounted) return;
      context.pushNamed(
        Routes.workoutDetailName,
        pathParameters: {'id': workout.id},
      );
      return;
    }
  }

  static DateTime _monthOnly(DateTime date) => DateTime(date.year, date.month);

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// Awaits the program detail before pushing, rather than letting
  /// [ProgramDetailPage] show its own brief loading spinner after the push
  /// starts — the data's almost always already cached from the list this
  /// card came from, so this avoids a pointless flash of a spinner.
  Future<void> _openProgram(
    BuildContext context,
    WidgetRef ref,
    String programId,
  ) async {
    await ref.read(programDetailProvider(programId).future);
    if (!context.mounted) return;
    await context.pushNamed(
      Routes.programDetailName,
      pathParameters: {'id': programId},
    );
  }
}

class _ResumeWorkoutBanner extends StatelessWidget {
  const _ResumeWorkoutBanner({required this.exerciseCount});

  final int exerciseCount;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AppCard(
      onTap: () => context.pushNamed(Routes.activeWorkoutName),
      semanticLabel: 'Resume in-progress workout',
      child: Row(
        children: [
          Icon(Icons.play_circle_outline, color: scheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Workout in progress',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  exerciseCount == 0
                      ? 'Tap to resume'
                      : '$exerciseCount exercise${exerciseCount == 1 ? '' : 's'} logged · tap to resume',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _HistorySliverList extends StatelessWidget {
  const _HistorySliverList(
      {required this.workouts, required this.prWorkoutIds});

  final List<Workout> workouts;
  final Set<String> prWorkoutIds;

  @override
  Widget build(BuildContext context) {
    return SliverList.builder(
      itemCount: workouts.length,
      itemBuilder: (context, index) {
        final workout = workouts[index];
        final showHeader = index == 0 ||
            DateFormatters.relativeDay(workouts[index - 1].startedAt) !=
                DateFormatters.relativeDay(workout.startedAt);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeader)
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.sm,
                    bottom: AppSpacing.xs,
                  ),
                  child: Text(
                    DateFormatters.relativeDay(workout.startedAt),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              _WorkoutHistoryTile(
                workout: workout,
                isPersonalRecord: prWorkoutIds.contains(workout.id),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WorkoutHistoryTile extends ConsumerWidget {
  const _WorkoutHistoryTile({
    required this.workout,
    required this.isPersonalRecord,
  });

  final Workout workout;
  final bool isPersonalRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    return AppCard(
      onTap: () => context.pushNamed(
        Routes.workoutDetailName,
        pathParameters: {'id': workout.id},
      ),
      semanticLabel: 'Workout on ${DateFormatters.full(workout.startedAt)}, '
          '${UnitFormatters.volume(workout.totalVolumeKg, unit)} volume'
          '${isPersonalRecord ? ', personal record' : ''}',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      DateFormatters.time(workout.startedAt),
                      style: theme.textTheme.titleSmall,
                    ),
                    if (isPersonalRecord) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const _PrBadge(),
                    ],
                  ],
                ),
                Text(
                  workout.durationSeconds == null
                      ? UnitFormatters.volume(
                          workout.totalVolumeKg,
                          unit,
                        )
                      : '${UnitFormatters.volume(workout.totalVolumeKg, unit)} · '
                          '${UnitFormatters.durationShort(Duration(seconds: workout.durationSeconds!))}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// Badge shown on a history entry that set a new estimated-1RM personal
/// record for at least one exercise (see `WorkoutDao.watchPersonalRecordWorkoutIds`).
class _PrBadge extends StatelessWidget {
  const _PrBadge();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.military_tech,
              size: 12, color: scheme.onTertiaryContainer),
          const SizedBox(width: 2),
          Text(
            'PR',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
