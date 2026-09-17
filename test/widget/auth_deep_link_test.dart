import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/profile_dao.dart';
import 'package:ironyx/core/database/tables/profiles.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/features/auth/domain/auth_controller.dart';
import 'package:ironyx/features/auth/domain/auth_service.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/pump_app.dart';

/// Confirming an email arrives as a session pushed in from outside the app:
/// `supabase_flutter` follows the deep link, exchanges the `?code=` and emits
/// on `onAuthStateChange` with no auth screen on top to react. These cover
/// what the app has to do about that on its own.
void main() {
  late AppDatabase database;
  late ProfileDao dao;
  late FakeAuthService auth;

  const Map<String, Object> seededPrefs = <String, Object>{
    'exercise_seed_version': 999999,
    'program_seed_version': 999999,
    'onboarding_complete': true,
  };

  setUp(() {
    database = AppDatabase.forTesting();
    dao = ProfileDao(database);
    auth = FakeAuthService();
  });

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    auth.dispose();
    await database.close();
  }

  Future<void> pumpDashboard(WidgetTester tester) async {
    await pumpApp(
      tester,
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        authServiceProvider.overrideWithValue(auth),
      ],
      prefs: seededPrefs,
    );
  }

  testWidgets('a session arriving by deep link links the local profile',
      (tester) async {
    await pumpDashboard(tester);

    // Nobody has signed in through a form; the profile is unlinked.
    expect((await dao.get())?.remoteUserId, isNull);

    // What confirming the email from a mail app looks like from in here.
    auth.emitExternalChange(
      const AuthUser(
        id: 'user-42',
        email: 'lifter@example.com',
        isEmailConfirmed: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final Profile? profile = await dao.get();
    expect(profile?.remoteUserId, 'user-42');
    expect(profile?.email, 'lifter@example.com');

    await disposeApp(tester);
  });

  testWidgets('a token refresh for the same user does not rewrite the profile',
      (tester) async {
    await pumpDashboard(tester);

    const AuthUser user = AuthUser(
      id: 'user-42',
      email: 'lifter@example.com',
      isEmailConfirmed: true,
    );
    auth.emitExternalChange(user);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // A guest who had already filled in their details keeps them; the guard
    // is what stops a re-emitted session from touching the row at all.
    await dao.upsert(
      const ProfilesTableCompanion(displayName: Value('Mustafa')),
    );

    auth.emitExternalChange(user);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final Profile? profile = await dao.get();
    expect(profile?.displayName, 'Mustafa');
    expect(profile?.remoteUserId, 'user-42');

    await disposeApp(tester);
  });

  testWidgets('signing out leaves the local details in place', (tester) async {
    await pumpDashboard(tester);

    auth.emitExternalChange(
      const AuthUser(
        id: 'user-42',
        email: 'lifter@example.com',
        isEmailConfirmed: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // A null session must not be mistaken for a new account to link.
    auth.emitExternalChange(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect((await dao.get())?.remoteUserId, 'user-42');

    await disposeApp(tester);
  });
}
