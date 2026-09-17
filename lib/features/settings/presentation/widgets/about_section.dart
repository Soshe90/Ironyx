import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/services/data_export_service.dart' show kAppVersion;

/// Version, open-source licenses, and exercise-data attribution.
///
/// The exercise catalogue (free-exercise-db, public domain) owes no
/// attribution under its licence — see `ASSETS-LICENSE.md` — but crediting
/// it here costs one card and is the honest thing to do regardless. The
/// "Open-source licenses" tile opens Flutter's own `showLicensePage`, which
/// already lists every package dependency's licence automatically; the one
/// thing it does not know about is bundled data rather than a package, which
/// is why the exercise catalogue also gets its own tile and its own
/// `LicenseRegistry` entry (registered once, in `main.dart`).
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Column(
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.fitness_center_outlined),
          title: Text(l10n.settingsExerciseCreditsTitle),
          subtitle: Text(l10n.settingsExerciseCreditsSubtitle),
          onTap: () => _showExerciseCredits(context),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(l10n.settingsLicensesTitle),
          subtitle: Text(l10n.settingsLicensesSubtitle),
          onTap: () => showLicensePage(
            context: context,
            applicationName: l10n.appTitle,
            applicationVersion: kAppVersion,
          ),
        ),
      ],
    );
  }

  Future<void> _showExerciseCredits(BuildContext context) async {
    final AppLocalizations l10n = context.l10n;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsExerciseCreditsTitle),
        content: Text(l10n.settingsExerciseCreditsBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => _openSource(context),
            child: Text(l10n.settingsExerciseCreditsViewSource),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.actionOk),
          ),
        ],
      ),
    );
  }

  Future<void> _openSource(BuildContext context) async {
    final AppLocalizations l10n = context.l10n;
    final bool launched = await launchUrl(
      Uri.parse('https://github.com/yuhonas/free-exercise-db'),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsExerciseCreditsOpenFailed)),
      );
    }
  }
}
