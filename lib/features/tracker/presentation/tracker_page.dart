import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database_providers.dart';
import '../../../core/database/tables/workouts.dart';
import '../../../core/formatters/date_formatters.dart';
import '../../../core/formatters/unit_formatters.dart';
import '../../../core/formatters/weight_unit_controller.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/page_body.dart';
import '../../../core/widgets/pr_badge.dart';
import '../../../core/widgets/section_header.dart';
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
      appBar: AppBar(title: Text(context.l10n.navTracker)),
      body: PageBody(
        gutter: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: context.sliverGutter.copyWith(
                top: AppSpacing.sm,
                bottom: AppSpacing.xl,
              ),
              sliver: SliverToBoxAdapter(
                child: draft == null
                    ? FilledButton.icon(
                        onPressed: () =>
                            context.pushNamed(Routes.activeWorkoutName),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(context.l10n.dashboardStartWorkout),
                      )
                    : _ResumeWorkoutBanner(
                        exerciseCount: draft.exercises.length,
                      ),
              ),
            ),
            SliverPadding(
              padding: context.sliverGutter,
              sliver: SliverToBoxAdapter(
                child: SectionHeader(
                  title: context.l10n.trackerPrograms,
                  subtitle: context.l10n.trackerProgramsSubtitle,
                  actionLabel: context.l10n.trackerNew,
                  onAction: () => context.pushNamed(Routes.programNewName),
                ),
              ),
            ),
            programsAsync.when(
              data: (programs) => programs.isEmpty
                  ? SliverPadding(
                      padding:
                          context.sliverGutter.copyWith(bottom: AppSpacing.xl),
                      sliver: SliverToBoxAdapter(
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                context.l10n.trackerNoPrograms,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                context.l10n.trackerNoProgramsMessage,
                                style: AppTypography.caption(
                                  Theme.of(context),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              // The button theme sets a full-width minimum,
                              // so it needs an Expanded to sit in a Row.
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => context
                                          .pushNamed(Routes.programNewName),
                                      icon: const Icon(Icons.add),
                                      label: Text(context.l10n.trackerNewProgram),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  const ProgramImportAction(),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : SliverPadding(
                      padding:
                          context.sliverGutter.copyWith(bottom: AppSpacing.xl),
                      sliver: SliverList.builder(
                        itemCount: programs.length,
                        itemBuilder: (context, index) {
                          final summary = programs[index];
                          return Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: _ProgramTile(
                              name: summary.program.name,
                              description: summary.program.description,
                              dayCount: summary.dayCount,
                              onTap: () => _openProgram(
                                context,
                                ref,
                                summary.program.id,
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
              padding: context.sliverGutter,
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: SectionHeader(title: context.l10n.trackerHistory),
                    ),
                    const WorkoutXlsxImportAction(),
                  ],
                ),
              ),
            ),
            historyAsync.when(
              data: (workouts) => workouts.isEmpty
                  ? SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        icon: Icons.history,
                        title: context.l10n.trackerNoWorkouts,
                        message: context.l10n.trackerNoWorkoutsMessage,
                      ),
                    )
                  : SliverMainAxisGroup(
                      slivers: [
                        SliverPadding(
                          padding: context.sliverGutter
                              .copyWith(bottom: AppSpacing.lg),
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
                          padding: context.sliverGutter
                              .copyWith(bottom: AppSpacing.xl),
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
                  title: context.l10n.trackerHistoryLoadFailed,
                  details: error.toString(),
                  onRetry: () => ref.invalidate(workoutHistoryStreamProvider),
                ),
              ),
            ),
          ],
        ),
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

class _ProgramTile extends StatelessWidget {
  const _ProgramTile({
    required this.name,
    required this.description,
    required this.dayCount,
    required this.onTap,
  });

  final String name;
  final String? description;
  final int dayCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      semanticLabel: context.l10n.trackerProgramSemantic(
        name,
        context.l10n.dayCount(dayCount),
      ),
      child: Row(
        children: [
          Icon(Icons.event_note_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  description ?? context.l10n.dayCount(dayCount),
                  style: AppTypography.caption(theme),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

class _ResumeWorkoutBanner extends StatelessWidget {
  const _ResumeWorkoutBanner({required this.exerciseCount});

  final int exerciseCount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return AppCard(
      onTap: () => context.pushNamed(Routes.activeWorkoutName),
      semanticLabel: context.l10n.trackerResumeSemantic,
      child: Row(
        children: [
          Icon(Icons.play_circle_outline, color: scheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.dashboardWorkoutInProgress,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  exerciseCount == 0
                      ? context.l10n.trackerTapToResume
                      : context.l10n.trackerResumeWithExercises(
                          context.l10n.exerciseCount(exerciseCount),
                        ),
                  style: AppTypography.caption(theme),
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
            DateFormatters.of(context).relativeDay(workouts[index - 1].startedAt) !=
                DateFormatters.of(context).relativeDay(workout.startedAt);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeader)
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.sm,
                    bottom: AppSpacing.sm,
                  ),
                  child: Text(
                    DateFormatters.of(context).relativeDay(workout.startedAt).toUpperCase(),
                    style: AppTypography.eyebrow(Theme.of(context)),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      semanticLabel: isPersonalRecord
          ? context.l10n.trackerWorkoutSemanticPr(
              DateFormatters.of(context).full(workout.startedAt),
              UnitFormatters.volume(workout.totalVolumeKg, unit),
            )
          : context.l10n.trackerWorkoutSemantic(
              DateFormatters.of(context).full(workout.startedAt),
              UnitFormatters.volume(workout.totalVolumeKg, unit),
            ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      DateFormatters.of(context).time(workout.startedAt),
                      style: theme.textTheme.titleSmall,
                    ),
                    if (isPersonalRecord) ...[
                      const SizedBox(width: AppSpacing.sm),
                      const PrBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  workout.durationSeconds == null
                      ? context.l10n.trackerNoDuration
                      : UnitFormatters.durationShort(
                          Duration(seconds: workout.durationSeconds!),
                        ),
                  style: AppTypography.caption(theme),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            UnitFormatters.volume(workout.totalVolumeKg, unit),
            style: AppTypography.cardMetric(
              scheme,
              size: AppTypography.metricSizeSm,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
