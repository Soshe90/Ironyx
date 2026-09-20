import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/features/auth/domain/auth_controller.dart';
import 'package:ironyx/features/auth/domain/auth_service.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/pump_app.dart';

/// A password-reset link opens the app, which has to notice and ask for the
/// new password — the link itself only establishes a recovery session.
void main() {
  late AppDatabase database;
  late FakeAuthService auth;

  const Map<String, Object> seededPrefs = <String, Object>{
    'exercise_seed_version': 999999,
    'program_seed_version': 999999,
    'onboarding_complete': true,
  };

  const AuthUser user = AuthUser(
    id: 'user-1',
    email: 'lifter@example.com',
    isEmailConfirmed: true,
  );

  setUp(() {
    database = AppDatabase.forTesting();
    auth = FakeAuthService(initialUser: user)
      ..accounts['lifter@example.com'] = 'old-password';
  });

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    auth.dispose();
    await database.close();
  }

  Future<void> pumpWithAuth(WidgetTester tester) => pumpApp(
        tester,
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          authServiceProvider.overrideWithValue(auth),
        ],
        prefs: seededPrefs,
      );

  Future<void> enterPasswords(
    WidgetTester tester, {
    required String password,
    required String confirm,
  }) async {
    final Finder fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), password);
    await tester.enterText(fields.at(1), confirm);
    await tester.pump();
  }

  testWidgets('following a reset link while running opens the screen',
      (tester) async {
    await pumpWithAuth(tester);
    expect(find.text('Set a new password'), findsNothing);

    auth.openRecoveryLink();
    await tester.pumpAndSettle();

    expect(find.text('Set a new password'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a cold start from the link opens the screen', (tester) async {
    auth.startWithRecoveryPending();
    await pumpWithAuth(tester);
    await tester.pumpAndSettle();

    expect(find.text('Set a new password'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a second link does not stack a second screen', (tester) async {
    await pumpWithAuth(tester);

    auth.openRecoveryLink();
    await tester.pumpAndSettle();
    auth.openRecoveryLink();
    await tester.pumpAndSettle();

    expect(find.text('Set a new password'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('saving a valid new password updates it and leaves',
      (tester) async {
    await pumpWithAuth(tester);
    auth.openRecoveryLink();
    await tester.pumpAndSettle();

    await enterPasswords(
      tester,
      password: 'brand-new-pass',
      confirm: 'brand-new-pass',
    );
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();

    expect(auth.passwordsUpdated, <String>['brand-new-pass']);
    expect(auth.isPasswordRecoveryPending, isFalse);
    expect(find.text('Set a new password'), findsNothing);
    expect(find.text('Password updated.'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a too-short or mismatched password never reaches the backend',
      (tester) async {
    await pumpWithAuth(tester);
    auth.openRecoveryLink();
    await tester.pumpAndSettle();

    await enterPasswords(tester, password: 'short', confirm: 'short');
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 8 characters.'), findsOneWidget);

    await enterPasswords(
      tester,
      password: 'long-enough-1',
      confirm: 'long-enough-2',
    );
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();
    expect(find.text("Passwords don't match."), findsOneWidget);

    expect(auth.passwordsUpdated, isEmpty);

    await disposeApp(tester);
  });

  testWidgets('reusing the old password is reported as such', (tester) async {
    await pumpWithAuth(tester);
    auth.openRecoveryLink();
    await tester.pumpAndSettle();

    await enterPasswords(
      tester,
      password: 'old-password',
      confirm: 'old-password',
    );
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();

    expect(find.text("That's already your password. Choose a new one."),
        findsOneWidget);
    // Still on the form, so the user can pick another.
    expect(find.text('Set a new password'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('an expired link says so and offers a new one', (tester) async {
    await pumpWithAuth(tester);
    auth.openRecoveryLink();
    await tester.pumpAndSettle();
    // The recovery session goes away between opening the screen and saving.
    auth.expireRecoverySession();

    await enterPasswords(
      tester,
      password: 'brand-new-pass',
      confirm: 'brand-new-pass',
    );
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This reset link has expired or was already used. Request a new one.',
      ),
      findsOneWidget,
    );
    expect(find.text('Request a new link'), findsOneWidget);

    await tester.tap(find.text('Request a new link'));
    await tester.pumpAndSettle();
    expect(find.text('Reset password'), findsWidgets);

    await disposeApp(tester);
  });

  testWidgets('"Not now" returns without changing anything', (tester) async {
    await pumpWithAuth(tester);
    auth.openRecoveryLink();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(find.text('Set a new password'), findsNothing);
    expect(auth.passwordsUpdated, isEmpty);

    await disposeApp(tester);
  });
}
