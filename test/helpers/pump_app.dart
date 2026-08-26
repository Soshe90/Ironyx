import 'package:fittrack/app.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/router/app_router.dart';
import 'package:fittrack/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Boots the real app with an in-memory preferences store.
///
/// [initialLocation] lets a test start on any route without tapping
/// through the shell first.
Future<void> pumpApp(
  WidgetTester tester, {
  String initialLocation = '/',
  Map<String, Object> prefs = const <String, Object>{},
  List<dynamic> overrides = const [],
  Size surfaceSize = const Size(400, 800),
  bool settle = true,
  bool awaitDatabase = false,
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(prefs);
  final SharedPreferences instance = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(instance),
        ...overrides.cast(),
      ],
      child: FitTrackApp(
        router: createRouter(initialLocation: initialLocation),
      ),
    ),
  );
  // A fixed pump avoids waiting forever on intentionally animated loading
  // placeholders (`LoadingShimmer` never stops) while still letting route
  // transitions run.
  await tester.pump(const Duration(seconds: 2));

  if (awaitDatabase) {
    // Drift queries are real asynchronous work against a real sqlite3 handle.
    // `tester.pump` only advances the *fake* clock and drains microtasks, so
    // without a slice of genuine wall-clock time the query never completes
    // and a stream-backed screen stays on its loading shimmer forever.
    //
    // Opt-in rather than automatic: letting that I/O run also lets Drift's
    // stream cache schedule the keep-alive timer that the test binding then
    // reports as still pending, so a caller that asks for this owes the
    // matching teardown (see `disposeApp` in the tests that use it).
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

/// Wraps a single widget in the minimum needed to render it.
Future<void> pumpWidgetUnderTest(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  Size surfaceSize = const Size(400, 800),
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: theme,
        // Widgets under test read `context.l10n`, which needs the same
        // delegates the real app installs.
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
  // Lets the delegates resolve before the caller starts asserting.
  await tester.pump();
}
