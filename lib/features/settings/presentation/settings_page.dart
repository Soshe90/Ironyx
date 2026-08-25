import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters/unit_formatters.dart';
import '../../../core/formatters/weight_unit_controller.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/l10n/locale_controller.dart';
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
    final AppLocalizations l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navSettings),
        leading: IconButton(
          // Mirrors into a right-pointing arrow under an RTL locale, which is
          // the direction "back" actually points there.
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
          tooltip: l10n.actionBack,
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
            SectionHeader(
              title: l10n.settingsLanguageTitle,
              subtitle: l10n.settingsLanguageSubtitle,
            ),
            const AppCard(
              padding: EdgeInsets.zero,
              child: _LanguageSection(),
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionHeader(
              title: l10n.settingsAppearanceTitle,
              subtitle: l10n.settingsAppearanceSubtitle,
            ),
            AppCard(
              child: SegmentedButton<ThemeMode>(
                segments: <ButtonSegment<ThemeMode>>[
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.system,
                    label: Text(l10n.settingsThemeSystem),
                    icon: const Icon(Icons.brightness_auto_outlined),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.light,
                    label: Text(l10n.settingsThemeLight),
                    icon: const Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.dark,
                    label: Text(l10n.settingsThemeDark),
                    icon: const Icon(Icons.dark_mode_outlined),
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
            SectionHeader(
              title: l10n.settingsUnitsTitle,
              subtitle: l10n.settingsUnitsSubtitle,
            ),
            AppCard(
              child: SegmentedButton<WeightUnit>(
                segments: <ButtonSegment<WeightUnit>>[
                  for (final WeightUnit option in WeightUnit.values)
                    ButtonSegment<WeightUnit>(
                      value: option,
                      label: Text(
                        option == WeightUnit.kg
                            ? l10n.settingsUnitKilograms
                            : l10n.settingsUnitPounds,
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
            SectionHeader(
              title: l10n.settingsFeedbackTitle,
              subtitle: l10n.settingsFeedbackSubtitle,
            ),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    title: Text(l10n.settingsSoundCues),
                    subtitle: Text(l10n.settingsSoundCuesSubtitle),
                    value: feedback.soundEnabled,
                    onChanged: feedbackController.setSoundEnabled,
                  ),
                  SwitchListTile(
                    title: Text(l10n.settingsHaptics),
                    subtitle: Text(l10n.settingsHapticsSubtitle),
                    value: feedback.hapticsEnabled,
                    onChanged: feedbackController.setHapticsEnabled,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionHeader(
              title: l10n.settingsDataTitle,
              subtitle: l10n.settingsDataSubtitle,
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

/// Language picker, including the "follow the device" default.
///
/// Each language is listed in its own script rather than translated into the
/// current one: someone who has landed in a language they cannot read needs
/// to recognise their own to get back out.
class _LanguageSection extends ConsumerWidget {
  const _LanguageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Locale? selected = ref.watch(localeControllerProvider);

    // Keyed by language tag rather than by `Locale?` so that "match device"
    // is a real value: a null radio value reads to `RadioGroup` as "nothing
    // selected", which would leave the default option unchecked.
    return RadioGroup<String>(
      groupValue: selected?.languageCode ?? _systemTag,
      onChanged: (String? tag) {
        ref.read(localeControllerProvider.notifier).set(
              tag == null || tag == _systemTag ? null : Locale(tag),
            );
      },
      child: Column(
        children: <Widget>[
          RadioListTile<String>(
            value: _systemTag,
            title: Text(context.l10n.settingsLanguageSystem),
          ),
          for (final Locale locale in kSupportedLocales)
            RadioListTile<String>(
              value: locale.languageCode,
              title: Text(_endonym(locale)),
            ),
        ],
      ),
    );
  }

  static const String _systemTag = 'system';

  /// The language's name in that language.
  static String _endonym(Locale locale) => switch (locale.languageCode) {
        'ar' => 'العربية',
        _ => 'English',
      };
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
            context.l10n.settingsStorageNote,
            style: AppTypography.caption(theme),
          ),
        ),
      ],
    );
  }
}
