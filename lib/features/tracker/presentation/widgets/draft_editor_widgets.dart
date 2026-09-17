import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/formatters/unit_formatters.dart';
import '../../../../core/formatters/weight_unit_controller.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../library/domain/exercise_catalogue_l10n.dart';
import '../../../timer/domain/timer_engine.dart';
import '../../../timer/domain/timer_preset.dart';
import '../../domain/draft_editor_controller.dart';
import '../../domain/workout_draft.dart';

/// Largest weight, in kilograms, a set row will accept. Guards against a
/// fat-fingered entry silently poisoning volume totals.
const double _maxWeightKg = 1000;
const int _maxReps = 100;

/// Longest hold, in seconds, a time-based set row will accept (30 minutes).
const int _maxDurationSeconds = 1800;

/// One exercise within a draft, with its sets. Shared by the active-session
/// screen and the edit screen — both back it with a [DraftEditorController].
///
/// Laid out as a small table: a header row names the columns once, so the
/// set rows below carry no per-field labels and stay scannable mid-set.
class ExerciseDraftCard extends ConsumerWidget {
  const ExerciseDraftCard({
    required this.exercise,
    required this.controller,
    this.position,
    this.dragHandleIndex,
    this.supersetLabel,
    this.isInSuperset = false,
    this.canGroupWithPrevious = false,
    super.key,
  });

  final DraftExercise exercise;
  final DraftEditorController controller;

  /// 1-based index shown in the leading chip. Null hides the chip.
  final int? position;

  /// 0-based index within the enclosing reorderable list. Non-null renders
  /// an explicit drag handle — preferred over a whole-card long-press,
  /// which is invisible to a screen reader and easy to trigger by accident
  /// while reaching for a set field.
  final int? dragHandleIndex;

  /// Letter ("A", "B", …) shown in the leading chip instead of [position]
  /// when this exercise is part of a superset.
  final String? supersetLabel;

  /// Whether this exercise is currently part of a superset.
  final bool isInSuperset;

  /// Whether "group with above" is available (there is an exercise above and
  /// this one isn't already grouped with it).
  final bool canGroupWithPrevious;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final String displayName = localizedExerciseName(
      context,
      ref.watch(exerciseSlugsByIdProvider),
      exercise.exerciseId,
      exercise.name,
    );

    final int completed =
        exercise.sets.where((DraftSet s) => s.isCompleted).length;
    // Working volume only. Must use the same rule as
    // `ActiveWorkoutNotifier.save`, which excludes warm-ups from the
    // persisted `totalVolumeKg` — otherwise this figure and the saved
    // workout's disagree for anyone who logs warm-up sets.
    final double volumeKg = exercise.sets
        .where(
            (DraftSet s) => s.isCompleted && !s.isWarmup && !exercise.isWarmup)
        .fold<double>(0, (double t, DraftSet s) => t + s.weightKg * s.reps);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                if (position != null || supersetLabel != null) ...<Widget>[
                  _PositionChip(label: supersetLabel ?? '$position'),
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        displayName,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (isInSuperset) ...<Widget>[
                        const SizedBox(height: AppSpacing.xxs),
                        _SupersetTag(label: context.l10n.draftSuperset),
                      ],
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        _summary(
                          context.l10n,
                          completed,
                          exercise.sets.length,
                          volumeKg,
                          unit,
                        ),
                        style: AppTypography.caption(theme),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<_DraftCardAction>(
                  tooltip: context.l10n.draftExerciseOptions(displayName),
                  icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
                  onSelected: (_DraftCardAction action) => switch (action) {
                    _DraftCardAction.groupWithAbove =>
                      controller.groupWithPrevious(exercise.id),
                    _DraftCardAction.ungroup =>
                      controller.ungroupFromSuperset(exercise.id),
                  },
                  itemBuilder: (_) => <PopupMenuEntry<_DraftCardAction>>[
                    PopupMenuItem<_DraftCardAction>(
                      value: _DraftCardAction.groupWithAbove,
                      enabled: canGroupWithPrevious,
                      child: ListTile(
                        leading: const Icon(Icons.vertical_align_top),
                        title: Text(context.l10n.draftGroupWithAbove),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem<_DraftCardAction>(
                      value: _DraftCardAction.ungroup,
                      enabled: isInSuperset,
                      child: ListTile(
                        leading: const Icon(Icons.vertical_align_center),
                        title: Text(context.l10n.draftUngroup),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => controller.removeExercise(exercise.id),
                  icon: const Icon(Icons.close),
                  tooltip: context.l10n.draftRemoveExercise(displayName),
                  visualDensity: VisualDensity.compact,
                ),
                if (dragHandleIndex != null)
                  ReorderableDragStartListener(
                    index: dragHandleIndex!,
                    child: Tooltip(
                      message: context.l10n.draftReorderExercise(displayName),
                      child: Icon(
                        Icons.drag_indicator,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            if (exercise.sets.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _SetTableHeader(unit: unit, isTimeBased: exercise.isTimeBased),
              const SizedBox(height: AppSpacing.xs),
              for (int i = 0; i < exercise.sets.length; i++)
                DraftSetRow(
                  key: ValueKey<String>(exercise.sets[i].id),
                  exerciseId: exercise.id,
                  set: exercise.sets[i],
                  index: i + 1,
                  controller: controller,
                  isTimeBased: exercise.isTimeBased,
                ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => controller.addSet(exercise.id),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(context.l10n.draftAddSet),
                  ),
                ),
                Container(
                  width: 1,
                  height: AppSpacing.xl,
                  color: scheme.outlineVariant,
                ),
                const Expanded(child: InlineRestTimer()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _summary(
    AppLocalizations l10n,
    int completed,
    int total,
    double volumeKg,
    WeightUnit unit,
  ) {
    if (total == 0) {
      return l10n.draftNoSetsYet;
    }
    final String sets = l10n.draftSetsProgress(completed, total);
    return completed == 0
        ? sets
        : '$sets · ${UnitFormatters.volume(volumeKg, unit)}';
  }
}

/// The exercise's ordinal (or superset letter) within the workout.
class _PositionChip extends StatelessWidget {
  const _PositionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return ExcludeSemantics(
      child: Container(
        width: AppSpacing.xl,
        height: AppSpacing.xl,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// A small uppercase pill marking a superset member.
class _SupersetTag extends StatelessWidget {
  const _SupersetTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// Actions on the overflow menu of an exercise card.
enum _DraftCardAction { groupWithAbove, ungroup }

/// Names the set-row columns once, so each row can drop its field labels.
class _SetTableHeader extends StatelessWidget {
  const _SetTableHeader({required this.unit, required this.isTimeBased});

  final WeightUnit unit;
  final bool isTimeBased;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    Widget label(String text, {TextAlign align = TextAlign.start}) => Text(
          text,
          textAlign: align,
          style: AppTypography.eyebrow(theme),
        );

    return ExcludeSemantics(
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _setNumberWidth,
            child: label(context.l10n.draftColumnSet),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: label(unit.label.toUpperCase())),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: label(
              isTimeBased
                  ? context.l10n.draftColumnDuration
                  : context.l10n.draftColumnReps,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: AppSpacing.minTapTarget,
            child: label(
              context.l10n.draftColumnDone,
              align: TextAlign.center,
            ),
          ),
          const SizedBox(width: _rowMenuWidth),
        ],
      ),
    );
  }
}

/// Column widths shared by the header and the rows so they stay aligned.
const double _setNumberWidth = AppSpacing.xxl;
const double _rowMenuWidth = AppSpacing.minTapTarget;

/// A compact, local rest countdown.
///
/// It reuses the platform-independent [TimerEngine] but deliberately does not
/// create a saved timer session or use notifications, audio, or wakelock.
///
/// Rendered once per exercise rather than between every pair of sets: the
/// old placement repeated an identical control up to a dozen times per card
/// and made the set list hard to read.
class InlineRestTimer extends StatefulWidget {
  const InlineRestTimer({this.duration = 60, super.key});

  final int duration;

  @override
  State<InlineRestTimer> createState() => _InlineRestTimerState();
}

class _InlineRestTimerState extends State<InlineRestTimer> {
  TimerEngine? _engine;
  Timer? _ticker;
  TimerSnapshot? _snapshot;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TimerSnapshot? snapshot = _snapshot;
    final bool running = snapshot?.isRunning ?? false;
    final bool complete = snapshot?.isComplete ?? false;

    if (snapshot == null) {
      return TextButton.icon(
        onPressed: _start,
        icon: const Icon(Icons.timer_outlined, size: 18),
        label: Text(context.l10n.draftRest),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Flexible(
          child: Text(
            complete
                ? context.l10n.actionDone
                : UnitFormatters.duration(snapshot.remaining),
            style: AppTypography.cardMetric(
              scheme,
              size: AppTypography.metricSizeSm,
            ).copyWith(color: complete ? scheme.primary : scheme.onSurface),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!complete)
          IconButton(
            onPressed: running ? _pause : _resume,
            icon: Icon(running ? Icons.pause : Icons.play_arrow),
            tooltip: running
                ? context.l10n.draftPauseRest
                : context.l10n.draftResumeRest,
            visualDensity: VisualDensity.compact,
          ),
        IconButton(
          onPressed: complete ? _start : _reset,
          icon: Icon(complete ? Icons.refresh : Icons.stop),
          tooltip: complete
              ? context.l10n.draftRestartRest
              : context.l10n.draftStopRest,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  void _start() {
    _ticker?.cancel();
    _engine = TimerEngine(
      phases: <TimerPhase>[
        TimerPhase(type: TimerPhaseType.rest, durationSeconds: widget.duration),
      ],
    )..start();
    _tick();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  void _pause() {
    _engine?.pause();
    _tick();
  }

  void _resume() {
    _engine?.resume();
    _tick();
  }

  void _reset() {
    _ticker?.cancel();
    _ticker = null;
    setState(() {
      _engine = null;
      _snapshot = null;
    });
  }

  void _tick() {
    final TimerEngine? engine = _engine;
    if (engine == null || !mounted) return;
    final TimerSnapshot snapshot = engine.snapshot();
    if (snapshot.isComplete) {
      _ticker?.cancel();
      _ticker = null;
    }
    setState(() => _snapshot = snapshot);
  }
}

/// A single set row. Owns and disposes its own controllers (ADR-5) and
/// pushes changes up to whichever [DraftEditorController] it was given.
///
/// Weights are entered in the user's display unit and converted to
/// kilograms here — ADR-1's boundary. A pound value never reaches the
/// controller.
class DraftSetRow extends ConsumerStatefulWidget {
  const DraftSetRow({
    required this.exerciseId,
    required this.set,
    required this.index,
    required this.controller,
    this.isTimeBased = false,
    super.key,
  });

  final String exerciseId;
  final DraftSet set;

  /// 1-based position within the exercise, shown in the leading column and
  /// used in the row's semantic labels.
  final int index;
  final DraftEditorController controller;

  /// Whether this row logs a held duration instead of reps.
  final bool isTimeBased;

  @override
  ConsumerState<DraftSetRow> createState() => _DraftSetRowState();
}

class _DraftSetRowState extends ConsumerState<DraftSetRow> {
  late final TextEditingController _weightController;
  late final TextEditingController _repsController;
  late final TextEditingController _durationController;

  /// The unit the text field currently holds a value in. When the user
  /// switches kg/lb mid-workout the displayed number has to be rewritten,
  /// otherwise a 100 entered as kg would silently be re-read as 100 lb.
  WeightUnit? _renderedUnit;
  Timer? _weightDebounce;
  Timer? _repsDebounce;
  Timer? _durationDebounce;

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController();
    _repsController = TextEditingController(text: _repsText(widget.set.reps));
    _durationController =
        TextEditingController(text: _durationText(widget.set.durationSeconds));
  }

  @override
  void didUpdateWidget(covariant DraftSetRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.set.id != widget.set.id) return;
    _sync(_weightController, _weightText(widget.set.weightKg, _renderedUnit));
    _sync(_repsController, _repsText(widget.set.reps));
    _sync(_durationController, _durationText(widget.set.durationSeconds));
  }

  @override
  void dispose() {
    _weightDebounce?.cancel();
    _repsDebounce?.cancel();
    _durationDebounce?.cancel();
    _weightController.dispose();
    _repsController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    if (_renderedUnit != unit) {
      _renderedUnit = unit;
      _weightController.text = _weightText(widget.set.weightKg, unit);
    }

    final bool done = widget.set.isCompleted;
    final int index = widget.index;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _setNumberWidth,
            child: Text(
              '$index',
              style: AppTypography.numeric(
                theme.textTheme.titleSmall ?? const TextStyle(),
              ).copyWith(
                color: done ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _NumberField(
              controller: _weightController,
              semanticLabel:
                  context.l10n.draftSetWeightSemantic(index, unit.label),
              decimal: true,
              onChanged: (String value) {
                final double? entered = double.tryParse(value);
                if (entered == null || !entered.isFinite || entered < 0) {
                  _weightDebounce?.cancel();
                  return;
                }
                final double kg = UnitFormatters.toKg(entered, unit);
                if (kg > _maxWeightKg) {
                  _weightDebounce?.cancel();
                  return;
                }
                _weightDebounce?.cancel();
                _weightDebounce = Timer(AppDuration.inputDebounce, () {
                  if (!mounted) return;
                  widget.controller.updateSet(
                    widget.exerciseId,
                    widget.set.id,
                    weightKg: kg,
                  );
                });
              },
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: widget.isTimeBased
                ? _NumberField(
                    controller: _durationController,
                    semanticLabel: context.l10n.draftSetDurationSemantic(index),
                    onChanged: (String value) {
                      final int? seconds = int.tryParse(value);
                      if (seconds == null ||
                          seconds < 0 ||
                          seconds > _maxDurationSeconds) {
                        _durationDebounce?.cancel();
                        return;
                      }
                      _durationDebounce?.cancel();
                      _durationDebounce = Timer(AppDuration.inputDebounce, () {
                        if (!mounted) return;
                        widget.controller.updateSet(
                          widget.exerciseId,
                          widget.set.id,
                          durationSeconds: seconds,
                        );
                      });
                    },
                  )
                : _NumberField(
                    controller: _repsController,
                    semanticLabel: context.l10n.draftSetRepsSemantic(index),
                    onChanged: (String value) {
                      final int? reps = int.tryParse(value);
                      if (reps == null || reps < 0 || reps > _maxReps) {
                        _repsDebounce?.cancel();
                        return;
                      }
                      _repsDebounce?.cancel();
                      _repsDebounce = Timer(AppDuration.inputDebounce, () {
                        if (!mounted) return;
                        widget.controller.updateSet(
                          widget.exerciseId,
                          widget.set.id,
                          reps: reps,
                        );
                      });
                    },
                  ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _SetDoneButton(
            done: done,
            index: index,
            onChanged: (bool value) => widget.controller.updateSet(
              widget.exerciseId,
              widget.set.id,
              isCompleted: value,
            ),
          ),
          SizedBox(
            width: _rowMenuWidth,
            child: PopupMenuButton<_SetAction>(
              tooltip: context.l10n.draftSetOptionsSemantic(index),
              icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
              padding: EdgeInsets.zero,
              onSelected: (_SetAction action) => switch (action) {
                _SetAction.details => _showSetDetails(),
                _SetAction.duplicate => widget.controller
                    .duplicateSet(widget.exerciseId, widget.set.id),
                _SetAction.remove =>
                  widget.controller.removeSet(widget.exerciseId, widget.set.id),
              },
              itemBuilder: (_) => <PopupMenuEntry<_SetAction>>[
                PopupMenuItem<_SetAction>(
                  value: _SetAction.details,
                  child: ListTile(
                    leading: const Icon(Icons.speed_outlined),
                    title: Text(context.l10n.draftRpeAndRest),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem<_SetAction>(
                  value: _SetAction.duplicate,
                  child: ListTile(
                    leading: const Icon(Icons.copy_outlined),
                    title: Text(context.l10n.draftDuplicateSet),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem<_SetAction>(
                  value: _SetAction.remove,
                  child: ListTile(
                    leading: const Icon(Icons.remove_circle_outline),
                    title: Text(context.l10n.draftRemoveSet),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSetDetails() async {
    final rpeController = TextEditingController(
      text: widget.set.rpeTimes10 == null
          ? ''
          : (widget.set.rpeTimes10! / 10).toStringAsFixed(1),
    );
    final restController = TextEditingController(
      text: widget.set.restSeconds?.toString() ?? '',
    );
    try {
      final result = await showDialog<(int?, int?)>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.draftSetDetailsTitle(widget.index)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: rpeController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    InputDecoration(labelText: context.l10n.draftRpeField),
              ),
              TextField(
                controller: restController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: context.l10n.draftRestBeforeSetField),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.actionCancel)),
            FilledButton(
              onPressed: () {
                final rpe = double.tryParse(rpeController.text);
                final rest = int.tryParse(restController.text);
                if ((rpe != null && (rpe < 1 || rpe > 10)) ||
                    (rest != null && (rest < 0 || rest > 3600))) {
                  return;
                }
                Navigator.pop(context, (
                  rpe == null ? null : (rpe * 10).round(),
                  rest,
                ));
              },
              child: Text(context.l10n.actionSave),
            ),
          ],
        ),
      );
      if (!mounted || result == null) return;
      await widget.controller.updateSet(
        widget.exerciseId,
        widget.set.id,
        rpeTimes10: result.$1,
        restSeconds: result.$2,
      );
    } finally {
      rpeController.dispose();
      restController.dispose();
    }
  }

  void _sync(TextEditingController controller, String value) {
    if (controller.text != value && !controller.selection.isValid) {
      controller.text = value;
    }
  }

  static String _repsText(int reps) => reps == 0 ? '' : '$reps';

  static String _durationText(int? seconds) =>
      seconds == null || seconds == 0 ? '' : '$seconds';

  static String _weightText(double kg, WeightUnit? unit) {
    if (kg == 0) return '';
    final double display = unit == null ? kg : UnitFormatters.fromKg(kg, unit);
    return UnitFormatters.plain(display);
  }
}

enum _SetAction { details, duplicate, remove }

/// Bare numeric field sized for a table cell.
///
/// Labels live in the column header, so the field itself carries only a
/// semantic label for screen readers.
class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.semanticLabel,
    required this.onChanged,
    this.decimal = false,
  });

  final TextEditingController controller;
  final String semanticLabel;
  final ValueChanged<String> onChanged;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // The visible label is the column header, so the field carries the
    // full description for screen readers instead. Semantics merges into
    // the field's own node rather than replacing it, which keeps the
    // editing actions intact.
    return Semantics(
      label: semanticLabel,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        textAlign: TextAlign.center,
        style: AppTypography.numeric(
          theme.textTheme.titleMedium ?? const TextStyle(),
        ),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(
            decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
          ),
        ],
        decoration: const InputDecoration(
          hintText: '0',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// Large, unmistakable "set complete" toggle.
///
/// The primary interaction on this screen, so it gets a full tap target and
/// signals state with a fill *and* an icon — never colour alone.
class _SetDoneButton extends StatelessWidget {
  const _SetDoneButton({
    required this.done,
    required this.index,
    required this.onChanged,
  });

  final bool done;
  final int index;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    // State is carried by the fill, not by hue alone: an unlogged set is a
    // hollow tonal square, a logged one is a solid primary square.
    return Semantics(
      label: context.l10n.draftSetCompleteSemantic(index),
      toggled: done,
      container: true,
      child: Material(
        color: done ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: () => onChanged(!done),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: SizedBox(
            width: AppSpacing.minTapTarget,
            height: AppSpacing.minTapTarget,
            child: Icon(
              Icons.check,
              size: 20,
              color: done ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
