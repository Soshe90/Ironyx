import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters/unit_formatters.dart';
import '../../../core/formatters/weight_unit_controller.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_body.dart';
import '../../../core/widgets/section_header.dart';
import '../../timer/domain/timer_settings_controller.dart';
import 'widgets/account_section.dart';
import 'widgets/cloud_backup_section.dart';
import 'widgets/data_management_section.dart';

/// Root-level route (ADR-3): full screen, bottom bar hidden.
///
/// Grouped into titled cards rather than one flat list separated by rules:
/// the settings here fall into four unrelated concerns, and a card per
/// concern makes that structure visible without extra chrome.
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
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          children: <Widget>[
            const AccountSection(),
            // Directly under Account on purpose: the backup is tied to the
            // account, and someone who has just signed in on a fresh
            // install is exactly the person looking for it.
            const CloudBackupSection(),
            const SectionHeader(
              title: 'Appearance',
              subtitle: 'Dark mode is a first-class theme, not an inversion',
            ),
            AppCard(
              child: SegmentedButton<ThemeMode>(
                segments: const <ButtonSegment<ThemeMode>>[
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.system,
                    label: Text('System'),
                    icon: Icon(Icons.brightness_auto_outlined),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: <ThemeMode>{mode},
                showSelectedIcon: false,
                onSelectionChanged: (Set<ThemeMode> selection) async {
                  await ref
                      .read(themeModeControllerProvider.notifier)
                      .set(selection.first);
                },
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(
              title: 'Units',
              subtitle: 'Applies everywhere weights are shown or entered',
            ),
            AppCard(
              child: SegmentedButton<WeightUnit>(
                segments: <ButtonSegment<WeightUnit>>[
                  for (final WeightUnit option in WeightUnit.values)
                    ButtonSegment<WeightUnit>(
                      value: option,
                      label: Text(
                        option == WeightUnit.kg
                            ? 'Kilograms (kg)'
                            : 'Pounds (lb)',
                      ),
                    ),
                ],
                selected: <WeightUnit>{unit},
                showSelectedIcon: false,
                onSelectionChanged: (Set<WeightUnit> selection) async {
                  await ref
                      .read(weightUnitControllerProvider.notifier)
                      .set(selection.first);
                },
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(
              title: 'Feedback',
              subtitle: 'Cues when a timer phase ends',
            ),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    title: const Text('Sound cues'),
                    subtitle: const Text('Play a tone on phase change'),
                    value: feedback.soundEnabled,
                    onChanged: feedbackController.setSoundEnabled,
                  ),
                  SwitchListTile(
                    title: const Text('Haptics'),
                    subtitle: const Text('Vibrate on phase change'),
                    value: feedback.hapticsEnabled,
                    onChanged: feedbackController.setHapticsEnabled,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(
              title: 'Data',
              subtitle: 'FitTrack stores everything on this device',
            ),
            const AppCard(
              padding: EdgeInsets.zero,
              child: DataManagementSection(),
            ),
            const SizedBox(height: AppSpacing.xl),
            const _StorageNote(),
          ],
        ),
      ),
    );
  }
}

/// Closes the page with the one thing a user is most likely to worry about
/// on a settings screen: where their data actually lives.
class _StorageNote extends StatelessWidget {
  const _StorageNote();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.lock_outline,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Your training data never leaves this device unless you export '
            'it yourself.',
            style: AppTypography.caption(theme),
          ),
        ),
      ],
    );
  }
}
