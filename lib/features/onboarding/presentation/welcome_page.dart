import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/page_body.dart';
import '../../../core/widgets/sticky_action_bar.dart';
import '../../auth/domain/auth_controller.dart';
import '../domain/onboarding_controller.dart';

/// First-launch introduction: what the app does, then how to start.
///
/// Shown once per install, chosen as the router's initial location rather
/// than enforced with a `redirect` — ADR-8 forbids a redirect on this router
/// because it is the one thing able to stop a cold offline launch from
/// reaching the dashboard.
///
/// The copy about guest data is deliberately blunt. Workouts live in local
/// SQLite and are never uploaded (ADR-8), so an account does **not** protect
/// them; only an export does. Implying otherwise here would be a promise the
/// app cannot keep, and the person who finds out is someone who just lost
/// their training history.
class WelcomePage extends ConsumerWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool accountsAvailable = ref.watch(authAvailableProvider);

    // Leaves the welcome screen for [routeName], or straight to the
    // dashboard when it is null. The dashboard is always pushed first so
    // that backing out of a sign-in form lands on the app rather than on
    // this screen, which has already been dismissed by then.
    Future<void> leave([String? routeName]) async {
      await ref.read(onboardingControllerProvider.notifier).complete();
      if (!context.mounted) {
        return;
      }
      context.goNamed(Routes.homeName);
      if (routeName != null) {
        // The pushed route's result is the user closing a form; nothing here
        // waits on it.
        unawaited(context.pushNamed<void>(routeName));
      }
    }

    // The pitch scrolls; the choice does not. A short phone would otherwise
    // push "Continue without an account" past the bottom edge, which is
    // exactly the option someone with no intention of registering is looking
    // for — and the one they would have to hunt for by scrolling.
    return Scaffold(
      body: Column(
        children: <Widget>[
          Expanded(
            child: SafeArea(
              bottom: false,
              child: PageBody(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  children: <Widget>[
                    Icon(
                      Icons.fitness_center,
                      size: AppSpacing.xxl,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'FitTrack',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Your training, tracked.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const _Feature(
                      icon: Icons.checklist_rtl,
                      title: 'Log every set and rep',
                      detail: 'Weight, reps and rest, recorded as you lift.',
                    ),
                    const _Feature(
                      icon: Icons.calendar_month_outlined,
                      title: 'Follow or build programs',
                      detail: 'Start from a built-in split or write your own.',
                    ),
                    const _Feature(
                      icon: Icons.timer_outlined,
                      title: 'A rest timer that keeps time',
                      detail: 'Runs in the background, with sound and haptics.',
                    ),
                    const _Feature(
                      icon: Icons.show_chart,
                      title: 'Charts that show progress',
                      detail: 'Volume, estimated 1RM and body measurements.',
                    ),
                  ],
                ),
              ),
            ),
          ),
          StickyActionBar(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Sits with the buttons, not above the fold somewhere: it
                // qualifies the choice being made right here.
                _DataNotice(accountsAvailable: accountsAvailable),
                const SizedBox(height: AppSpacing.lg),
                if (accountsAvailable) ...<Widget>[
                  FilledButton(
                    onPressed: () => leave(Routes.signUpName),
                    child: const Text('Create a free account'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: () => leave(Routes.signInName),
                    child: const Text('I already have an account'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: leave,
                    child: const Text('Continue without an account'),
                  ),
                ] else
                  FilledButton(
                    onPressed: leave,
                    child: const Text('Get started'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: scheme.primary),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(detail, style: AppTypography.caption(theme)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the data actually lives, stated before the user starts adding any.
///
/// Points at the export, which is the only thing that genuinely survives an
/// uninstall — not at the account, which under ADR-8 carries identity only.
class _DataNotice extends StatelessWidget {
  const _DataNotice({required this.accountsAvailable});

  final bool accountsAvailable;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.info_outline,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              accountsAvailable
                  ? 'Your workouts stay on this device, account or not. '
                      'Uninstalling deletes them — save a backup from '
                      'Settings any time. A free account keeps your profile.'
                  : 'Your workouts stay on this device. Uninstalling deletes '
                      'them — save a backup from Settings any time.',
              style: AppTypography.caption(theme),
            ),
          ),
        ],
      ),
    );
  }
}
