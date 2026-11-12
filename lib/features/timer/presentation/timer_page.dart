import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/error_reporting.dart';
import '../../../core/formatters/number_input.dart';
import '../../../core/formatters/unit_formatters.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/router/routes.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/page_body.dart';
import '../../../core/widgets/section_header.dart';
import '../domain/timer_controller.dart';
import '../domain/timer_preset.dart';
import 'timer_preset_labels.dart';

/// Timer hub (branch index 3). Quick-start presets, a custom builder, and
/// feedback toggles. Starting a session requests notification permission in
/// context, then pushes the full-screen active timer (ADR-3).
class TimerPage extends ConsumerWidget {
  const TimerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navTimer)),
      body: SafeArea(
        child: PageBody(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            children: [
              SectionHeader(
                title: l10n.timerQuickStartTitle,
                subtitle: l10n.timerQuickStartSubtitle,
              ),
              for (final TimerPreset preset in <TimerPreset>[
                TimerPresets.tabata(),
                TimerPresets.hiit(),
                TimerPresets.strength(),
              ])
                _PresetCard(
                  preset: preset,
                  onTap: () => startTimer(context, ref, preset),
                ),
              const SizedBox(height: AppSpacing.xl),
              // Personal presets follow quick start and stay hidden until
              // the user has saved one.
              const _SavedPresets(),
              SectionHeader(
                title: l10n.timerCustomTitle,
                subtitle: l10n.timerCustomSubtitle,
              ),
              _CustomBuilder(
                onStart: (preset) => startTimer(context, ref, preset),
                onSave: (preset) async {
                  final ScaffoldMessengerState messenger =
                      ScaffoldMessenger.of(context);
                  final AppLocalizations l10n = context.l10n;
                  try {
                    await ref.read(timerPresetDaoProvider).save(preset);
                  } on Object catch (error, stackTrace) {
                    // It escaped the tap handler, and the tap did nothing.
                    reportError(error, stackTrace, context: 'save preset');
                    messenger.showSnackBar(
                      SnackBar(content: Text(l10n.timerPresetSaveFailed)),
                    );
                    return;
                  }
                  ref.invalidate(savedTimerPresetsProvider);
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.timerPresetSaved)),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// True while [startTimer] is starting a session: from the first tap to
/// the timer screen opening.
bool _startingTimer = false;

/// Starts [preset] and opens the full-screen timer.
///
/// Permission is re-checked on every start (users revoke in system
/// settings) and requested in context if needed. A denial must never block
/// the timer (ADR-4) — it only costs the background notification.
///
/// Three guards, each for something that happened:
/// * A session already running (backgrounded, its screen closed) is
///   opened, not replaced. Starting again threw it away unsaved.
/// * A second tap while the first is still starting is ignored. The wait
///   on the permission let a double tap start two sessions and push two
///   timer screens.
/// * A failure shows a message and is logged; it escaped the tap handler,
///   and the tap did nothing.
Future<void> startTimer(
  BuildContext context,
  WidgetRef ref,
  TimerPreset preset,
) async {
  final TimerController controller = ref.read(timerControllerProvider.notifier);
  if (controller.isActive) {
    unawaited(context.pushNamed(Routes.activeTimerName));
    return;
  }
  if (_startingTimer) return;
  _startingTimer = true;
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final AppLocalizations l10n = context.l10n;
  try {
    final NotificationService notifications =
        ref.read(notificationServiceProvider);

    final bool alreadyGranted = await notifications.isPermissionGranted;
    final bool granted =
        alreadyGranted || await notifications.requestPermission();

    await controller.start(preset, notificationGranted: granted);
  } on Object catch (error, stackTrace) {
    reportError(error, stackTrace, context: 'start timer');
    messenger.showSnackBar(SnackBar(content: Text(l10n.timerStartFailed)));
    return;
  } finally {
    _startingTimer = false;
  }

  if (context.mounted) {
    unawaited(context.pushNamed(Routes.activeTimerName));
  }
}

class _SavedPresets extends ConsumerWidget {
  const _SavedPresets();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedTimerPresetsProvider);
    Widget section(Widget body) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SectionHeader(title: context.l10n.timerSavedPresets),
            body,
            const SizedBox(height: AppSpacing.xl),
          ],
        );

    return saved.when(
      data: (presets) => presets.isEmpty
          ? const SizedBox.shrink()
          : section(
              Column(
                children: [
                  for (final preset in presets)
                    _PresetCard(
                      preset: preset,
                      onTap: () => startTimer(context, ref, preset),
                      onDelete: () => _delete(context, ref, preset),
                    ),
                ],
              ),
            ),
      // Nothing until it resolves: a placeholder for a section that is
      // usually absent would flash and vanish.
      loading: () => const SizedBox.shrink(),
      error: (error, _) => section(
        AppCard(
          child: ErrorView(
            title: context.l10n.timerPresetsLoadFailed,
            details: error.toString(),
            compact: true,
            onRetry: () => ref.invalidate(savedTimerPresetsProvider),
          ),
        ),
      ),
    );
  }
}

/// Deletes a saved preset, with an undo that puts it back in its place.
///
/// There was no way to delete one: the DAO had `remove`, but no screen
/// called it, and saving the same values twice made a second copy.
Future<void> _delete(
  BuildContext context,
  WidgetRef ref,
  TimerPreset preset,
) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final AppLocalizations l10n = context.l10n;
  final dao = ref.read(timerPresetDaoProvider);
  final TimerPresetsTableData? row = await dao.take(preset.id);
  ref.invalidate(savedTimerPresetsProvider);
  if (row == null) return;
  // Replaces a message still showing (a "Preset saved." of a moment ago),
  // or the Undo would queue behind it and could expire unseen.
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(l10n.timerPresetDeleted),
      duration: AppDuration.undoWindow,
      // An action makes a snack bar persist by default; this one must go
      // when the undo window closes (as the discarded-workout one does).
      persist: false,
      action: SnackBarAction(
        label: l10n.actionUndo,
        onPressed: () async {
          await dao.restore(row);
          ref.invalidate(savedTimerPresetsProvider);
        },
      ),
    ),
  );
}

enum _PresetAction { delete }

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.preset, required this.onTap, this.onDelete});

  final TimerPreset preset;
  final VoidCallback onTap;

  /// Shown as a menu on saved presets; the built-in ones have none.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Duration total = Duration(seconds: preset.totalDurationSeconds);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        semanticLabel: context.l10n.timerPresetSemantic(
          preset.displayName(context.l10n),
          UnitFormatters.duration(total),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(
                Icons.timer_outlined,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    preset.displayName(context.l10n),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    preset.displayDescription(context.l10n),
                    style: AppTypography.caption(theme),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  UnitFormatters.duration(total),
                  style: AppTypography.cardMetric(
                    scheme,
                    size: AppTypography.metricSizeSm,
                  ).copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  context.l10n.intervalCount(preset.totalIntervals),
                  style: AppTypography.caption(theme),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.play_circle_rounded, color: scheme.primary, size: 28),
            if (onDelete != null)
              PopupMenuButton<_PresetAction>(
                tooltip: context.l10n.timerPresetOptions,
                onSelected: (_PresetAction action) => switch (action) {
                  _PresetAction.delete => onDelete!(),
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<_PresetAction>>[
                  PopupMenuItem<_PresetAction>(
                    value: _PresetAction.delete,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.delete_outline),
                      title: Text(context.l10n.actionDelete),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CustomBuilder extends ConsumerStatefulWidget {
  const _CustomBuilder({required this.onStart, required this.onSave});

  final ValueChanged<TimerPreset> onStart;
  final Future<void> Function(TimerPreset) onSave;

  @override
  ConsumerState<_CustomBuilder> createState() => _CustomBuilderState();
}

class _CustomBuilderState extends ConsumerState<_CustomBuilder> {
  final TextEditingController _work = TextEditingController(text: '30');
  final TextEditingController _rest = TextEditingController(text: '10');
  final TextEditingController _rounds = TextEditingController(text: '8');
  final TextEditingController _warmup = TextEditingController(text: '0');
  final TextEditingController _cooldown = TextEditingController(text: '0');

  /// Errors show under their fields once Start or Save has been pressed,
  /// then follow the typing; before that a half-typed value is not marked.
  bool _showErrors = false;

  List<TextEditingController> get _fields =>
      <TextEditingController>[_work, _rest, _rounds, _warmup, _cooldown];

  @override
  void initState() {
    super.initState();
    // The total and the errors follow every keystroke.
    for (final TextEditingController field in _fields) {
      field.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  int _read(TextEditingController field) => int.tryParse(field.text) ?? 0;

  /// What is wrong with [value] for a field whose least is [min] and most
  /// is [max], if anything.
  String? _rangeError(int value, {required int min, required int max}) {
    final AppLocalizations l10n = context.l10n;
    if (value < min) return l10n.timerFieldAtLeast(min);
    if (value > max) return l10n.timerFieldAtMost(max);
    return null;
  }

  String? get _workError =>
      _rangeError(_read(_work), min: 1, max: kMaxTimerPhaseSeconds);
  String? get _restError =>
      _rangeError(_read(_rest), min: 0, max: kMaxTimerPhaseSeconds);
  String? get _roundsError =>
      _rangeError(_read(_rounds), min: 1, max: kMaxTimerRounds);
  String? get _warmupError =>
      _rangeError(_read(_warmup), min: 0, max: kMaxTimerPhaseSeconds);
  String? get _cooldownError =>
      _rangeError(_read(_cooldown), min: 0, max: kMaxTimerPhaseSeconds);

  bool get _valid =>
      _workError == null &&
      _restError == null &&
      _roundsError == null &&
      _warmupError == null &&
      _cooldownError == null;

  @override
  void dispose() {
    _work.dispose();
    _rest.dispose();
    _rounds.dispose();
    _warmup.dispose();
    _cooldown.dispose();
    super.dispose();
  }

  /// The preset the fields describe, or null while one is out of range.
  /// The ranges are `checkCustomTimer`'s; rest may be 0, a work-only
  /// timer, which the engine always ran and the builder refused.
  TimerPreset? get _preset => _valid
      ? TimerPresets.custom(
          workSeconds: _read(_work),
          restSeconds: _read(_rest),
          rounds: _read(_rounds),
          warmupSeconds: _read(_warmup),
          cooldownSeconds: _read(_cooldown),
        )
      : null;

  /// The preset, or null after marking what is wrong under its field: a
  /// message at the foot of the screen did not say which field it meant.
  TimerPreset? _readPreset() {
    final TimerPreset? preset = _preset;
    if (preset == null) setState(() => _showErrors = true);
    return preset;
  }

  void _submit() {
    final preset = _readPreset();
    if (preset != null) widget.onStart(preset);
  }

  /// Asks for a name, then saves. Every saved preset was named "Custom",
  /// so a list of them told them apart only by their numbers.
  Future<void> _save() async {
    final preset = _readPreset();
    if (preset == null) return;
    final String formula = preset.displayDescription(context.l10n);
    final String? name = await showDialog<String>(
      context: context,
      builder: (_) => _PresetNameDialog(initial: formula),
    );
    if (name == null || !mounted) return;
    await widget.onSave(
      preset.copyWith(name: name.trim().isEmpty ? formula : name.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    // Paired side by side because that is how the values are reasoned
    // about — work against rest, warm-up against cool-down — and it keeps
    // five fields from becoming a five-screen-tall stack.
    final TimerPreset? preset = _preset;
    String? shown(String? error) => _showErrors ? error : null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            // Top-aligned, so an error under one field does not shift the
            // field beside it.
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _NumberField(
                  label: l10n.timerFieldWork,
                  controller: _work,
                  error: shown(_workError),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _NumberField(
                  label: l10n.timerFieldRest,
                  controller: _rest,
                  error: shown(_restError),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _NumberField(
            label: l10n.timerFieldRounds,
            controller: _rounds,
            error: shown(_roundsError),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _NumberField(
                  label: l10n.timerFieldWarmup,
                  controller: _warmup,
                  error: shown(_warmupError),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _NumberField(
                  label: l10n.timerFieldCooldown,
                  controller: _cooldown,
                  error: shown(_cooldownError),
                ),
              ),
            ],
          ),
          // How long it runs, as it is typed; it was known only once the
          // timer had started.
          if (preset != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.timerBuilderTotal(
                UnitFormatters.duration(
                  Duration(seconds: preset.totalDurationSeconds),
                ),
                l10n.intervalCount(preset.totalIntervals),
              ),
              style: AppTypography.caption(Theme.of(context)),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.play_arrow),
            label: Text(l10n.timerStartCustom),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: Text(l10n.timerSavePreset),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    this.error,
  });

  final String label;
  final TextEditingController controller;

  /// Shown under the field, in the error colour.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );

    return Semantics(
      label: label,
      textField: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: const <TextInputFormatter>[
              NumberInputFormatter.integer(),
            ],
            style: AppTypography.numeric(
              theme.textTheme.titleMedium?.copyWith(
                    fontSize: AppTypography.fieldValueSize,
                    color: scheme.onSurface,
                  ) ??
                  const TextStyle(),
            ),
            decoration: InputDecoration(
              errorText: error,
              filled: true,
              fillColor: scheme.surfaceContainerHigh,
              enabledBorder: border,
              border: border,
              focusedBorder: border.copyWith(
                borderSide: BorderSide(color: scheme.primary, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Longest name a saved preset can have.
const int kMaxPresetNameLength = 40;

/// Asks for a saved preset's name, filled in with its formula. Pops with
/// the text, or null when cancelled. Owns its controller, so the field is
/// never left pointing at a disposed one while the dialog animates out.
class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog({required this.initial});

  final String initial;

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial.length > kMaxPresetNameLength
        ? widget.initial.substring(0, kMaxPresetNameLength)
        : widget.initial,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.timerPresetNameTitle),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: kMaxPresetNameLength,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: l10n.timerPresetNameLabel),
        onSubmitted: (String value) => Navigator.pop(context, value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _name.text),
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }
}
