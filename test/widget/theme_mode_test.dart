import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  ThemeMode themeModeOf(WidgetTester tester) {
    final MaterialApp app = tester.widget(find.byType(MaterialApp));
    return app.themeMode ?? ThemeMode.system;
  }

  group('theme preference', () {
    testWidgets('defaults to system when nothing is stored', (tester) async {
      await pumpApp(tester, initialLocation: '/settings');
      expect(themeModeOf(tester), ThemeMode.system);
    });

    testWidgets('restores a stored preference on launch', (tester) async {
      await pumpApp(
        tester,
        initialLocation: '/settings',
        prefs: <String, Object>{'theme_mode': 'dark'},
      );
      expect(themeModeOf(tester), ThemeMode.dark);
    });

    testWidgets('selecting a mode updates the app theme', (tester) async {
      await pumpApp(tester, initialLocation: '/settings');

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(themeModeOf(tester), ThemeMode.dark);
    });

    testWidgets('an unrecognised stored value falls back to system',
        (tester) async {
      await pumpApp(
        tester,
        initialLocation: '/settings',
        prefs: <String, Object>{'theme_mode': 'sepia'},
      );
      expect(themeModeOf(tester), ThemeMode.system);
    });
  });
}
