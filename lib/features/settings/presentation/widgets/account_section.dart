import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../auth/domain/auth_controller.dart';
import '../../../auth/domain/auth_service.dart';

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SectionHeader(
          title: 'Account',
          subtitle: 'Optional — your workouts are stored on this device '
              'either way',
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              if (!available)
                const ListTile(
                  leading: Icon(Icons.cloud_off_outlined),
                  title: Text('Accounts unavailable'),
                  subtitle: Text('This build has no sign-in configured.'),
                )
              else if (user == null) ...<Widget>[
                ListTile(
                  leading: const Icon(Icons.login),
                  title: const Text('Sign in'),
                  subtitle: const Text('Keep your details with your account'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.pushNamed(Routes.signInName),
                ),
                ListTile(
                  leading: const Icon(Icons.person_add_alt),
                  title: const Text('Create account'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.pushNamed(Routes.signUpName),
                ),
              ] else ...<Widget>[
                ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(user.email),
                  subtitle: const Text('Signed in'),
                ),
                if (!user.isEmailConfirmed)
                  const ListTile(
                    leading: Icon(Icons.mark_email_unread_outlined),
                    title: Text('Email not confirmed'),
                    subtitle: Text('Open the link we sent to finish setting '
                        'up your account.'),
                  ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign out'),
                  onTap: () => _signOut(context, ref),
                ),
              ],
              // Always available, signed in or not: the details are local,
              // and a guest has just as much use for them.
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Personal details'),
                subtitle: const Text('Name, date of birth, sex, height'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.pushNamed(Routes.personalDetailsName),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your workouts, programs and personal details stay on this device. '
          'Only the account link is removed.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authControllerProvider.notifier).signOut();
      await ref.read(profileDaoProvider).unlinkAccount();
      messenger.showSnackBar(const SnackBar(content: Text('Signed out')));
    } on AuthFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}
