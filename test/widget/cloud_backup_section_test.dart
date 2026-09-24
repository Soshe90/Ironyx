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

/// A backend with a backup waiting whose download fails with an error the
/// service layer did not translate — standing in for any failure nothing
/// upstream maps (a disk error writing the pre-import snapshot, a database
/// error mid-restore).
class _UnmappedFailureBackupService implements CloudBackupService {
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
  Future<String> download() async => throw StateError('disk full');
}

void main() {
  const Map<String, Object> seededPrefs = <String, Object>{
    'exercise_seed_version': 999999,
    'program_seed_version': 999999,
  };

  testWidgets(
      'a restore that fails unexpectedly tells the user instead of leaving '
      '"Restoring…" on screen', (tester) async {
    final AppDatabase database = AppDatabase.forTesting();
    final FakeAuthService auth = FakeAuthService(
      initialUser: const AuthUser(
        id: 'user-1',
        email: 'tester@example.com',
        isEmailConfirmed: true,
      ),
    );

    await pumpApp(
      tester,
      initialLocation: Routes.settings,
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        authServiceProvider.overrideWithValue(auth),
        cloudBackupServiceProvider
            .overrideWithValue(_UnmappedFailureBackupService()),
        // The path_provider channel is not registered in a widget test, so
        // the real provider never completes. The download fails before the
        // path is used.
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
    await tester.tap(find.text('Restore from my account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Restoring…'), findsNothing);
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    auth.dispose();
    await database.close();
  });
}
