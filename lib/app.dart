import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/router/routes.dart';
import 'core/theme/app_theme.dart';

import 'core/theme/theme_mode_controller.dart';
import 'features/auth/domain/auth_controller.dart';
import 'features/auth/domain/auth_service.dart';
import 'features/onboarding/domain/onboarding_controller.dart';

class FitTrackApp extends ConsumerStatefulWidget {
  const FitTrackApp({this.router, super.key});

  /// Injected by widget tests so they can start at an arbitrary location.
  final GoRouter? router;

  @override
  ConsumerState<FitTrackApp> createState() => _FitTrackAppState();
}

class _FitTrackAppState extends ConsumerState<FitTrackApp> {
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
      unawaited(
        ref.read(profileDaoProvider).linkAccount(
              userId: next.id,
              email: next.email,
            ),
      );
    });

    return MaterialApp.router(
      title: 'FitTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: _router,
    );
  }
}
