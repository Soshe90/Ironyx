import 'package:fittrack/app.dart';
import 'package:fittrack/core/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// M1 smoke journey. Expanded in M3 into the three journeys named in the
/// build plan: log a workout, run a timer, view progress.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boots and reaches every destination', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const FitTrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    for (final String label in <String>[
      'Tracker',
      'Library',
      'Timer',
      'Progress',
      'Home',
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
