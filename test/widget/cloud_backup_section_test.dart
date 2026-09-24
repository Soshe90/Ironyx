import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/router/routes.dart';
import 'package:ironyx/features/auth/domain/auth_controller.dart';
import 'package:ironyx/features/auth/domain/auth_service.dart';
import 'package:ironyx/features/backup/domain/cloud_backup_controller.dart';
import 'package:ironyx/features/backup/domain/cloud_backup_service.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/pump_app.dart';

/// A backend with a backup waiting whose download is supplied per test.
class _FakeBackupService implements CloudBackupService {
  _FakeBackupService(this._download);

  final Future<String> Function() _download;
  int downloads = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<CloudBackupInfo?> head() async => CloudBackupInfo(
        updatedAt: DateTime(2026, 9, 1),
        sizeBytes: 2048,
        appVersion: '1.0.0',
        dbSchemaVersion: 1,
      );

  @override
  Future<CloudBackupInfo> upload({
    required String payload,
    required String appVersion,
    required int dbSchemaVersion,
  }) =>
      throw UnimplementedError();

  @override
  Future<String> download() {
    downloads++;
    return _download();
  }
}

void main() {
  const Map<String, Object> seededPrefs = <String, Object>{
    'exercise_seed_version': 999999,
    'program_seed_version': 999999,
  };

  late AppDatabase database;
  late FakeAuthService auth;

  setUp(() {
    database = AppDatabase.forTesting();
    auth = FakeAuthService(
      initialUser: const AuthUser(
        id: 'user-1',
        email: 'tester@example.com',
        isEmailConfirmed: true,
      ),
    );
  });

  Future<void> pumpSettings(
    WidgetTester tester,
    CloudBackupService cloud,
  ) async {
    await pumpApp(
      tester,
      initialLocation: Routes.settings,
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        authServiceProvider.overrideWithValue(auth),
        cloudBackupServiceProvider.overrideWithValue(cloud),
        // The path_provider channel is not registered in a widget test, so
        // the real provider never completes. Every download below fails
        // before the path is used.
        snapshotDirectoryProvider.overrideWith((ref) async => 'unused'),
      ],
      prefs: seededPrefs,
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Restore from my account'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> startRestore(WidgetTester tester) async {
    await tester.tap(find.text('Restore from my account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
  }

  ListTile tileTitled(WidgetTester tester, String title) => tester.widget(
        find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
      );

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    auth.dispose();
    await database.close();
  }

  testWidgets(
      'a restore that fails unexpectedly tells the user instead of leaving '
      '"Restoring…" on screen', (tester) async {
    // An error nothing upstream translates, standing in for a disk error
    // writing the pre-import snapshot or a database error mid-restore.
    await pumpSettings(
      tester,
      _FakeBackupService(() async => throw StateError('disk full')),
    );

    await startRestore(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Restoring…'), findsNothing);
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets(
      'while a restore runs, neither restore nor backup can be started, and '
      'both come back when it ends', (tester) async {
    final Completer<String> download = Completer<String>();
    final _FakeBackupService cloud = _FakeBackupService(() => download.future);
    await pumpSettings(tester, cloud);

    await startRestore(tester);
    // Settles the dialog's exit animation; the download stays pending.
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(cloud.downloads, 1);
    expect(tileTitled(tester, 'Restore from my account').enabled, isFalse);
    expect(tileTitled(tester, 'Back up now').enabled, isFalse);

    // A second tap must not reach the confirmation dialog at all.
    await tester.tap(
      find.text('Restore from my account'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(cloud.downloads, 1);

    // Finish the restore. A failed download ends it without reaching the
    // parser, which runs on a background isolate that a widget test's fake
    // clock never waits for.
    download.completeError(
      const CloudBackupFailure(CloudBackupFailureKind.offline),
    );
    await tester.pumpAndSettle();

    expect(tileTitled(tester, 'Restore from my account').enabled, isTrue);
    expect(tileTitled(tester, 'Back up now').enabled, isTrue);

    await disposeApp(tester);
  });
}
