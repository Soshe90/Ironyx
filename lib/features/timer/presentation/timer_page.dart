import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database_providers.dart';
import '../../../core/formatters/unit_formatters.dart';
import '../../../core/router/routes.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/responsive.dart';
import '../domain/timer_controller.dart';
import '../domain/timer_preset.dart';
import '../domain/timer_settings_controller.dart';

/// Timer hub (branch index 3). Quick-start presets, a custom builder, and
/// feedback toggles. Starting a session requests notification permission in
/// context, then pushes the full-screen active timer (ADR-3).
class TimerPage extends ConsumerWidget {
  const TimerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timer')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                const _SectionHeader('Quick start'),
                _PresetCard(
                  preset: TimerPresets.tabata(),
                  onTap: () => _start(context, ref, TimerPresets.tabata()),
                ),
                _PresetCard(
                  preset: TimerPresets.hiit(),
                  onTap: () => _start(context, ref, TimerPresets.hiit()),
                ),
                _PresetCard(
                  preset: TimerPresets.strength(),
                  onTap: () => _start(context, ref, TimerPresets.strength()),
                ),
                const SizedBox(height: AppSpacing.lg),
                const _SectionHeader('Saved presets'),
                const _SavedPresets(),
                const SizedBox(height: AppSpacing.lg),
                const _SectionHeader('Custom'),
                _CustomBuilder(
                  onStart: (preset) => _start(context, ref, preset),
                  onSave: (preset) async {
                    await ref.read(timerPresetDaoProvider).save(preset);
                    ref.invalidate(savedTimerPresetsProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Preset saved.')),
                      );
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                const _SectionHeader('Feedback'),
                const _FeedbackToggles(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _start(
    BuildContext context,
    WidgetRef ref,
    TimerPreset preset,
  ) async {
    final NotificationService notifications =
        ref.read(notificationServiceProvider);

    // Re-check on every start (users revoke in system settings), then request
    // in context if needed. A denial must never block the timer (ADR-4).
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
}

class _SavedPresets extends ConsumerWidget {
  const _SavedPresets();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedTimerPresetsProvider);
    return saved.when(
      data: (presets) => presets.isEmpty
          ? const Text('No saved presets yet.')
          : Column(
              children: [
                for (final preset in presets)
                  _PresetCard(
                    preset: preset,
                    onTap: () => _start(context, ref, preset),
                  ),
              ],
            ),
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text('Unable to load saved presets: $error'),
    );
  }

  Future<void> _start(
    BuildContext context,
    WidgetRef ref,
    TimerPreset preset,
  ) async {
    final notifications = ref.read(notificationServiceProvider);
    final alreadyGranted = await notifications.isPermissionGranted;
    final granted = alreadyGranted || await notifications.requestPermission();
    await ref.read(timerControllerProvider.notifier).start(
          preset,
          notificationGranted: granted,
        );
    if (context.mounted) unawaited(context.pushNamed(Routes.activeTimerName));
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.preset, required this.onTap});

  final TimerPreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Duration total = Duration(seconds: preset.totalDurationSeconds);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: onTap,
        semanticLabel: 'Start ${preset.name}',
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    preset.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              UnitFormatters.duration(total),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.play_arrow),
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
        const SnackBar(
          content: Text('Work, rest and rounds must be positive.'),
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
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NumberField(label: 'Work (s)', controller: _work),
          _NumberField(label: 'Rest (s)', controller: _rest),
          _NumberField(label: 'Rounds', controller: _rounds),
          _NumberField(label: 'Warm-up (s, optional)', controller: _warmup),
          _NumberField(label: 'Cool-down (s, optional)', controller: _cooldown),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start custom'),
              ),
              OutlinedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save preset'),
              ),
            ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class _FeedbackToggles extends ConsumerWidget {
  const _FeedbackToggles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TimerSettings settings = ref.watch(timerSettingsControllerProvider);
    final TimerSettingsController controller =
        ref.read(timerSettingsControllerProvider.notifier);

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Sound cues'),
            value: settings.soundEnabled,
            onChanged: controller.setSoundEnabled,
          ),
          SwitchListTile(
            title: const Text('Haptics'),
            value: settings.hapticsEnabled,
            onChanged: controller.setHapticsEnabled,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
