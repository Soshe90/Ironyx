import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/profile_dao.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/core/router/routes.dart';
import 'package:ironyx/core/services/data_export_service.dart';
import 'package:ironyx/features/auth/domain/auth_controller.dart';
import 'package:ironyx/features/auth/domain/auth_service.dart';
import 'package:ironyx/features/backup/domain/cloud_backup_controller.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/pump_app.dart';
import '../helpers/stub_seeders.dart';

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

  Future<void> pumpSettings(
    WidgetTester tester, {
    List<dynamic> overrides = const [],
  }) async {
    await pumpApp(
      tester,
      initialLocation: Routes.settings,
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        authServiceProvider.overrideWithValue(auth),
        ...overrides,
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

  testWidgets(
      'signing in as a different account offers to keep or erase local data '
      '— keeping local data cancels the sign-in', (tester) async {
    await ProfileDao(database).upsert(
      const ProfilesTableCompanion(displayName: Value('Previous Owner')),
    );
    await ProfileDao(database)
        .linkAccount(userId: 'user-existing', email: 'old@example.com');
    auth.accounts['new@example.com'] = 'hunter22';
    await pumpSettings(tester);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'new@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'hunter22',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    // Not `pumpAndSettle`: `_submit` is now suspended waiting on the
    // conflict dialog's choice, which this test hasn't made yet, so the
    // form's busy spinner (an indeterminate `CircularProgressIndicator`)
    // would keep `pumpAndSettle` from ever returning.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The conflict dialog, not the ordinary "signed in" outcome.
    expect(find.text('Different account on this device'), findsOneWidget);

    await tester.tap(find.text('Keep my data'));
    await tester.pumpAndSettle();

    // Reverted: the sign-in that already completed is undone, and the
    // previous owner's data is untouched.
    expect(
      find.text('Sign-in cancelled. Nothing on this device changed.'),
      findsOneWidget,
    );
    final profile = await ProfileDao(database).get();
    expect(profile!.remoteUserId, 'user-existing');
    expect(profile.displayName, 'Previous Owner');

    await disposeApp(tester);
  });

  testWidgets(
      'signing in as a different account offers to keep or erase local data '
      '— erasing wipes local data and links the new account', (tester) async {
    await ProfileDao(database).upsert(
      const ProfilesTableCompanion(displayName: Value('Previous Owner')),
    );
    await ProfileDao(database)
        .linkAccount(userId: 'user-existing', email: 'old@example.com');
    auth.accounts['new@example.com'] = 'hunter22';
    // The erase branch re-triggers the real `programSeederProvider`, which
    // is watched app-wide (`app.dart`) and reseeds built-in programs against
    // a real sqlite3 handle — exercising that reseed race is not what this
    // test is about, so it's stubbed out the same way any other test that
    // isn't itself testing seeding does.
    // The erase also removes the import snapshots, a copy of the old
    // account's data; pointed at a folder the test owns.
    final Directory snapshots =
        Directory.systemTemp.createTempSync('ironyx_conflict_erase');
    addTearDown(() => snapshots.deleteSync(recursive: true));
    File('${snapshots.path}/pre_import_snapshot_1.json')
        .writeAsStringSync('{}');
    await pumpSettings(
      tester,
      overrides: [
        ...stubSeeders(),
        snapshotDirectoryProvider.overrideWith((ref) async => snapshots.path),
      ],
    );

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'new@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'hunter22',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    // See the matching comment in the "keeping local data" test above.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Different account on this device'), findsOneWidget);

    await tester.tap(find.text('Erase local data and continue'));
    // Deleting the snapshots is real file I/O, which only runs outside the
    // test's fake clock: polled, as the Settings delete-all test does.
    for (int i = 0;
        i < 100 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // Back on Settings, now showing the new account.
    expect(find.text('new@example.com'), findsOneWidget);

    expect(snapshots.listSync(), isEmpty,
        reason: "the old account's data must not survive in a snapshot");

    final profile = await ProfileDao(database).get();
    expect(profile!.remoteUserId, isNot('user-existing'));
    expect(profile.email, 'new@example.com');
    expect(
      profile.displayName,
      isNull,
      reason: 'delete-all wipes the profile row entirely, including the '
          'previous owner\'s name',
    );

    await disposeApp(tester);
  });

  testWidgets(
      'signing in as a different account — an erase that fails undoes the '
      'sign-in and says so', (tester) async {
    // Production review 2026-11-12: the erase had no error handling, so a
    // failure escaped the sign-in form (which catches only AuthFailure),
    // leaving the new account signed in, unlinked, over the old account's
    // data, with nothing on screen.
    await ProfileDao(database).upsert(
      const ProfilesTableCompanion(displayName: Value('Previous Owner')),
    );
    await ProfileDao(database)
        .linkAccount(userId: 'user-existing', email: 'old@example.com');
    auth.accounts['new@example.com'] = 'hunter22';
    await pumpSettings(
      tester,
      overrides: [
        ...stubSeeders(),
        dataExportServiceProvider.overrideWithValue(_FailingDelete()),
        snapshotDirectoryProvider.overrideWith((ref) async => 'unused'),
      ],
    );

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'new@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'hunter22',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Erase local data and continue'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text(
        'Something went wrong while deleting your data. Please try again.',
      ),
      findsOneWidget,
    );
    expect(auth.currentUser, isNull, reason: 'the sign-in is undone');
    final profile = await ProfileDao(database).get();
    expect(profile!.remoteUserId, 'user-existing');
    expect(profile.displayName, 'Previous Owner');

    await disposeApp(tester);
  });

  testWidgets(
      'signing in as a different account — an erase that leaves the old '
      "account's snapshots does not link the new one", (tester) async {
    // Review of this branch: a partial erase linked the new account
    // whatever was left, so the old account's snapshots (a full copy of
    // its data) or its open workout stayed under the new account.
    await ProfileDao(database)
        .linkAccount(userId: 'user-existing', email: 'old@example.com');
    auth.accounts['new@example.com'] = 'hunter22';
    await pumpSettings(
      tester,
      overrides: [
        ...stubSeeders(),
        dataExportServiceProvider.overrideWithValue(_FailingSnapshots()),
        snapshotDirectoryProvider.overrideWith((ref) async => 'unused'),
      ],
    );

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'new@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'hunter22',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Erase local data and continue'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
        find.textContaining('Delete all data again to finish'), findsOneWidget);
    expect(auth.currentUser, isNull, reason: 'signed back out');
    expect(await ProfileDao(database).get(), isNull,
        reason: 'the database step ran; nothing was linked after it');

    await disposeApp(tester);
  });

  testWidgets('deleting an account requires confirmation and keeps local data',
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

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account?'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Delete account'), findsOneWidget);

    // The destructive action stays disabled until the exact confirmation word
    // is entered.
    final Finder confirmationField = find.byType(TextField);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Delete account'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(confirmationField, 'DELETE');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Delete account'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    final profile = await ProfileDao(database).get();
    expect(profile!.remoteUserId, isNull);
    expect(profile.displayName, 'Mustafa Salih');

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

  group('account failures are reported', () {
    const AuthUser signedIn = AuthUser(
      id: 'u1',
      email: 'mustafa@example.com',
      isEmailConfirmed: true,
    );

    Future<void> signOutWith(
      WidgetTester tester,
      AuthService service, {
      List<dynamic> overrides = const [],
    }) async {
      await pumpApp(
        tester,
        initialLocation: Routes.settings,
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          authServiceProvider.overrideWithValue(service),
          ...overrides,
        ],
        prefs: seededPrefs,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();
    }

    testWidgets('an unexpected error says something went wrong',
        (tester) async {
      await signOutWith(tester, _ThrowingAuth(signedIn));

      expect(find.text('Something went wrong'), findsOneWidget,
          reason: 'only AuthFailure was caught; this escaped');
      await disposeApp(tester);
    });

    testWidgets('signed out, but not saved on the device, says both',
        (tester) async {
      await signOutWith(
        tester,
        FakeAuthService(initialUser: signedIn),
        overrides: [
          profileDaoProvider.overrideWithValue(_FailingUnlink(database)),
        ],
      );

      expect(
        find.text('Signed out, but saving that on this device failed.'),
        findsOneWidget,
      );
      await disposeApp(tester);
    });

    testWidgets('the delete-account dialog fits with the keyboard open',
        (tester) async {
      await pumpApp(
        tester,
        initialLocation: Routes.settings,
        surfaceSize: const Size(360, 640),
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          authServiceProvider
              .overrideWithValue(FakeAuthService(initialUser: signedIn)),
        ],
        prefs: seededPrefs,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'the dialog overflowed under the keyboard');
      await disposeApp(tester);
    });
  });
}

/// Signed in; signing out fails with an error that is not an AuthFailure.
class _ThrowingAuth extends FakeAuthService {
  _ThrowingAuth(AuthUser user) : super(initialUser: user);

  @override
  Future<void> signOut() => Future<void>.error(StateError('socket closed'));
}

/// Clearing the account from the profile fails.
class _FailingUnlink extends ProfileDao {
  _FailingUnlink(super.db);

  @override
  Future<void> unlinkAccount() => Future<void>.error(StateError('disk full'));
}

/// A delete-all that fails before anything is deleted.
class _FailingDelete extends DataExportService {
  @override
  Future<void> deleteAllUserData(
    AppDatabase db, {
    String? snapshotDirPath,
  }) async =>
      throw StateError('disk full');
}

/// A delete-all whose database step succeeds and snapshot step fails.
class _FailingSnapshots extends DataExportService {
  @override
  Future<void> deleteSnapshots(String snapshotDirPath) async =>
      throw StateError('locked');
}
