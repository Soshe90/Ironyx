import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  ThemeMode themeModeOf(WidgetTester tester) {
    final MaterialApp app = tester.widget(find.byType(MaterialApp));
    return app.themeMode ?? ThemeMode.system;
  }

  group('theme preference', () {
    testWidgets('defaults to dark when nothing is stored', (tester) async {
      await pumpApp(tester, initialLocation: '/settings');
      expect(themeModeOf(tester), ThemeMode.dark);
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

      // Settings grew a Language section above Appearance, so the theme
      // control now starts below the fold and the ListView has not built it
      // yet.
      // Light, not Dark: dark is already the default, so tapping it would
      // pass without anything changing.
      await tester.scrollUntilVisible(find.text('Light'), 200);
      // scrollUntilVisible stops as soon as any sliver of the label is on
      // screen, which can leave the tap point off it; bring it fully in.
      await tester.ensureVisible(find.text('Light'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      expect(themeModeOf(tester), ThemeMode.light);
    });

    testWidgets('an unrecognised stored value falls back to dark',
        (tester) async {
      await pumpApp(
        tester,
        initialLocation: '/settings',
        prefs: <String, Object>{'theme_mode': 'sepia'},
      );
      expect(themeModeOf(tester), ThemeMode.dark);
    });
  });
}
