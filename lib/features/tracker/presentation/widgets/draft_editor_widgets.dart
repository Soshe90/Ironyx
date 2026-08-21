import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../timer/domain/timer_engine.dart';
import '../../../timer/domain/timer_preset.dart';
import '../../domain/draft_editor_controller.dart';
import '../../domain/workout_draft.dart';

/// One exercise within a draft, with its sets. Shared by the active-session
/// screen and the edit screen — both back it with a [DraftEditorController].
class ExerciseDraftCard extends StatelessWidget {
  const ExerciseDraftCard({
    required this.exercise,
    required this.controller,
    super.key,
  });

  final DraftExercise exercise;
  final DraftEditorController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    exercise.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: () => controller.removeExercise(exercise.id),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove exercise',
                ),
              ],
            ),
            for (var index = 0; index < exercise.sets.length; index++) ...[
              DraftSetRow(
                key: ValueKey(exercise.sets[index].id),
                exerciseId: exercise.id,
                set: exercise.sets[index],
                controller: controller,
              ),
              if (index < exercise.sets.length - 1) const InlineRestTimer(),
            ],
            TextButton.icon(
              onPressed: () => controller.addSet(exercise.id),
              icon: const Icon(Icons.add),
              label: const Text('Add set'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact, local rest countdown shown between set rows.
///
/// It reuses the platform-independent [TimerEngine] but deliberately does not
/// create a saved timer session or use notifications, audio, or wakelock.
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
    final snapshot = _snapshot;
    final running = snapshot?.isRunning ?? false;
    final complete = snapshot?.isComplete ?? false;
    final label = snapshot == null
        ? 'Rest'
        : complete
            ? 'Rest complete'
            : _format(snapshot.remaining);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Text(label),
          const Spacer(),
          if (snapshot != null && !complete)
            IconButton(
              onPressed: running ? _pause : _resume,
              icon: Icon(running ? Icons.pause : Icons.play_arrow),
              tooltip: running ? 'Pause rest' : 'Resume rest',
              visualDensity: VisualDensity.compact,
            ),
          TextButton(
            onPressed: complete || snapshot == null ? _start : _reset,
            child: Text(snapshot == null || complete ? 'Start' : 'Reset'),
          ),
        ],
      ),
    );
  }

  void _start() {
    _ticker?.cancel();
    _engine = TimerEngine(
      phases: [
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
    final engine = _engine;
    if (engine == null || !mounted) return;
    final snapshot = engine.snapshot();
    if (snapshot.isComplete) {
      _ticker?.cancel();
      _ticker = null;
    }
    setState(() => _snapshot = snapshot);
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// A single set row. Owns and disposes its own controllers (ADR-5) and
/// pushes changes up to whichever [DraftEditorController] it was given.
class DraftSetRow extends StatefulWidget {
  const DraftSetRow({
    required this.exerciseId,
    required this.set,
    required this.controller,
    super.key,
  });

  final String exerciseId;
  final DraftSet set;
  final DraftEditorController controller;

  @override
  State<DraftSetRow> createState() => _DraftSetRowState();
}

class _DraftSetRowState extends State<DraftSetRow> {
  late final TextEditingController _weightController;
  late final TextEditingController _repsController;

  @override
  void initState() {
    super.initState();
    _weightController =
        TextEditingController(text: _format(widget.set.weightKg));
    _repsController = TextEditingController(text: '${widget.set.reps}');
  }

  @override
  void didUpdateWidget(covariant DraftSetRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.set.id != widget.set.id) return;
    _sync(_weightController, _format(widget.set.weightKg));
    _sync(_repsController, '${widget.set.reps}');
  }

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 86,
          child: TextField(
            controller: _weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'kg'),
            onChanged: (value) {
              final weight = double.tryParse(value);
              if (weight != null &&
                  weight.isFinite &&
                  weight >= 0 &&
                  weight <= 1000) {
                widget.controller.updateSet(
                  widget.exerciseId,
                  widget.set.id,
                  weightKg: weight,
                );
              }
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 70,
          child: TextField(
            controller: _repsController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'reps'),
            onChanged: (value) {
              final reps = int.tryParse(value);
              if (reps != null && reps >= 0 && reps <= 100) {
                widget.controller.updateSet(
                  widget.exerciseId,
                  widget.set.id,
                  reps: reps,
                );
              }
            },
          ),
        ),
        Checkbox(
          value: widget.set.isCompleted,
          onChanged: (value) => widget.controller.updateSet(
            widget.exerciseId,
            widget.set.id,
            isCompleted: value ?? false,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy_outlined),
          tooltip: 'Duplicate set',
          onPressed: () =>
              widget.controller.duplicateSet(widget.exerciseId, widget.set.id),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: 'Remove set',
          onPressed: () =>
              widget.controller.removeSet(widget.exerciseId, widget.set.id),
        ),
      ],
    );
  }

  void _sync(TextEditingController controller, String value) {
    if (controller.text != value && !controller.selection.isValid) {
      controller.text = value;
    }
  }

  String _format(double value) => value == 0 ? '' : value.toString();
}
