import 'dart:async';

import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/config/supabase_config.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/services/data_export_service.dart';
import '../../auth/domain/auth_controller.dart';
import '../../auth/domain/auth_service.dart';
import '../../settings/domain/export_envelope.dart';
import '../data/supabase_cloud_backup_service.dart';
import 'cloud_backup_service.dart';

part 'cloud_backup_controller.g.dart';

/// The backend seam. Overridden with a fake in every test — nothing in the
/// suite may reach the network.
@Riverpod(keepAlive: true)
CloudBackupService cloudBackupService(Ref ref) {
  if (!SupabaseConfig.isConfigured) return const DisabledCloudBackupService();
  try {
    return SupabaseCloudBackupService(sb.Supabase.instance.client);
  } on Object {
    // Configured but `Supabase.initialize` failed and `main` chose to keep
    // launching. Reading `.instance` throws in that state, so degrade
    // rather than crashing Settings.
    return const DisabledCloudBackupService();
  }
}

/// Whether this build can offer cloud backup at all, so the UI can explain
/// itself instead of showing a button that can only fail.
@Riverpod(keepAlive: true)
bool cloudBackupAvailable(Ref ref) =>
    ref.watch(cloudBackupServiceProvider).isAvailable;

/// Where `applyImport` writes its pre-import snapshot.
///
/// A provider rather than a direct `getApplicationSupportDirectory()` call
/// so a unit test can point it at a temp directory — the plugin channel
/// isn't registered outside a widget test, and a restore that cannot be
/// tested is a restore nobody should trust.
@Riverpod(keepAlive: true)
Future<String> snapshotDirectory(Ref ref) async =>
    (await getApplicationSupportDirectory()).path;

/// Metadata for the signed-in account's backup, or null when there is none.
///
/// Re-reads whenever the session changes, so signing in on a fresh install
/// surfaces "a backup is waiting" without the user going looking for it.
@riverpod
Future<CloudBackupInfo?> cloudBackupStatus(Ref ref) async {
  final user = ref.watch(authControllerProvider);
  if (user == null) return null;
  return ref.watch(cloudBackupServiceProvider).head();
}

/// Uploads and restores the whole database against the account's backup
/// slot.
///
/// Both directions reuse the ADR-7 export envelope rather than inventing a
/// second serialization: it is already versioned, already validated, and
/// `applyImport` already takes the pre-import snapshot that makes a restore
/// undoable. A bespoke wire format would have to re-earn all three.
///
/// `keepAlive`, unlike the screen-scoped notifiers elsewhere in the app,
/// because nothing ever *watches* this one: Settings reads it from a tap
/// handler and drops the reference. An auto-disposing notifier is torn down
/// while the upload is still in flight, and every `ref` use after the first
/// await then throws "cannot use Ref after it has been disposed" — a backup
/// that silently fails after the bytes were already on the wire.
@Riverpod(keepAlive: true)
class CloudBackupController extends _$CloudBackupController {
  @override
  void build() {}

  /// Uploads the current database. Throws [CloudBackupFailure].
  Future<CloudBackupInfo> backUpNow() async {
    // Everything `ref` is needed for is read up front, before any await, so
    // this stays correct even if the notifier's lifetime is shortened later.
    final database = ref.read(appDatabaseProvider);
    final CloudBackupService cloud = ref.read(cloudBackupServiceProvider);
    const DataExportService service = DataExportService();

    // Safety net behind the interactive sign-in/sign-up conflict dialog
    // (`AccountConflictFlow`): that dialog only runs on the two screens that
    // trigger it, but a session can also change underneath the app via a
    // deep link (email confirmation), which does not go through either
    // screen. Uploading here regardless would write this device's data —
    // possibly still a *different* account's, never wiped — into whichever
    // account the live session now belongs to.
    final AuthUser? user = ref.read(authControllerProvider);
    if (user != null &&
        await ref.read(profileDaoProvider).hasConflictingAccount(user.id)) {
      throw const CloudBackupFailure(CloudBackupFailureKind.accountMismatch);
    }
    final String payload = await service
        .buildJsonExport(database, indent: false)
        .timeout(const Duration(seconds: 45));

    final CloudBackupInfo info = await cloud
        .upload(
          payload: payload,
          appVersion: kAppVersion,
          dbSchemaVersion: database.schemaVersion,
        )
        .timeout(const Duration(seconds: 45));
    ref.invalidate(cloudBackupStatusProvider);
    return info;
  }

  /// Replaces the local database with the account's backup.
  ///
  /// [ImportMode.replace], not merge: the point is "I reinstalled, give me
  /// my data back", and merging a fresh empty install into a backup would
  /// leave the seeded catalogue fighting the restored one. `applyImport`
  /// snapshots the current database first, so this stays undoable from
  /// Settings even though it overwrites.
  Future<void> restoreFromCloud() async {
    final database = ref.read(appDatabaseProvider);
    final CloudBackupService cloud = ref.read(cloudBackupServiceProvider);
    final String snapshotDir = await ref.read(snapshotDirectoryProvider.future);
    final String payload = await cloud.download();
    const DataExportService service = DataExportService();

    try {
      final ImportEnvelope envelope = service.parseImport(payload);
      // `applyImport` validates too — schema version and every row — and
      // throws the same exception before it touches the database. The
      // realistic trigger is a backup taken before an app update migrated
      // the schema, so it must be translated here as well, not only the
      // parser's.
      await service.applyImport(
        database,
        envelope,
        mode: ImportMode.replace,
        snapshotDirPath: snapshotDir,
      );
    } on ImportValidationException catch (error) {
      // A backup that fails validation is corrupt or from an incompatible
      // build. Either way the user cannot act on the raw parser message.
      throw CloudBackupFailure(
        CloudBackupFailureKind.corrupt,
        detail: error.message,
      );
    }
  }
}
