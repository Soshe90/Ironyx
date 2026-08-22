import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/database_providers.dart';
import 'package:fittrack/core/router/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

/// Renders every screen at each breakpoint in both themes.
///
/// Layout overflows and unbounded-constraint errors surface as exceptions
/// in `flutter_test`, so simply pumping a route is enough to catch the
/// class of bug that a redesign most often introduces — a Row that fits on
/// a phone but not a tablet, or a button that claims infinite width.
void main() {
  group('responsive smoke', () {
    late AppDatabase database;

    // Skips the seeder so the pump does not race a catalogue import.
    const Map<String, Object> seededPrefs = <String, Object>{
      'exercise_seed_version': 999999,
    };

    const Map<String, Size> surfaces = <String, Size>{
      'phone': Size(360, 800),
      'tablet': Size(834, 1100),
      'desktop': Size(1440, 900),
    };

    const Map<String, String> routes = <String, String>{
      'dashboard': Routes.home,
      'tracker': Routes.tracker,
      'library': Routes.library,
      'timer': Routes.timer,
      'progress': Routes.progress,
      'settings': Routes.settings,
      'active workout': Routes.activeWorkout,
    };

    setUp(() => database = AppDatabase.forTesting());

    // Drift's `.watch()` streams schedule a zero-duration timer on
    // cancellation; disposing the tree before closing the database avoids
    // flutter_test's "Timer still pending" assertion.
    Future<void> disposeApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      await database.close();
    }

    for (final MapEntry<String, String> route in routes.entries) {
      for (final MapEntry<String, Size> surface in surfaces.entries) {
        for (final ThemeMode mode in <ThemeMode>[
          ThemeMode.light,
          ThemeMode.dark,
        ]) {
          testWidgets(
            '${route.key} lays out on ${surface.key} in ${mode.name} mode',
            (tester) async {
              await pumpApp(
                tester,
                initialLocation: route.value,
                surfaceSize: surface.value,
                overrides: [
                  appDatabaseProvider.overrideWithValue(database),
                ],
                prefs: <String, Object>{
                  ...seededPrefs,
                  'theme_mode': mode.name,
                },
              );

              expect(tester.takeException(), isNull);
              await disposeApp(tester);
            },
          );
        }
      }
    }
  });
}
