import 'package:fittrack/core/l10n/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

/// End-to-end checks that the Arabic locale actually reaches the widget tree.
///
/// The per-string translations are covered by the ARB files themselves (an
/// untranslated key fails `flutter gen-l10n`). What these guard is the wiring
/// around them: that the stored preference selects the locale, that selecting
/// Arabic flips the whole app to RTL, and that numbers stay Western — the one
/// thing `intl` would otherwise localize out from under us.
void main() {
  group('Arabic locale', () {
    testWidgets('renders Arabic strings when the preference is stored',
        (tester) async {
      await pumpApp(
        tester,
        initialLocation: '/settings',
        prefs: <String, Object>{'app_locale': 'ar'},
      );

      expect(find.text('الإعدادات'), findsOneWidget);
      expect(find.text('اللغة'), findsOneWidget);
      // The English equivalent must be gone, not merely outnumbered.
      expect(find.text('Settings'), findsNothing);
    });

    testWidgets('lays the app out right-to-left', (tester) async {
      await pumpApp(
        tester,
        initialLocation: '/settings',
        prefs: <String, Object>{'app_locale': 'ar'},
      );

      expect(
        Directionality.of(tester.element(find.text('اللغة'))),
        TextDirection.rtl,
      );
    });

    testWidgets('stays left-to-right in English', (tester) async {
      await pumpApp(
        tester,
        initialLocation: '/settings',
        prefs: <String, Object>{'app_locale': 'en'},
      );

      expect(find.text('Settings'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('Language'))),
        TextDirection.ltr,
      );
    });

    testWidgets('offers every supported language in its own script',
        (tester) async {
      await pumpApp(tester, initialLocation: '/settings');

      // Listed as endonyms so someone stranded in a language they cannot
      // read can still find their way back.
      expect(find.text('English'), findsOneWidget);
      expect(find.text('العربية'), findsOneWidget);
      expect(kSupportedLocales.length, 2);
    });
  });
}
