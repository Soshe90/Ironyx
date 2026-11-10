import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ironyx/core/router/routes.dart';
import 'package:ironyx/features/tracker/presentation/widgets/draft_editor_widgets.dart';

import 'helpers/e2e_harness.dart';

/// Layout under the settings most likely to break it: Arabic (right to
/// left, a different font with taller glyphs), 200 % text, and dark mode,
/// rendered with the phone's own fonts rather than the test font.
///
/// A clipped or overflowing layout is reported by Flutter as an error, which
/// these tests turn into a failure naming the screen.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// A draft with long names and big numbers, the worst case for a set row.
  final String draft = jsonEncode(<String, Object?>{
    'id': 'layout-draft',
    'startedAt': DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 1, minutes: 23))
        .toIso8601String(),
    'exercises': <Object>[
      for (int e = 0; e < 3; e++)
        <String, Object?>{
          'id': 'e$e',
          'exerciseId': 'unknown-$e',
          'name': 'ضغط الصدر بالبار على مقعد مائل بقبضة واسعة $e',
          'supersetGroupId': e < 2 ? 'g1' : null,
          'sets': <Object>[
            for (int s = 0; s < 4; s++)
              <String, Object?>{
                'id': 'e$e-s$s',
                'weightKg': 997.5,
                'reps': 100,
                'isCompleted': s.isEven,
                'rpeTimes10': 95,
                'restSeconds': 180,
              },
          ],
        },
    ],
  });

  final List<({String name, String locale, double scale, String theme})>
      configs = <({String name, String locale, double scale, String theme})>[
    (name: 'Arabic, 200 %, dark', locale: 'ar', scale: 2.0, theme: 'dark'),
    (name: 'English, 200 %, light', locale: 'en', scale: 2.0, theme: 'light'),
    (name: 'Arabic, 100 %, light', locale: 'ar', scale: 1.0, theme: 'light'),
  ];

  for (final config in configs) {
    testWidgets('${config.name}: every tab renders without overflow',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = config.scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final E2eApp app = await E2eApp.install(prefs: {
        'onboarding_complete': true,
        'app_locale': config.locale,
        'theme_mode': config.theme,
      });
      await app.launch(tester);
      await pumpUntilFound(tester, find.byType(NavigationBar));
      if (config.locale == 'ar') {
        expect(
          Directionality.of(tester.element(find.byType(NavigationBar))),
          TextDirection.rtl,
        );
      }

      // By position, not label: the labels are translated. Workouts,
      // Library, Timer, Progress, then back to Home.
      for (final int tab in <int>[1, 2, 3, 4, 0]) {
        await tester.tap(
          find
              .descendant(
                of: find.byType(NavigationBar),
                matching: find.byType(NavigationDestination),
              )
              .at(tab),
        );
        await pumpFor(tester, const Duration(seconds: 1));
        await _scrollThrough(tester);
        expect(tester.takeException(), isNull, reason: 'tab $tab');
      }
    });

    testWidgets('${config.name}: the active workout renders without overflow',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = config.scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final E2eApp app = await E2eApp.install(prefs: {
        'onboarding_complete': true,
        'app_locale': config.locale,
        'theme_mode': config.theme,
        'active_workout_draft': draft,
      });
      await app.launch(tester, initialLocation: Routes.activeWorkout);
      await pumpUntilFound(tester, find.byType(DraftSetRow));

      await _scrollThrough(tester);
      expect(tester.takeException(), isNull);

      // The largest figure a set row can hold is still readable in full.
      final Finder weight = find
          .descendant(
            of: find.byType(DraftSetRow).first,
            matching: find.byType(TextField),
          )
          .first;
      expect(tester.widget<TextField>(weight).controller!.text, '997.5');
    });
  }
}

/// Scrolls the main scrollable to the end and back, so lazily built rows
/// are laid out too.
Future<void> _scrollThrough(WidgetTester tester) async {
  final Finder scrollables = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  if (scrollables.evaluate().isEmpty) return;
  final Finder main = scrollables.first;
  for (int i = 0; i < 6; i++) {
    await tester.drag(main, const Offset(0, -600), warnIfMissed: false);
    await pumpFor(tester, const Duration(milliseconds: 300));
  }
  for (int i = 0; i < 6; i++) {
    await tester.drag(main, const Offset(0, 600), warnIfMissed: false);
    await pumpFor(tester, const Duration(milliseconds: 200));
  }
}
