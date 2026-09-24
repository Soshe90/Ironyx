import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database_providers.dart';
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
              // The user's own presets first: they are why someone saved
              // one. Hidden entirely until there is one to show.
              const _SavedPresets(),
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
              SectionHeader(
                title: l10n.timerCustomTitle,
                subtitle: l10n.timerCustomSubtitle,
              ),
              _CustomBuilder(
                onStart: (preset) => startTimer(context, ref, preset),
                onSave: (preset) async {
                  await ref.read(timerPresetDaoProvider).save(preset);
                  ref.invalidate(savedTimerPresetsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.l10n.timerPresetSaved)),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Starts [preset] and opens the full-screen timer.
///
/// Permission is re-checked on every start (users revoke in system
/// settings) and requested in context if needed. A denial must never block
/// the timer (ADR-4) — it only costs the background notification.
Future<void> startTimer(
  BuildContext context,
  WidgetRef ref,
  TimerPreset preset,
) async {
  final NotificationService notifications =
      ref.read(notificationServiceProvider);

  final bool alreadyGranted = await notifications.isPermissionGranted;
  final bool granted =
      alreadyGranted || await notifications.requestPermission();

  await ref
      .read(timerControllerProvider.notifier)
      .start(preset, notificationGranted: granted);

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

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.preset, required this.onTap});

  final TimerPreset preset;
  final VoidCallback onTap;

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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    preset.displayName(context.l10n),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    preset.displayDescription(context.l10n),
                    style: AppTypography.caption(theme),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  UnitFormatters.duration(total),
                  style: AppTypography.cardMetric(
                    scheme,
                    size: AppTypography.metricSizeSm,
                  ),
                ),
                Text(
                  context.l10n.intervalCount(preset.totalIntervals),
                  style: AppTypography.eyebrow(theme),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.md),
            Icon(Icons.play_circle_outline, color: scheme.primary),
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

  @override
  void dispose() {
    _work.dispose();
    _rest.dispose();
    _rounds.dispose();
    _warmup.dispose();
    _cooldown.dispose();
    super.dispose();
  }

  TimerPreset? _readPreset() {
    final int work = int.tryParse(_work.text) ?? 0;
    final int rest = int.tryParse(_rest.text) ?? 0;
    final int rounds = int.tryParse(_rounds.text) ?? 0;
    final int warmup = int.tryParse(_warmup.text) ?? 0;
    final int cooldown = int.tryParse(_cooldown.text) ?? 0;

    if (work <= 0 || rest <= 0 || rounds <= 0 || warmup < 0 || cooldown < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.timerPositiveValuesRequired),
        ),
      );
      return null;
    }

    return TimerPresets.custom(
      workSeconds: work,
      restSeconds: rest,
      rounds: rounds,
      warmupSeconds: warmup,
      cooldownSeconds: cooldown,
    );
  }

  void _submit() {
    final preset = _readPreset();
    if (preset != null) widget.onStart(preset);
  }

  Future<void> _save() async {
    final preset = _readPreset();
    if (preset != null) await widget.onSave(preset);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    // Paired side by side because that is how the values are reasoned
    // about — work against rest, warm-up against cool-down — and it keeps
    // five fields from becoming a five-screen-tall stack.
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: <Widget>[
              Expanded(
                child:
                    _NumberField(label: l10n.timerFieldWork, controller: _work),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child:
                    _NumberField(label: l10n.timerFieldRest, controller: _rest),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _NumberField(label: l10n.timerFieldRounds, controller: _rounds),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: _NumberField(
                  label: l10n.timerFieldWarmup,
                  controller: _warmup,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _NumberField(
                  label: l10n.timerFieldCooldown,
                  controller: _cooldown,
                ),
              ),
            ],
          ),
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
  const _NumberField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: AppTypography.numeric(
        Theme.of(context).textTheme.bodyLarge ?? const TextStyle(),
      ),
      decoration: InputDecoration(labelText: label),
    );
  }
}
