import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/tables/exercises.dart';
import '../../../core/formatters/unit_formatters.dart';
import '../../../core/formatters/weight_unit_controller.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_body.dart';
import '../../../core/widgets/stat_strip.dart';
import '../../../core/widgets/sticky_action_bar.dart';
import '../../library/presentation/exercise_picker_sheet.dart';
import '../domain/active_workout_notifier.dart';
import '../domain/workout_draft.dart';
import 'widgets/draft_editor_widgets.dart';

/// Root-level active-workout session (ADR-3): the bottom bar is hidden here
/// by design, so a mistaken tap on another tab mid-set can't happen.
///
/// Optimised for use mid-set: the running clock and session totals stay
/// pinned at the top, and "Finish" lives in a fixed bottom bar rather than
/// at the end of the scroll, so neither is more than one tap away no matter
/// how many exercises have been logged.
class ActiveWorkoutPage extends ConsumerStatefulWidget {
  const ActiveWorkoutPage({super.key});

  @override
  ConsumerState<ActiveWorkoutPage> createState() => _ActiveWorkoutPageState();
}

class _ActiveWorkoutPageState extends ConsumerState<ActiveWorkoutPage> {
  @override
  void initState() {
    super.initState();
    // Riverpod forbids modifying a provider mid-build (initState counts),
    // so the first mutation is deferred to right after this frame.
    Future.microtask(() {
      if (!mounted) return;
      final notifier = ref.read(activeWorkoutProvider.notifier);
      if (ref.read(activeWorkoutProvider) == null) {
        // Reached directly (e.g. from the Dashboard banner) without a draft.
        unawaited(notifier.start());
      } else {
        // Resumed while a discard-undo window was still open.
        notifier.cancelScheduledDiscard();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final WorkoutDraft? draft = ref.watch(activeWorkoutProvider);
    final ActiveWorkoutNotifier notifier =
        ref.read(activeWorkoutProvider.notifier);

    if (draft == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final bool hasExercises = draft.exercises.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => context.pop(),
        ),
        title: _SessionClock(startedAt: draft.startedAt),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Discard workout',
            onPressed: () => _confirmDiscard(context, notifier),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: PageBody(
          gutter: false,
          child: CustomScrollView(
            slivers: <Widget>[
              SliverPadding(
                padding: context.sliverGutter.copyWith(
                  top: AppSpacing.sm,
                  bottom: AppSpacing.lg,
                ),
                sliver: SliverToBoxAdapter(
                  child: _SessionTotals(draft: draft),
                ),
              ),
              if (!hasExercises)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.fitness_center_outlined,
                    title: 'Add your first exercise',
                    message: 'Pick a movement and start logging sets. Your '
                        'draft is saved as you go.',
                    actionLabel: 'Add exercise',
                    onAction: () => _addExercise(context, notifier),
                  ),
                )
              else
                SliverPadding(
                  padding: context.sliverGutter,
                  sliver: SliverReorderableList(
                    itemCount: draft.exercises.length,
                    onReorderItem: (int oldIndex, int newIndex) {
                      unawaited(notifier.reorderExercise(
                        draft.exercises[oldIndex].id,
                        newIndex,
                      ));
                    },
                    itemBuilder: (BuildContext context, int index) {
                      final DraftExercise exercise = draft.exercises[index];
                      return ExerciseDraftCard(
                        key: ValueKey<String>(exercise.id),
                        exercise: exercise,
                        controller: notifier,
                        position: index + 1,
                        dragHandleIndex: index,
                      );
                    },
                  ),
                ),
              if (hasExercises)
                SliverPadding(
                  padding: context.sliverGutter.copyWith(
                    bottom: AppSpacing.xl,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: OutlinedButton.icon(
                      onPressed: () => _addExercise(context, notifier),
                      icon: const Icon(Icons.add),
                      label: const Text('Add exercise'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: StickyActionBar(
        child: FilledButton.icon(
          onPressed: hasExercises ? () => _save(context, notifier) : null,
          icon: const Icon(Icons.check),
          label: const Text('Finish workout'),
        ),
      ),
    );
  }

  Future<void> _addExercise(
    BuildContext context,
    ActiveWorkoutNotifier notifier,
  ) async {
    final exercise = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ExercisePickerSheet(),
    );
    if (exercise != null) {
      await notifier.addExercise(exerciseId: exercise.id, name: exercise.name);
    }
  }

  Future<void> _save(
    BuildContext context,
    ActiveWorkoutNotifier notifier,
  ) async {
    try {
      await notifier.save();
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Workout saved')));
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save workout: $error')),
        );
      }
    }
  }

  Future<void> _confirmDiscard(
    BuildContext context,
    ActiveWorkoutNotifier notifier,
  ) async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard workout?'),
        content: const Text('Your current draft will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true || !context.mounted) return;

    notifier.scheduleDiscard();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    context.pop();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Workout discarded'),
        duration: AppDuration.undoWindow,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            notifier.cancelScheduledDiscard();
            router.pushNamed(Routes.activeWorkoutName);
          },
        ),
      ),
    );
  }
}

/// Running session duration, ticking once a second.
///
/// Tabular figures keep the title from shifting as the digits roll over.
class _SessionClock extends StatefulWidget {
  const _SessionClock({required this.startedAt});

  final DateTime startedAt;

  @override
  State<_SessionClock> createState() => _SessionClockState();
}

class _SessionClockState extends State<_SessionClock> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Duration elapsed =
        DateTime.now().toUtc().difference(widget.startedAt.toUtc());
    final String text =
        UnitFormatters.duration(elapsed.isNegative ? Duration.zero : elapsed);

    return Semantics(
      label: 'Elapsed time $text',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.fiber_manual_record,
              size: 10,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              text,
              style: AppTypography.numeric(
                theme.textTheme.titleLarge ?? const TextStyle(),
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live session totals. Answers "how much have I done so far" without the
/// user having to scroll back through the exercise list and add it up.
class _SessionTotals extends ConsumerWidget {
  const _SessionTotals({required this.draft});

  final WorkoutDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    int completedSets = 0;
    double volumeKg = 0;
    for (final DraftExercise exercise in draft.exercises) {
      for (final DraftSet set in exercise.sets) {
        if (!set.isCompleted) continue;
        completedSets++;
        volumeKg += set.weightKg * set.reps;
      }
    }

    return StatStrip(
      stats: <Stat>[
        Stat(
          label: 'Volume',
          value: UnitFormatters.volume(volumeKg, unit),
          emphasis: true,
        ),
        Stat(label: 'Sets', value: '$completedSets'),
        Stat(label: 'Exercises', value: '${draft.exercises.length}'),
      ],
    );
  }
}

