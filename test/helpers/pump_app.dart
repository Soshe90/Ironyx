import 'package:fittrack/app.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/router/app_router.dart';
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
  // placeholders while still allowing route transitions and Drift streams to
  // initialize.
  await tester.pump(const Duration(seconds: 2));
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
        home: Scaffold(body: child),
      ),
    ),
  );
}
