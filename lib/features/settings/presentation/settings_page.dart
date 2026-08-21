import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters/unit_formatters.dart';
import '../../../core/formatters/weight_unit_controller.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/widgets/responsive.dart';
import '../../timer/domain/timer_settings_controller.dart';
import 'widgets/data_management_section.dart';

/// Root-level route (ADR-3): full screen, bottom bar hidden.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode mode = ref.watch(themeModeControllerProvider);
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final TimerSettings feedback = ref.watch(timerSettingsControllerProvider);
    final TimerSettingsController feedbackController =
        ref.read(timerSettingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
          tooltip: 'Back',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            children: <Widget>[
              const _SectionHeader('Appearance'),
              _ThemeOption(
                label: 'Match system',
                value: ThemeMode.system,
                selected: mode,
              ),
              _ThemeOption(
                label: 'Light',
                value: ThemeMode.light,
                selected: mode,
              ),
              _ThemeOption(
                label: 'Dark',
                value: ThemeMode.dark,
                selected: mode,
              ),
              const Divider(),
              const _SectionHeader('Units'),
              for (final option in WeightUnit.values)
                _UnitOption(unit: option, selected: unit),
              const Divider(),
              const _SectionHeader('Feedback'),
              SwitchListTile(
                title: const Text('Sound cues'),
                value: feedback.soundEnabled,
                onChanged: feedbackController.setSoundEnabled,
              ),
              SwitchListTile(
                title: const Text('Haptics'),
                value: feedback.hapticsEnabled,
                onChanged: feedbackController.setHapticsEnabled,
              ),
              const Divider(),
              const _SectionHeader('Data'),
              const DataManagementSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeOption extends ConsumerWidget {
  const _ThemeOption({
    required this.label,
    required this.value,
    required this.selected,
  });

  final String label;
  final ThemeMode value;
  final ThemeMode selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isSelected = value == selected;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return ListTile(
      title: Text(label),
      trailing: isSelected
          ? Icon(Icons.check, color: scheme.primary)
          : const SizedBox(width: 24),
      selected: isSelected,
      onTap: () async {
        await ref.read(themeModeControllerProvider.notifier).set(value);
      },
    );
  }
}

class _UnitOption extends ConsumerWidget {
  const _UnitOption({required this.unit, required this.selected});

  final WeightUnit unit;
  final WeightUnit selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isSelected = unit == selected;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return ListTile(
      title: Text(unit == WeightUnit.kg ? 'Kilograms (kg)' : 'Pounds (lb)'),
      trailing: isSelected
          ? Icon(Icons.check, color: scheme.primary)
          : const SizedBox(width: 24),
      selected: isSelected,
      onTap: () async {
        await ref.read(weightUnitControllerProvider.notifier).set(unit);
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
