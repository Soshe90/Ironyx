import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/router/app_router.dart';
import 'core/services/exercise_seeder.dart';
import 'core/services/program_seeder.dart';
import 'core/theme/app_theme.dart';

import 'core/theme/theme_mode_controller.dart';

class FitTrackApp extends ConsumerStatefulWidget {
  const FitTrackApp({this.router, super.key});

  /// Injected by widget tests so they can start at an arbitrary location.
  final GoRouter? router;

  @override
  ConsumerState<FitTrackApp> createState() => _FitTrackAppState();
}

class _FitTrackAppState extends ConsumerState<FitTrackApp> {
  late final GoRouter _router = widget.router ?? createRouter();

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
