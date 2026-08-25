import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../auth/domain/auth_controller.dart';
import '../../../auth/domain/auth_service.dart';
import '../../../auth/presentation/auth_failure_messages.dart';

/// The Settings entry point for accounts and personal details.
///
/// Three states, in order of how often they're seen: signed out (offer to
/// sign in), signed in (show who, offer to leave), and not-configured (this
/// build shipped without Supabase credentials, so say so rather than
/// offering a button that can only fail).
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool available = ref.watch(authAvailableProvider);
    final AuthUser? user = ref.watch(authControllerProvider);
    // Deliberately does not watch the profile. A drift query stream schedules
    // a timer that never resolves under a widget test's fake clock, which
    // leaves a pending timer at teardown and keeps frames scheduled so
    // `pumpAndSettle` spins for its full 10-minute timeout. The email below
    // already identifies the account; the display name belongs on the
    // Personal Details screen, which is one tap away.

    final AppLocalizations l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title: l10n.accountSectionTitle,
          subtitle: l10n.accountSectionSubtitle,
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              if (!available)
                ListTile(
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: Text(l10n.accountUnavailableTitle),
                  subtitle: Text(l10n.accountUnavailableSubtitle),
                )
              else if (user == null) ...<Widget>[
                ListTile(
                  leading: const Icon(Icons.login),
                  title: Text(l10n.authSignInTitle),
                  subtitle: Text(l10n.accountSignInSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.pushNamed(Routes.signInName),
                ),
                ListTile(
                  leading: const Icon(Icons.person_add_alt),
                  title: Text(l10n.authCreateAccountTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.pushNamed(Routes.signUpName),
                ),
              ] else ...<Widget>[
                ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(user.email),
                  subtitle: Text(l10n.authSignedIn),
                ),
                if (!user.isEmailConfirmed)
                  ListTile(
                    leading: const Icon(Icons.mark_email_unread_outlined),
                    title: Text(l10n.accountEmailNotConfirmedTitle),
                    subtitle: Text(l10n.accountEmailNotConfirmedSubtitle),
                  ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: Text(l10n.authSignOut),
                  onTap: () => _signOut(context, ref),
                ),
              ],
              // Always available, signed in or not: the details are local,
              // and a guest has just as much use for them.
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(l10n.accountPersonalDetailsTitle),
                subtitle: Text(l10n.accountPersonalDetailsSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.pushNamed(Routes.personalDetailsName),
              ),
              // The welcome screen shows once per install, so without this
              // the only way back to it is a reinstall — which would take
              // the workout history with it.
              ListTile(
                leading: const Icon(Icons.slideshow_outlined),
                title: Text(l10n.accountShowWelcomeTitle),
                subtitle: Text(l10n.accountShowWelcomeSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.pushNamed(Routes.welcomeName),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.authSignOutConfirmTitle),
        content: Text(l10n.authSignOutConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.authSignOut),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authControllerProvider.notifier).signOut();
      await ref.read(profileDaoProvider).unlinkAccount();
      messenger.showSnackBar(SnackBar(content: Text(l10n.authSignedOut)));
    } on AuthFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text(failure.messageFor(l10n))),
      );
    }
  }
}
