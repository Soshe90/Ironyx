import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/database_providers.dart';
import 'package:fittrack/core/router/scaffold_with_nav_bar.dart';
import 'package:fittrack/features/dashboard/presentation/dashboard_page.dart';
import 'package:fittrack/features/tracker/presentation/active_workout_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  group('shell navigation', () {
    // The dashboard (M6) now reads live data from five stream providers,
    // and the Timer tab reads saved presets (M4) — both resolve their
    // storage path through path_provider's platform channel and never
    // complete in a plain `flutter test` run, leaving an indeterminate
    // loading indicator animating forever, which is exactly what
    // pumpAndSettle waits on. An in-memory test database resolves
    // immediately instead, matching the fix already used by
    // `library_page_test.dart`. Every test in this group lands on the
    // dashboard at least momentarily, so every test needs the override.
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.forTesting();
    });

    List<dynamic> overrides() => [
          appDatabaseProvider.overrideWithValue(database),
        ];

    // Drift's `.watch()` streams schedule a zero-duration timer on
    // cancellation; disposing the widget tree (and letting that timer fire)
    // before closing the database avoids flutter_test's "Timer still
    // pending after widget tree disposed" assertion — same fix as
    // `progress_page_test.dart`'s `disposeApp` and
    // `dashboard_page_test.dart`.
    Future<void> disposeApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      await database.close();
    }

    testWidgets('starts on the dashboard', (tester) async {
      await pumpApp(tester, overrides: overrides());
      expect(find.byType(DashboardPage), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('exposes exactly five destinations', (tester) async {
      await pumpApp(tester, overrides: overrides());
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      await disposeApp(tester);
    });

    testWidgets('switching tabs changes the visible page', (tester) async {
      await pumpApp(
        tester,
        overrides: overrides(),
        prefs: const {'exercise_seed_version': 999999},
      );

      await tester.tap(find.text('Timer'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Timer'), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('root-level route hides the bottom bar (ADR-3)',
        (tester) async {
      await pumpApp(tester, overrides: overrides());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start workout'));
      await tester.pumpAndSettle();

      expect(find.byType(ActiveWorkoutPage), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await disposeApp(tester);
    });

    testWidgets('closing a root route returns to the originating branch',
        (tester) async {
      await pumpApp(tester, overrides: overrides());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start workout'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(DashboardPage), findsOneWidget);
      await disposeApp(tester);
    });

    testWidgets('wide layout swaps the bottom bar for a rail', (tester) async {
      await pumpApp(
        tester,
        overrides: overrides(),
        surfaceSize: const Size(1200, 900),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(ScaffoldWithNavBar), findsOneWidget);
      await disposeApp(tester);
    });
  });
}
