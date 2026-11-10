import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/router/routes.dart';
import 'package:ironyx/core/theme/app_colors.dart';
import 'package:ironyx/features/timer/domain/timer_controller.dart';
import 'package:ironyx/features/timer/domain/timer_engine.dart';
import 'package:ironyx/features/timer/domain/timer_preset.dart';
import 'package:ironyx/features/timer/presentation/active_timer_page.dart';

import '../helpers/pump_app.dart';

/// Stands in for the real controller so the screen can be driven without
/// wakelock, audio, notifications or a ticking clock.
class _FakeTimerController extends TimerController {
  _FakeTimerController(this._initial);

  final TimerSnapshot _initial;
  int stops = 0;

  @override
  TimerSnapshot? build() => _initial;

  @override
  bool get isActive => state != null;

  @override
  Future<void> stop() async {
    stops++;
    state = null;
  }

  /// The last interval running out on its own.
  void finish() => state = null;

  void show(TimerSnapshot snapshot) => state = snapshot;
}

TimerSnapshot _snapshot(TimerPhaseType type) => TimerSnapshot(
      currentIndex: 0,
      currentPhase: TimerPhase(type: type, durationSeconds: 20),
      remaining: const Duration(seconds: 12),
      elapsed: const Duration(seconds: 8),
      total: const Duration(minutes: 4),
      progress: 0.4,
      isRunning: true,
      isComplete: false,
    );

void main() {
  late AppDatabase database;
  late _FakeTimerController controller;

  setUp(() {
    database = AppDatabase.forTesting();
    controller = _FakeTimerController(_snapshot(TimerPhaseType.work));
  });

  tearDown(() async {
    await database.close();
  });

  /// Frame-by-frame rather than `pumpAndSettle`: the Timer tab underneath
  /// can hold a never-ending loading shimmer.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> openActiveTimer(
    WidgetTester tester, {
    String themeMode = 'dark',
  }) async {
    await pumpApp(
      tester,
      initialLocation: Routes.timer,
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        timerControllerProvider.overrideWith(() => controller),
      ],
      prefs: <String, Object>{
        'exercise_seed_version': 999999,
        'theme_mode': themeMode,
      },
    );
    // Completes only when the page pops, which some tests never do.
    unawaited(
      GoRouter.of(tester.element(find.text('Quick start')))
          .pushNamed(Routes.activeTimerName),
    );
    await settle(tester);
    expect(find.byType(ActiveTimerPage), findsOneWidget);
  }

  testWidgets('closing asks first, and Cancel keeps the session running',
      (tester) async {
    await openActiveTimer(tester);

    await tester.tap(find.byTooltip('End timer').first);
    await settle(tester);
    expect(find.text('End this timer?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(controller.stops, 0);
    expect(find.byType(ActiveTimerPage), findsOneWidget);
  });

  testWidgets('confirming ends the session and leaves the screen',
      (tester) async {
    await openActiveTimer(tester);

    await tester.tap(find.byTooltip('End timer').last);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'End timer'));
    await settle(tester);

    expect(controller.stops, 1);
    expect(find.byType(ActiveTimerPage), findsNothing);
    expect(find.text('Quick start'), findsOneWidget);
  });

  testWidgets('system back asks instead of hiding a running timer',
      (tester) async {
    await openActiveTimer(tester);

    await tester.binding.handlePopRoute();
    await settle(tester);

    expect(find.text('End this timer?'), findsOneWidget);
    expect(find.byType(ActiveTimerPage), findsOneWidget);
    expect(controller.stops, 0);
  });

  testWidgets('a session that finishes under the dialog closes both',
      (tester) async {
    await openActiveTimer(tester);

    await tester.tap(find.byTooltip('End timer').first);
    await settle(tester);
    controller.finish();
    await settle(tester);

    expect(find.text('End this timer?'), findsNothing);
    expect(find.byType(ActiveTimerPage), findsNothing);
    expect(controller.stops, 0);
  });

  testWidgets('the countdown ring stays a circle on a phone', (tester) async {
    await openActiveTimer(tester);

    // Seen on a real phone (LMR LX9): a 200dp minimum diameter forced into
    // ~160dp of height drew the ring as a 210x161 oval.
    final Size ring = tester.getSize(find.byType(CircularProgressIndicator));
    expect(ring.width, ring.height);
  });

  for (final (String mode, Color rest, Color prepare)
      in <(String, Color, Color)>[
    ('light', AppColors.phaseRestLight, AppColors.phasePrepareLight),
    ('dark', AppColors.phaseRestDark, AppColors.phasePrepareDark),
  ]) {
    testWidgets('each phase takes its own colour ($mode)', (tester) async {
      await openActiveTimer(tester, themeMode: mode);
      final ColorScheme scheme =
          Theme.of(tester.element(find.byType(ActiveTimerPage))).colorScheme;
      Color? phaseColor(String label) =>
          tester.widget<Text>(find.text(label)).style?.color;
      Color? ringColor() => tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .color;

      expect(phaseColor('Work'), scheme.primary);
      expect(ringColor(), scheme.primary);

      controller.show(_snapshot(TimerPhaseType.rest));
      await settle(tester);
      expect(phaseColor('Rest'), rest);
      expect(ringColor(), rest);

      controller.show(_snapshot(TimerPhaseType.prepare));
      await settle(tester);
      expect(phaseColor('Prepare'), prepare);
    });
  }
}
