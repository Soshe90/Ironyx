import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database_providers.dart';
import '../../../core/database/tables/workouts.dart';
import '../../../core/error_reporting.dart';
import '../../../core/formatters/week_start_controller.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/router/routes.dart';
import '../../../core/services/clock.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/page_body.dart';
import '../../../core/widgets/section_header.dart';
import '../../programs/domain/program_providers.dart';
import '../../programs/presentation/program_import_action.dart';
import '../domain/active_workout_notifier.dart';
import 'widgets/history_calendar.dart';
import 'widgets/history_list.dart';
import 'widgets/history_row.dart';
import 'widgets/program_strip.dart';
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

/// The tab's one overflow menu: the two imports, both rare.
enum _ImportAction { programsCsv, workoutsXlsx }

class _TrackerPageState extends ConsumerState<TrackerPage> {
  /// Month shown by the calendar. Starts on the current month and follows
  /// a month change only while the user is still looking at the month that
  /// was current (see the `todayProvider` listener in [build]).
  late DateTime _visibleMonth = _monthOnly(ref.read(todayProvider));

  /// The calendar is a second lens on the same history. Shown by default it
  /// pushed the list itself, the reason people open this tab, below the
  /// fold, so it is opt-in for the session.
  bool _showCalendar = false;

  /// True while a program card is being opened, so a second tap (a double
  /// tap, or an impatient one) does not push the same page twice.
  bool _openingProgram = false;

  /// How long a card waits for its program before opening anyway. The wait
  /// only saves a spinner flash on a page whose data is nearly always cached
  /// already; Riverpod keeps a failing provider's `.future` pending while it
  /// retries, so without a limit a tap on a failing program did nothing for
  /// seconds.
  static const Duration _programPrefetchLimit = Duration(milliseconds: 600);

  @override
  Widget build(BuildContext context) {
    final WidgetRef ref = this.ref;
    final DateTime today = ref.watch(todayProvider);
    // The tab stays alive in the shell, so the app can outlive the month it
    // was opened in. A month the user browsed back to stays put; the month
    // that was current moves on to the new one.
    ref.listen<DateTime>(todayProvider, (DateTime? previous, DateTime next) {
      if (previous == null) return;
      final DateTime wasCurrent = _monthOnly(previous);
      if (_visibleMonth == wasCurrent && _monthOnly(next) != wasCurrent) {
        setState(() => _visibleMonth = _monthOnly(next));
      }
    });
    final programsAsync = ref.watch(programSummariesProvider);
    final historyAsync = ref.watch(workoutHistoryStreamProvider);
    final prWorkoutIds =
        ref.watch(personalRecordWorkoutIdsProvider).value ?? const <String>{};
    final bool hasHistory = historyAsync.value?.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.navTracker),
        // Both imports in one place. Each section had a menu of its own
        // with this one rare item in it, two "⋮" for two one-off actions;
        // the headings now keep only their everyday action.
        actions: <Widget>[
          PopupMenuButton<_ImportAction>(
            tooltip: context.l10n.trackerImportMenu,
            onSelected: (_ImportAction action) => switch (action) {
              _ImportAction.programsCsv =>
                ProgramImportAction.run(context, ref),
              _ImportAction.workoutsXlsx =>
                WorkoutXlsxImportAction.run(context, ref),
            },
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<_ImportAction>>[
              PopupMenuItem<_ImportAction>(
                value: _ImportAction.programsCsv,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.upload_file_outlined),
                  title: Text(context.l10n.programImportTooltip),
                ),
              ),
              PopupMenuItem<_ImportAction>(
                value: _ImportAction.workoutsXlsx,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.table_view_outlined),
                  title: Text(context.l10n.trackerImportWorkoutsXlsx),
                ),
              ),
            ],
          ),
        ],
      ),
      body: PageBody(
        gutter: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: context.sliverGutter.copyWith(
                top: AppSpacing.sm,
                bottom: AppSpacing.xl,
              ),
              sliver: const SliverToBoxAdapter(child: _StartOrResume()),
            ),
            SliverPadding(
              padding: context.sliverGutter,
              sliver: SliverToBoxAdapter(
                child: SectionHeader(
                  title: context.l10n.trackerPrograms,
                  // What a program is, for someone who has none. Once
                  // there are cards under the heading they say it
                  // themselves, and the sentence only wrapped onto a
                  // second line with one word on it.
                  // Only once the list is known to be empty: while it
                  // loads, or when it failed, there may be programs.
                  subtitle:
                      programsAsync.hasValue && programsAsync.value!.isEmpty
                          ? context.l10n.trackerProgramsSubtitle
                          : null,
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
                                      label:
                                          Text(context.l10n.trackerNewProgram),
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
                  : SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                        child: ProgramStrip(
                          programs: programs,
                          onOpen: (String id) => _openProgram(context, ref, id),
                        ),
                      ),
                    ),
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              // It showed nothing, and the heading's "what is a program"
              // line, as if there were none.
              error: (error, _) => SliverPadding(
                padding: context.sliverGutter.copyWith(bottom: AppSpacing.xl),
                sliver: SliverToBoxAdapter(
                  child: AppCard(
                    child: ErrorView(
                      title: context.l10n.trackerProgramsLoadFailed,
                      details: error.toString(),
                      compact: true,
                      onRetry: () => ref.invalidate(programSummariesProvider),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: context.sliverGutter,
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: SectionHeader(title: context.l10n.trackerHistory),
                    ),
                    // Aligned with the header text, which carries a bottom
                    // gap of its own.
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (hasHistory)
                            IconButton(
                              isSelected: _showCalendar,
                              icon: const Icon(Icons.calendar_month_outlined),
                              selectedIcon: const Icon(Icons.calendar_month),
                              tooltip: _showCalendar
                                  ? context.l10n.trackerHideCalendar
                                  : context.l10n.trackerShowCalendar,
                              onPressed: () => setState(
                                () => _showCalendar = !_showCalendar,
                              ),
                            ),
                        ],
                      ),
                    ),
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
                        if (_showCalendar)
                          SliverPadding(
                            padding: context.sliverGutter
                                .copyWith(bottom: AppSpacing.lg),
                            sliver: SliverToBoxAdapter(
                              child: AppCard(
                                child: HistoryCalendar(
                                  visibleMonth: _visibleMonth,
                                  today: today,
                                  weekStart: ref.watch(
                                    weekStartControllerProvider,
                                  ),
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
                          sliver: HistorySliverList(
                            workouts: workouts,
                            prWorkoutIds: prWorkoutIds,
                          ),
                        ),
                      ],
                    ),
              // Rows shaped like the ones on their way, as the rest of the
              // app loads; a spinner in the middle of the page was the odd
              // one out.
              loading: () => SliverPadding(
                padding: context.sliverGutter,
                sliver: SliverToBoxAdapter(
                  child: Semantics(
                    label: context.l10n.trackerHistoryLoading,
                    child: const ExcludeSemantics(
                      child: Column(
                        children: <Widget>[
                          WorkoutHistoryRowPlaceholder(),
                          WorkoutHistoryRowPlaceholder(),
                          WorkoutHistoryRowPlaceholder(),
                        ],
                      ),
                    ),
                  ),
                ),
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

  /// Opens the day's workout, or, with several, asks which.
  ///
  /// It opened the first it found, the latest that day, so a morning and
  /// an evening session left the morning reachable only from the list.
  Future<void> _openWorkoutForDay(
    BuildContext context,
    List<Workout> workouts,
    DateTime date,
  ) async {
    final List<Workout> onDay = <Workout>[
      for (final Workout workout in workouts)
        if (_dateOnly(workout.startedAt) == date) workout,
    ];
    if (onDay.isEmpty) return;
    final String? id = onDay.length == 1
        ? onDay.single.id
        : await showModalBottomSheet<String>(
            context: context,
            useSafeArea: true,
            showDragHandle: true,
            // Above the shell's navigator, as the app's other sheets are,
            // so the scrim covers the bottom bar too.
            useRootNavigator: true,
            isScrollControlled: true,
            builder: (_) => DayWorkoutsSheet(date: date, workouts: onDay),
          );
    if (id == null || !context.mounted) return;
    await context.pushNamed(
      Routes.workoutDetailName,
      pathParameters: {'id': id},
    );
  }

  static DateTime _monthOnly(DateTime date) => DateTime(date.year, date.month);

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// Awaits the program detail before pushing, rather than letting
  /// [ProgramDetailPage] show its own brief loading spinner after the push
  /// starts — the data's almost always already cached from the list this
  /// card came from, so this avoids a pointless flash of a spinner.
  ///
  /// The wait is a nicety, so it never stops the page opening: past
  /// [_programPrefetchLimit], or when the program fails to load, the page
  /// opens anyway and shows its own loading or error state, with Retry. A
  /// failure here used to escape the tap handler unhandled and leave the
  /// card doing nothing.
  Future<void> _openProgram(
    BuildContext context,
    WidgetRef ref,
    String programId,
  ) async {
    if (_openingProgram) return;
    _openingProgram = true;
    try {
      try {
        await ref
            .read(programDetailProvider(programId).future)
            .timeout(_programPrefetchLimit);
      } on Object catch (error, stackTrace) {
        reportError(error, stackTrace, context: 'tracker open program');
      }
      if (!context.mounted) return;
      await context.pushNamed(
        Routes.programDetailName,
        pathParameters: {'id': programId},
      );
    } finally {
      _openingProgram = false;
    }
  }
}

/// Start, or resume the workout that is open.
///
/// Its own widget, reading only whether a draft is open and how many
/// exercises it has. The page used to watch the whole draft for that, and
/// the draft changes on every weight and rep typed: each keystroke in an
/// open workout rebuilt this tab, regrouping the entire history by month
/// and the calendar's set of days with it.
class _StartOrResume extends ConsumerWidget {
  const _StartOrResume();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int? exerciseCount = ref.watch(
      activeWorkoutProvider.select((draft) => draft?.exercises.length),
    );
    return exerciseCount == null
        ? const _StartWorkoutButton()
        : _ResumeWorkoutBanner(exerciseCount: exerciseCount);
  }
}

/// The tab's primary action. Deliberately a plain button, not the
/// dashboard's "Ready to train" hero: the same card on two neighbouring tabs
/// read as a copy, and here it pushed programs and history down the page.
class _StartWorkoutButton extends StatelessWidget {
  const _StartWorkoutButton();

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: () => context.pushNamed(Routes.activeWorkoutName),
        // The same plus as the dashboard's start button: one action, one
        // icon. Play is for resuming a session that already exists.
        icon: const Icon(Icons.add),
        label: Text(context.l10n.dashboardStartWorkout),
      );
}

/// The tab's primary action while a workout is open: the same filled
/// button as starting one, with play for resume.
///
/// It was a plain card, lighter than the "Start workout" button it
/// replaced, though an open workout is the most pressing thing on the
/// page. Its words were "Workout in progress" over "3 exercises logged ·
/// tap to resume"; a button says the action itself.
class _ResumeWorkoutBanner extends StatelessWidget {
  const _ResumeWorkoutBanner({required this.exerciseCount});

  final int exerciseCount;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return FilledButton.icon(
      onPressed: () => context.pushNamed(Routes.activeWorkoutName),
      icon: const Icon(Icons.play_arrow),
      label: Text(
        exerciseCount == 0
            ? l10n.dashboardResumeWorkout
            : l10n.trackerResumeWithCount(l10n.exerciseCount(exerciseCount)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
