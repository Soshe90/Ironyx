import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/app.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/core/router/routes.dart';
import 'package:ironyx/features/auth/domain/auth_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/pump_app.dart';

/// The first-launch welcome screen and the three ways out of it.
void main() {
  late AppDatabase database;
  late FakeAuthService auth;

  // Pins the seeders so a launch does not spend the test's pump budget
  // populating exercises and programs.
  const Map<String, Object> seededPrefs = <String, Object>{
    'exercise_seed_version': 999999,
    'program_seed_version': 999999,
  };

  setUp(() {
    database = AppDatabase.forTesting();
    auth = FakeAuthService();
  });

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    auth.dispose();
    await database.close();
  }

  Future<void> pumpWelcome(
    WidgetTester tester, {
    Map<String, Object> prefs = seededPrefs,
    bool accountsAvailable = true,
  }) async {
    if (!accountsAvailable) {
      auth = FakeAuthService(available: false);
    }
    await pumpApp(
      tester,
      initialLocation: Routes.welcome,
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        authServiceProvider.overrideWithValue(auth),
      ],
      prefs: prefs,
    );
  }

  testWidgets('introduces the app and offers all three ways in',
      (tester) async {
    await pumpWelcome(tester);

    expect(find.text('Ironyx'), findsOneWidget);
    expect(find.text('Your training, tracked.'), findsOneWidget);
    expect(find.text('Log every set and rep'), findsOneWidget);
    expect(find.text('Charts that show progress'), findsOneWidget);

    expect(find.text('Create a free account'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
    expect(find.text('Continue without an account'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('tells the truth about where guest data lives', (tester) async {
    await pumpWelcome(tester);

    // ADR-8: an account carries identity only. The notice must point at the
    // export, which is the only thing that survives an uninstall, and must
    // not claim that registering protects workouts.
    final Finder notice = find.textContaining('stay on this device');
    expect(notice, findsOneWidget);
    expect(find.textContaining('save a backup from Settings'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('continuing as a guest lands on the dashboard', (tester) async {
    await pumpWelcome(tester);

    await tester.tap(find.text('Continue without an account'));
    await tester.pumpAndSettle();

    expect(find.text('Continue without an account'), findsNothing);
    // The shell, and therefore the bottom navigation, is now on screen.
    expect(find.byType(NavigationBar), findsOneWidget);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_complete'), isTrue);

    await disposeApp(tester);
  });

  testWidgets('creating an account opens the sign-up form over the dashboard',
      (tester) async {
    await pumpWelcome(tester);

    await tester.tap(find.text('Create a free account'));
    await tester.pumpAndSettle();

    expect(find.text('Create account'), findsWidgets);

    // Backing out of the form reaches the app, not the welcome screen it
    // already dismissed.
    final NavigatorState navigator = tester.state(find.byType(Navigator).first);
    navigator.pop();
    await tester.pumpAndSettle();

    expect(find.text('Create a free account'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a build without credentials offers only Get started',
      (tester) async {
    await pumpWelcome(tester, accountsAvailable: false);

    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Create a free account'), findsNothing);
    expect(find.text('I already have an account'), findsNothing);

    await disposeApp(tester);
  });

  /// Boots the real [IronyxApp] with **no** injected router, so that
  /// `app.dart` picks the launch location from the persisted flag itself.
  /// The other tests supply a router and would skip that decision entirely.
  Future<void> pumpRealLaunch(
    WidgetTester tester, {
    required Map<String, Object> prefs,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(prefs);
    final SharedPreferences instance = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(instance),
          appDatabaseProvider.overrideWithValue(database),
          authServiceProvider.overrideWithValue(auth),
        ],
        child: const IronyxApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('a fresh install launches on the welcome screen', (tester) async {
    await pumpRealLaunch(tester, prefs: seededPrefs);

    expect(find.text('Your training, tracked.'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('a returning user launches straight into the dashboard',
      (tester) async {
    await pumpRealLaunch(
      tester,
      prefs: <String, Object>{...seededPrefs, 'onboarding_complete': true},
    );

    expect(find.text('Your training, tracked.'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);

    await disposeApp(tester);
  });
}
