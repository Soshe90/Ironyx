import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/error_reporting.dart';
import 'core/l10n/locale_controller.dart';
import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/router/routes.dart';
import 'core/theme/app_theme.dart';

import 'core/theme/theme_mode_controller.dart';
import 'features/auth/domain/auth_controller.dart';
import 'features/auth/domain/auth_service.dart';
import 'features/onboarding/domain/onboarding_controller.dart';
import 'l10n/app_localizations.dart';

class IronyxApp extends ConsumerStatefulWidget {
  const IronyxApp({this.router, super.key});

  /// Injected by widget tests so they can start at an arbitrary location.
  final GoRouter? router;

  @override
  ConsumerState<IronyxApp> createState() => _IronyxAppState();
}

class _IronyxAppState extends ConsumerState<IronyxApp> {
  /// Built once, on the first frame, from the persisted onboarding flag.
  ///
  /// `read` rather than `watch`: completing onboarding flips that flag, and
  /// rebuilding the router mid-session would tear down the navigator the
  /// welcome screen is currently navigating away from. The flag only needs
  /// to decide where this launch starts.
  late final GoRouter _router = widget.router ??
      createRouter(
        initialLocation: ref.read(onboardingControllerProvider)
            ? Routes.home
            : Routes.welcome,
      );

  @override
  void dispose() {
    // Only dispose a router this widget created.
    if (widget.router == null) {
      _router.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeMode themeMode = ref.watch(themeModeControllerProvider);
    final Locale? locale = ref.watch(localeControllerProvider);

    // Kicks off the idempotent exercise seeder (M2) once per launch. It's a
    // keepAlive provider that no screen otherwise reads, so nothing would
    // ever trigger `build()` without watching it from somewhere durable.
    ref.watch(exerciseSeederProvider);

    // Same pattern for built-in training programs (M8).
    ref.watch(programSeederProvider);

    // Links the local profile to whichever account just became active.
    //
    // The sign-in and sign-up screens do this themselves for the paths they
    // own, but confirming an email arrives by deep link (ADR-8): Supabase
    // hands the session straight to `AuthController` and no auth screen is
    // ever on top to notice. Without this, a user who confirms from their
    // mail app is signed in with an unlinked profile.
    //
    // `linkAccount` is an idempotent upsert, and the id guard keeps a token
    // refresh — which re-emits the same user — from writing on every rebuild.
    ref.listen<AuthUser?>(authControllerProvider, (previous, next) {
      if (next == null || previous?.id == next.id) {
        return;
      }
      unawaited(_linkIfNoConflict(ref, next));
    });

    return MaterialApp.router(
      // `onGenerateTitle` rather than `title`: it runs with a context that can
      // reach `Localizations`, so the name the OS task switcher shows follows
      // the app's language.
      onGenerateTitle: (BuildContext context) =>
          AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      // Null means "follow the device", which is what `basicLocaleListResolution`
      // already does with the platform's preferred locale list.
      locale: locale,
      supportedLocales: kSupportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: _router,
    );
  }
}

/// Links [user] to the local profile unless doing so would silently
/// reassign this device's existing training data away from a *different*
/// account — see `ProfileDao.hasConflictingAccount`.
///
/// Deliberately does not prompt: this listener fires outside any screen's
/// control (a deep-linked email confirmation can complete while no
/// interactive auth flow is on screen, or none at all), so there is no
/// `BuildContext` reliably available to run the same conflict dialog
/// `SignInPage`/`SignUpPage` show. Skipping the link is the safe default —
/// it leaves the previous association in place, which keeps
/// `CloudBackupController.backUpNow`'s own `accountMismatch` guard refusing
/// to upload rather than quietly attaching this device's data to whichever
/// account the deep link just authenticated. Signing in again through
/// Settings resolves it through the interactive flow.
Future<void> _linkIfNoConflict(WidgetRef ref, AuthUser user) async {
  final bool conflict =
      await ref.read(profileDaoProvider).hasConflictingAccount(user.id);
  if (conflict) {
    reportError(
      'Skipped linking ${user.id}: this device is already linked to a '
      'different account.',
      null,
      context: 'AccountLink',
    );
    return;
  }
  await ref.read(profileDaoProvider).linkAccount(
        userId: user.id,
        email: user.email,
      );
}
