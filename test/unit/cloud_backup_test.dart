import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/features/auth/domain/auth_controller.dart';
import 'package:ironyx/features/auth/domain/auth_service.dart';
import 'package:ironyx/features/backup/domain/cloud_backup_controller.dart';
import 'package:ironyx/features/backup/domain/cloud_backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_auth_service.dart';

/// In-memory stand-in for the Supabase-backed service. Nothing in the test
/// suite may reach the network, so this is the seam every test overrides.
class FakeCloudBackupService implements CloudBackupService {
  FakeCloudBackupService();

  String? payload;
  CloudBackupInfo? info;
  int uploads = 0;
  CloudBackupFailure? failWith;

  /// Stands in for network time, so a test can observe what happens to the
  /// caller while an upload is still in flight.
  Duration uploadDelay = Duration.zero;

  @override
  bool get isAvailable => true;

  @override
  Future<CloudBackupInfo?> head() async {
    if (failWith != null) throw failWith!;
    return info;
  }

  @override
  Future<CloudBackupInfo> upload({
    required String payload,
    required String appVersion,
    required int dbSchemaVersion,
  }) async {
    if (failWith != null) throw failWith!;
    if (uploadDelay > Duration.zero) await Future<void>.delayed(uploadDelay);
    uploads++;
    this.payload = payload;
    return info = CloudBackupInfo(
      updatedAt: DateTime.now(),
      sizeBytes: payload.length,
      appVersion: appVersion,
      dbSchemaVersion: dbSchemaVersion,
    );
  }

  @override
  Future<String> download() async {
    if (failWith != null) throw failWith!;
    final String? stored = payload;
    if (stored == null) {
      throw const CloudBackupFailure(CloudBackupFailureKind.noBackupYet);
    }
    return stored;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cloud backup', () {
    late AppDatabase database;
    late FakeCloudBackupService cloud;
    late String snapshotDir;
    late ProviderContainer container;

    Future<void> seedWorkout(AppDatabase db, String id, double weight) async {
      await WorkoutDao(db).insertWorkout(
        WorkoutsTableCompanion.insert(
          id: id,
          startedAt: DateTime(2026, 8, 1),
          totalVolumeKg: Value(weight * 5),
        ),
        <WorkoutExercisesTableCompanion>[
          WorkoutExercisesTableCompanion.insert(
            id: 'we_$id',
            workoutId: id,
            exerciseId: 'ex_001',
            orderIndex: 0,
          ),
        ],
        <WorkoutSetsTableCompanion>[
          WorkoutSetsTableCompanion.insert(
            id: 'set_$id',
            workoutExerciseId: 'we_$id',
            setIndex: 0,
            weightKg: weight,
            reps: 5,
            isCompleted: const Value(true),
          ),
        ],
      );
    }

    Future<void> seedCatalogue(AppDatabase db) =>
        ExerciseDao(db).upsertExercises(<ExercisesTableCompanion>[
          ExercisesTableCompanion.insert(
            id: 'ex_001',
            slug: 'bench',
            name: 'Bench Press',
            category: 'strength',
            difficulty: 'intermediate',
            movementPattern: 'horizontalPush',
            seedVersion: 1,
          ),
        ]);

    Future<ProviderContainer> containerFor(
      AppDatabase db, {
      AuthUser? user = const AuthUser(
        id: 'user-1',
        email: 'tester@example.com',
        isEmailConfirmed: true,
      ),
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      return ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          cloudBackupServiceProvider.overrideWithValue(cloud),
          // applyImport writes a pre-import snapshot; the path_provider
          // channel is not registered in a unit test.
          snapshotDirectoryProvider.overrideWith((ref) async => snapshotDir),
          authServiceProvider
              .overrideWithValue(FakeAuthService(initialUser: user)),
        ],
      );
    }

    setUp(() async {
      database = AppDatabase.forTesting();
      cloud = FakeCloudBackupService();
      final Directory dir =
          Directory.systemTemp.createTempSync('ironyx_backup_test');
      snapshotDir = dir.path;
      addTearDown(() => dir.deleteSync(recursive: true));
      await seedCatalogue(database);
    });

    tearDown(() async {
      container.dispose();
      await database.close();
    });

    test('backUpNow uploads the whole database', () async {
      await seedWorkout(database, 'w1', 100);
      container = await containerFor(database);

      final CloudBackupInfo info = await container
          .read(cloudBackupControllerProvider.notifier)
          .backUpNow();

      expect(cloud.uploads, 1);
      expect(info.dbSchemaVersion, database.schemaVersion);
      // The payload is the ADR-7 envelope, not a bespoke format — the whole
      // point of reusing it is that restore already knows how to validate.
      expect(cloud.payload, contains('formatVersion'));
      expect(cloud.payload, contains('w1'));
    });

    test('backUpNow refuses when local data is linked to a different account',
        () async {
      // The scenario this guards: a deep link (email confirmation) can
      // authenticate a different account than whichever one this device's
      // profile was last linked to, bypassing the interactive sign-in/
      // sign-up conflict dialog entirely (see `app.dart`'s
      // `_linkIfNoConflict`). Uploading regardless would write this
      // device's data into the wrong account's backup slot.
      await seedWorkout(database, 'w1', 100);
      container = await containerFor(
        database,
        user: const AuthUser(
          id: 'user-2',
          email: 'other@example.com',
          isEmailConfirmed: true,
        ),
      );
      await container.read(profileDaoProvider).linkAccount(
            userId: 'user-1',
            email: 'tester@example.com',
          );

      await expectLater(
        container.read(cloudBackupControllerProvider.notifier).backUpNow(),
        throwsA(
          isA<CloudBackupFailure>().having(
            (f) => f.kind,
            'kind',
            CloudBackupFailureKind.accountMismatch,
          ),
        ),
      );
      expect(cloud.uploads, 0);
    });

    test(
        'restoreFromCloud refuses when local data is linked to a different '
        'account, before downloading or replacing anything', () async {
      // Same deep-link scenario as the backup guard above, in the other
      // direction: restoring would replace user-1's data on this device
      // with user-2's backup without the conflict dialog ever asking.
      await seedWorkout(database, 'local_w', 100);
      cloud.payload = 'unreachable if the guard works';
      container = await containerFor(
        database,
        user: const AuthUser(
          id: 'user-2',
          email: 'other@example.com',
          isEmailConfirmed: true,
        ),
      );
      await container.read(profileDaoProvider).linkAccount(
            userId: 'user-1',
            email: 'tester@example.com',
          );

      await expectLater(
        container
            .read(cloudBackupControllerProvider.notifier)
            .restoreFromCloud(),
        throwsA(
          isA<CloudBackupFailure>().having(
            (f) => f.kind,
            'kind',
            CloudBackupFailureKind.accountMismatch,
          ),
        ),
      );
      final local = await WorkoutDao(database).watchAll().first;
      expect(local.map((w) => w.id), ['local_w']);
    });

    test('backUpNow completes even though nothing listens to the controller',
        () async {
      // The regression this guards: Settings reads the notifier from a tap
      // handler and keeps no reference, so an auto-disposing controller was
      // torn down mid-upload and the `ref` use afterwards threw. The UI
      // reported a generic failure while the tile still said "No backup
      // yet" — a backup that looked like it ran and hadn't.
      await seedWorkout(database, 'w1', 100);
      container = await containerFor(database);
      cloud.uploadDelay = const Duration(milliseconds: 50);

      final Future<CloudBackupInfo> pending =
          container.read(cloudBackupControllerProvider.notifier).backUpNow();
      // Give auto-dispose a chance to fire while the upload is in flight.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final CloudBackupInfo info = await pending;
      expect(cloud.uploads, 1);
      expect(info.sizeBytes, greaterThan(0));
    });

    test('a backup restores onto a fresh install', () async {
      // Back up from one device...
      await seedWorkout(database, 'w1', 100);
      await seedWorkout(database, 'w2', 120);
      container = await containerFor(database);
      await container.read(cloudBackupControllerProvider.notifier).backUpNow();
      container.dispose();

      // ...then restore onto an empty one, which is the actual scenario:
      // uninstall, reinstall, sign in, get the data back.
      final AppDatabase fresh = AppDatabase.forTesting();
      addTearDown(fresh.close);
      await seedCatalogue(fresh);
      expect(await WorkoutDao(fresh).watchAll().first, isEmpty);

      container = await containerFor(fresh);
      await container
          .read(cloudBackupControllerProvider.notifier)
          .restoreFromCloud();

      final restored = await WorkoutDao(fresh).watchAll().first;
      expect(restored.map((w) => w.id), containsAll(['w1', 'w2']));
    });

    test('restore replaces local data rather than merging it', () async {
      await seedWorkout(database, 'from_backup', 100);
      container = await containerFor(database);
      await container.read(cloudBackupControllerProvider.notifier).backUpNow();
      container.dispose();

      final AppDatabase other = AppDatabase.forTesting();
      addTearDown(other.close);
      await seedCatalogue(other);
      await seedWorkout(other, 'local_only', 60);

      container = await containerFor(other);
      await container
          .read(cloudBackupControllerProvider.notifier)
          .restoreFromCloud();

      final ids =
          (await WorkoutDao(other).watchAll().first).map((w) => w.id).toSet();
      expect(ids, contains('from_backup'));
      expect(
        ids,
        isNot(contains('local_only')),
        reason: 'replace mode must not leave the device\'s own rows behind — '
            'that would be a merge, which this feature deliberately is not',
      );
    });

    test('a corrupt payload fails as corrupt, not as a parser crash', () async {
      container = await containerFor(database);
      cloud.payload = 'this is not an export envelope';

      await expectLater(
        container
            .read(cloudBackupControllerProvider.notifier)
            .restoreFromCloud(),
        throwsA(
          isA<CloudBackupFailure>().having(
            (f) => f.kind,
            'kind',
            CloudBackupFailureKind.corrupt,
          ),
        ),
      );
    });

    test(
        'a backup from a newer schema fails as corrupt and leaves '
        'local data untouched', () async {
      await seedWorkout(database, 'w1', 100);
      container = await containerFor(database);
      await container.read(cloudBackupControllerProvider.notifier).backUpNow();
      await seedWorkout(database, 'w_local', 60);

      // A backup taken on a newer app version (e.g. another device that
      // updated first). `parseImport` accepts it; only `applyImport` knows
      // this build cannot read that schema. Older schemas are upgraded
      // instead — see export_schema_upgrade_test.dart.
      cloud.payload = cloud.payload!.replaceFirst(
        '"dbSchemaVersion":${database.schemaVersion}',
        '"dbSchemaVersion":${database.schemaVersion + 1}',
      );

      await expectLater(
        container
            .read(cloudBackupControllerProvider.notifier)
            .restoreFromCloud(),
        throwsA(
          isA<CloudBackupFailure>().having(
            (f) => f.kind,
            'kind',
            CloudBackupFailureKind.corrupt,
          ),
        ),
      );
      final local = await WorkoutDao(database).watchAll().first;
      expect(local.map((w) => w.id), containsAll(['w1', 'w_local']));
    });

    test('status is null when signed out, without calling the backend',
        () async {
      container = await containerFor(database, user: null);
      cloud.info = CloudBackupInfo(
        updatedAt: DateTime.now(),
        sizeBytes: 10,
        appVersion: '0.1.0',
        dbSchemaVersion: 9,
      );

      expect(await container.read(cloudBackupStatusProvider.future), isNull);
    });

    test('a build without credentials degrades instead of throwing', () async {
      const CloudBackupService disabled = DisabledCloudBackupService();

      expect(disabled.isAvailable, isFalse);
      expect(await disabled.head(), isNull);
      await expectLater(
        disabled.download(),
        throwsA(
          isA<CloudBackupFailure>().having(
            (f) => f.kind,
            'kind',
            CloudBackupFailureKind.notConfigured,
          ),
        ),
      );
    });
  });
}
