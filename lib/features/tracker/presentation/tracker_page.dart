import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/daos/program_dao.dart';
import '../../../core/database/daos/workout_dao.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/database/tables/workouts.dart';
import '../../../core/error_reporting.dart';
import '../../../core/formatters/date_formatters.dart';
import '../../../core/formatters/unit_formatters.dart';
import '../../../core/formatters/week_start_controller.dart';
import '../../../core/formatters/weight_unit_controller.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/router/routes.dart';
import '../../../core/services/clock.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/page_body.dart';
import '../../../core/widgets/pr_badge.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/section_header.dart';
import '../../library/domain/exercise_catalogue_l10n.dart';
import '../../programs/domain/program_catalogue_l10n.dart';
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

enum _HistoryMenuAction { importXlsx }

enum _ProgramsMenuAction { importCsv }

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
              sliver: const SliverToBoxAdapter(child: _StartOrResume()),
            ),
            SliverPadding(
              padding: context.sliverGutter,
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: SectionHeader(
                        title: context.l10n.trackerPrograms,
                        // What a program is, for someone who has none. Once
                        // there are cards under the heading they say it
                        // themselves, and the sentence only wrapped onto a
                        // second line with one word on it.
                        // Only once the list is known to be empty: while it
                        // loads, or when it failed, there may be programs.
                        subtitle: programsAsync.hasValue &&
                                programsAsync.value!.isEmpty
                            ? context.l10n.trackerProgramsSubtitle
                            : null,
                        actionLabel: context.l10n.trackerNew,
                        onAction: () =>
                            context.pushNamed(Routes.programNewName),
                      ),
                    ),
                    // CSV import lived only in the no-programs card, which
                    // the seeded built-in programs mean almost nobody sees.
                    // Here it is always reachable; a menu, as in History,
                    // because it is rare next to "New".
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: PopupMenuButton<_ProgramsMenuAction>(
                        tooltip: context.l10n.trackerProgramOptions,
                        onSelected: (_ProgramsMenuAction action) =>
                            switch (action) {
                          _ProgramsMenuAction.importCsv =>
                            ProgramImportAction.run(context, ref),
                        },
                        itemBuilder: (BuildContext context) =>
                            <PopupMenuEntry<_ProgramsMenuAction>>[
                          PopupMenuItem<_ProgramsMenuAction>(
                            value: _ProgramsMenuAction.importCsv,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.upload_file_outlined),
                              title: Text(context.l10n.programImportTooltip),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                        child: _ProgramStrip(
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
                          // A rare, one-off import; it does not need the
                          // section's only visible action.
                          PopupMenuButton<_HistoryMenuAction>(
                            tooltip: context.l10n.trackerHistoryOptions,
                            onSelected: (_HistoryMenuAction action) =>
                                switch (action) {
                              _HistoryMenuAction.importXlsx =>
                                WorkoutXlsxImportAction.run(context, ref),
                            },
                            itemBuilder: (BuildContext context) =>
                                <PopupMenuEntry<_HistoryMenuAction>>[
                              PopupMenuItem<_HistoryMenuAction>(
                                value: _HistoryMenuAction.importXlsx,
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.table_view_outlined,
                                  ),
                                  title: Text(context.l10n.importXlsxAction),
                                ),
                              ),
                            ],
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
            builder: (_) => _DayWorkoutsSheet(date: date, workouts: onDay),
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

/// Size of one card in [_ProgramStrip], before the text scale is applied.
const double _programCardWidth = 168;
const double _programCardHeight = 88;

/// The programs as one row of cards that scrolls sideways.
///
/// They were a column of full-width cards. Three of them, the number the
/// app ships with, took most of the first screen and left the history, the
/// reason this tab is opened, two-thirds of the way down; every program
/// added pushed it further. A row has the same height for three programs or
/// thirty.
class _ProgramStrip extends StatelessWidget {
  const _ProgramStrip({required this.programs, required this.onOpen});

  final List<ProgramSummary> programs;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    // Follows the system text size, so two lines of a name still fit.
    final double cardHeight =
        MediaQuery.textScalerOf(context).scale(_programCardHeight);
    return SizedBox(
      // Room above and below for the card's shadow, which the list clips.
      height: cardHeight + AppSpacing.xs * 2,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // The first card lines up with the page; the rest run to the edge
        // of the screen, which is what shows there are more.
        padding: EdgeInsets.symmetric(
          horizontal: context.pageGutter,
          vertical: AppSpacing.xs,
        ),
        itemCount: programs.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final ProgramSummary summary = programs[index];
          return SizedBox(
            width: _programCardWidth,
            child: _ProgramTile(
              name: summary.program.displayName(context),
              dayCount: summary.dayCount,
              onTap: () => onOpen(summary.program.id),
            ),
          );
        },
      ),
    );
  }
}

class _ProgramTile extends StatelessWidget {
  const _ProgramTile({
    required this.name,
    required this.dayCount,
    required this.onTap,
  });

  final String name;
  final int dayCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      semanticLabel: context.l10n.trackerProgramSemantic(
        name,
        context.l10n.dayCount(dayCount),
      ),
      // The name, and how many days it has. The built-in descriptions only
      // repeated the name ("Full Body" over "Full body · 3 days/week"); a
      // program's own description is on its page.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            name,
            style: theme.textTheme.titleSmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Row(
            children: <Widget>[
              Icon(
                Icons.event_note_outlined,
                size: AppSpacing.lg,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  context.l10n.dayCount(dayCount),
                  style: AppTypography.caption(theme),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
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

/// One line of the history list: a month heading or a workout row.
sealed class _HistoryEntry {
  const _HistoryEntry();
}

final class _MonthEntry extends _HistoryEntry {
  const _MonthEntry(this.month, this.workoutCount, this.volumeKg);

  final DateTime month;
  final int workoutCount;
  final double volumeKg;
}

final class _WorkoutEntry extends _HistoryEntry {
  const _WorkoutEntry(this.workout, {required this.firstInMonth});

  final Workout workout;
  final bool firstInMonth;
}

class _HistorySliverList extends ConsumerWidget {
  const _HistorySliverList(
      {required this.workouts, required this.prWorkoutIds});

  final List<Workout> workouts;
  final Set<String> prWorkoutIds;

  /// Groups the newest-first list by month. One heading per month replaced
  /// a heading above every row: with about one workout a day, half the list
  /// was headings, and the day now lives in each row's date tile.
  static List<_HistoryEntry> _group(List<Workout> workouts) {
    final List<_HistoryEntry> entries = <_HistoryEntry>[];
    int start = 0;
    while (start < workouts.length) {
      final DateTime first = workouts[start].startedAt;
      int end = start;
      double volume = 0;
      while (end < workouts.length &&
          workouts[end].startedAt.year == first.year &&
          workouts[end].startedAt.month == first.month) {
        volume += workouts[end].totalVolumeKg;
        end++;
      }
      entries.add(
        _MonthEntry(DateTime(first.year, first.month), end - start, volume),
      );
      for (int i = start; i < end; i++) {
        entries.add(_WorkoutEntry(workouts[i], firstInMonth: i == start));
      }
      start = end;
    }
    return entries;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One query for every row's exercise names (see
    // WorkoutDao.watchExerciseNamesByWorkout); empty while it loads, when
    // rows fall back to their start time.
    final Map<String, List<WorkoutExerciseName>> namesByWorkout =
        ref.watch(workoutExerciseNamesProvider).value ?? const {};
    final Map<String, String> slugsById = ref.watch(exerciseSlugsByIdProvider);
    final List<_HistoryEntry> entries = _group(workouts);

    return SliverList.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) => switch (entries[index]) {
        _MonthEntry(:final month, :final workoutCount, :final volumeKg) =>
          _MonthHeader(
            month: month,
            workoutCount: workoutCount,
            volumeKg: volumeKg,
          ),
        _WorkoutEntry(:final workout, :final firstInMonth) => Column(
            children: [
              if (!firstInMonth)
                const Divider(indent: _dateTileWidth + AppSpacing.md),
              _WorkoutHistoryTile(
                workout: workout,
                isPersonalRecord: prWorkoutIds.contains(workout.id),
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
class _DayWorkoutsSheet extends ConsumerWidget {
  const _DayWorkoutsSheet({required this.date, required this.workouts});

  final DateTime date;
  final List<Workout> workouts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<String, List<WorkoutExerciseName>> namesByWorkout =
        ref.watch(workoutExerciseNamesProvider).value ?? const {};
    final Set<String> prWorkoutIds =
        ref.watch(personalRecordWorkoutIdsProvider).value ?? const <String>{};
    final Map<String, String> slugsById = ref.watch(exerciseSlugsByIdProvider);

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
            if (i > 0) const Divider(indent: _dateTileWidth + AppSpacing.md),
            _WorkoutHistoryTile(
              workout: workouts[i],
              isPersonalRecord: prWorkoutIds.contains(workouts[i].id),
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

/// Width of a history row's date tile; the row dividers are inset by it so
/// they start under the text, not under the tile.
const double _dateTileWidth = 52;

/// How many exercise names a row title spells out before "+N".
const int _titleExerciseLimit = 2;

class _WorkoutHistoryTile extends ConsumerWidget {
  const _WorkoutHistoryTile({
    required this.workout,
    required this.isPersonalRecord,
    required this.exerciseNames,
    this.onOpen,
  });

  final Workout workout;
  final bool isPersonalRecord;

  /// What a tap does; opening the workout's page when null. The day sheet
  /// passes its own, to close with the choice.
  final VoidCallback? onOpen;

  /// Localized, in logged order. Empty for a workout with no exercises.
  final List<String> exerciseNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = context.l10n;
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final DateFormatters dates = DateFormatters.of(context);
    final String time = dates.time(workout.startedAt);
    final String duration = workout.durationSeconds == null
        ? l10n.trackerNoDuration
        : UnitFormatters.durationShort(
            Duration(seconds: workout.durationSeconds!),
            context.l10n,
          );
    // Named by what was trained; the start time is secondary. The screen
    // reader hears every exercise; the visible title is fitted by
    // [_HistoryTitle].
    final String? title =
        exerciseNames.isEmpty ? null : exerciseNames.join(l10n.listSeparator);
    final String volumeText =
        UnitFormatters.volume(workout.totalVolumeKg, unit, context.l10n);
    final String summary = isPersonalRecord
        ? l10n.trackerWorkoutSemanticPr(
            dates.full(workout.startedAt),
            volumeText,
          )
        : l10n.trackerWorkoutSemantic(
            dates.full(workout.startedAt),
            volumeText,
          );
    // Watched, not read from the clock: the list outlives the day it was
    // built on, and yesterday's row must stop saying "today".
    final DateTime today = ref.watch(todayProvider);
    final bool isToday = workout.startedAt.year == today.year &&
        workout.startedAt.month == today.month &&
        workout.startedAt.day == today.day;

    return Semantics(
      label: title == null ? summary : '$title. $summary',
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onOpen ??
              () => context.pushNamed(
                    Routes.workoutDetailName,
                    pathParameters: {'id': workout.id},
                  ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: [
                _DateTile(date: workout.startedAt, isToday: isToday),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _HistoryTitle(names: exerciseNames, fallback: time),
                      const SizedBox(height: AppSpacing.xxs),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title == null ? duration : '$time · $duration',
                              style: AppTypography.caption(theme),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isPersonalRecord) ...[
                            const SizedBox(width: AppSpacing.sm),
                            const PrBadge(),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  volumeText,
                  style: AppTypography.cardMetric(
                    scheme,
                    size: AppTypography.metricSizeSm,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "+4": how many exercises a history row's title leaves out.
class _MoreExercisesPill extends StatelessWidget {
  const _MoreExercisesPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _padding,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(label, style: styleOf(theme)),
    );
  }

  static const double _padding = AppSpacing.sm;

  static TextStyle styleOf(ThemeData theme) => AppTypography.numeric(
        theme.textTheme.labelMedium!.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      );

  /// The pill's horizontal padding, for callers measuring its width.
  static double get horizontalPadding => _padding * 2;
}

/// A history row's title: up to two exercise names, then a "+N" pill for
/// the rest. Measured before it is laid out, so when two names do not fit
/// beside the pill the second is dropped and counted, rather than being
/// cut mid-word ("Back Squat, Overhead P...").
class _HistoryTitle extends StatelessWidget {
  const _HistoryTitle({required this.names, required this.fallback});

  /// Localized, in logged order.
  final List<String> names;

  /// Shown when the workout has no exercises.
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle style = theme.textTheme.titleSmall!;
    if (names.isEmpty) {
      return Text(
        fallback,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final AppLocalizations l10n = context.l10n;
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final TextDirection direction = Directionality.of(context);

    double widthOf(String text, TextStyle textStyle) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final double width = painter.width;
      painter.dispose();
      return width;
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        double pillWidth(int extra) => extra == 0
            ? 0
            : widthOf(
                  l10n.trackerMoreExercises(extra),
                  _MoreExercisesPill.styleOf(theme),
                ) +
                _MoreExercisesPill.horizontalPadding +
                AppSpacing.xs;

        int shown = names.length < _titleExerciseLimit
            ? names.length
            : _titleExerciseLimit;
        while (shown > 1 &&
            widthOf(names.take(shown).join(l10n.listSeparator), style) +
                    pillWidth(names.length - shown) >
                constraints.maxWidth) {
          shown--;
        }
        final int extra = names.length - shown;
        // At the largest text sizes the volume beside this title leaves it
        // a sliver, narrower than the pill alone. The pill is dropped then
        // rather than drawn off the row; the row's spoken label still
        // names every exercise.
        final bool pillFits =
            extra > 0 && pillWidth(extra) <= constraints.maxWidth;

        return Row(
          children: [
            Flexible(
              child: Text(
                names.take(shown).join(l10n.listSeparator),
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (pillFits) ...[
              const SizedBox(width: AppSpacing.xs),
              _MoreExercisesPill(label: l10n.trackerMoreExercises(extra)),
            ],
          ],
        );
      },
    );
  }
}

/// Day number over a short weekday: the row's visual anchor, and what used
/// to be a heading above it. Today's tile takes the accent.
class _DateTile extends StatelessWidget {
  const _DateTile({required this.date, required this.isToday});

  final DateTime date;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DateFormatters dates = DateFormatters.of(context);
    final Color ink = isToday ? scheme.primary : scheme.onSurface;

    // The row's semantics label already carries the full date.
    return ExcludeSemantics(
      child: Container(
        width: _dateTileWidth,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isToday
              ? scheme.primary.withValues(alpha: 0.16)
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              dates.dayOfMonth(date),
              style: AppTypography.cardMetric(
                scheme,
                size: AppTypography.metricSizeMd,
              ).copyWith(color: ink, height: 1),
            ),
            const SizedBox(height: AppSpacing.xxs),
            // Arabic has no short weekday names, so the label scales down
            // rather than overflowing the tile.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                dates.weekdayShort(date).toUpperCase(),
                maxLines: 1,
                style: AppTypography.eyebrow(
                  theme,
                  color: isToday ? scheme.primary : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
