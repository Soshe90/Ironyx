import 'package:drift/drift.dart' show Value;
import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/daos/profile_dao.dart';
import 'package:fittrack/core/database/database_providers.dart';
import 'package:fittrack/core/router/routes.dart';
import 'package:fittrack/features/auth/domain/auth_controller.dart';
import 'package:fittrack/features/auth/domain/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/pump_app.dart';

/// End-to-end coverage for the Settings account card and the sign-in form.
void main() {
  late AppDatabase database;
  late FakeAuthService auth;

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

  Future<void> pumpSettings(WidgetTester tester) async {
    await pumpApp(
      tester,
      initialLocation: Routes.settings,
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        authServiceProvider.overrideWithValue(auth),
      ],
      prefs: seededPrefs,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('signed out, Settings offers sign in and create account',
      (tester) async {
    await pumpSettings(tester);

    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    // Personal details is available to guests too — the data is local.
    expect(find.text('Personal details'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);

    await disposeApp(tester);
  });

  testWidgets(
      'a build without Supabase credentials says so instead of offering a '
      'button that can only fail', (tester) async {
    await pumpApp(
      tester,
      initialLocation: Routes.settings,
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        authServiceProvider.overrideWithValue(const DisabledAuthService()),
      ],
      prefs: seededPrefs,
    );
    await tester.pumpAndSettle();

    expect(find.text('Accounts unavailable'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    // The rest of Settings must be entirely unaffected.
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Personal details'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('signing in validates, then links the account to the profile',
      (tester) async {
    auth.accounts['mustafa@example.com'] = 'hunter22';
    await pumpSettings(tester);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);

    // Submitting empty must be rejected, not sent.
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your email.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);

    // A wrong password reports itself without clearing the form.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'mustafa@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'wrong-one',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(
      find.text('That email and password don\'t match an account.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'hunter22',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    // Back on Settings, now showing the account.
    expect(find.text('mustafa@example.com'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);

    // And the local profile carries the account id, so the history on this
    // device is associated rather than duplicated.
    final profile = await ProfileDao(database).get();
    expect(profile!.email, 'mustafa@example.com');
    expect(profile.remoteUserId, isNotNull);

    await disposeApp(tester);
  });

  testWidgets('signing out keeps the personal details on the device',
      (tester) async {
    await ProfileDao(database).upsert(
      const ProfilesTableCompanion(displayName: Value('Mustafa Salih')),
    );
    auth.accounts['mustafa@example.com'] = 'hunter22';
    await pumpSettings(tester);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'mustafa@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'hunter22',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);

    final profile = await ProfileDao(database).get();
    expect(profile!.remoteUserId, isNull);
    // Signing out is not deleting.
    expect(profile.displayName, 'Mustafa Salih');

    await disposeApp(tester);
  });
}
