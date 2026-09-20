/// Account-tied backup of the whole local database.
///
/// **Temporary, and deliberately not what ADR-8 describes.** ADR-8 says
/// workouts "are never uploaded" and an account "carries identity only".
/// That is still the intended end state for the *free* tier — see TODO.md's
/// Roadmap Phase 5, which replaces this with real per-table sync and
/// amends ADR-8 properly. This exists so a handful of testers can
/// reinstall the app, sign in, and get their history back, which
/// `flutter run` on a phone otherwise makes impossible without exporting
/// a file by hand first.
///
/// It is backup/restore, not sync. There is no merge, no conflict rule,
/// and no background upload: one slot per account, last write wins, and
/// restoring replaces what is on the device. Anything cleverer is Phase 5
/// work and should not be smuggled in here.
library;

/// Why a cloud backup call failed.
///
/// Mirrors `AuthFailureKind`: implementations translate transport and
/// vendor errors into these, so no caller ever sees a Supabase type.
enum CloudBackupFailureKind {
  /// Signed out, or the session expired.
  notSignedIn,

  /// This build has no Supabase credentials.
  notConfigured,

  /// The `backups` table is missing, or row-level security rejected the
  /// call. Almost always the one-time SQL in `docs/cloud_backup_setup.sql`
  /// not having been run against the project.
  notProvisioned,

  /// No backup has ever been uploaded for this account.
  noBackupYet,

  /// Network unreachable.
  offline,

  /// The stored backup could not be decoded, or came from an incompatible
  /// database schema.
  corrupt,

  /// The local profile is still linked to a *different* account than the
  /// one currently signed in — e.g. a deep link (email confirmation)
  /// authenticated a different account than the one the interactive
  /// sign-in/sign-up flow would have checked. Uploading now would write
  /// this device's data into the newly-active account's backup slot, which
  /// may not be who that data actually belongs to. Refused rather than
  /// silently proceeding; the fix is to sign out and back in through the
  /// normal flow, which resolves the conflict explicitly.
  accountMismatch,

  unknown,
}

/// A failed cloud backup call.
class CloudBackupFailure implements Exception {
  const CloudBackupFailure(this.kind, {this.detail});

  final CloudBackupFailureKind kind;

  /// The backend's own message, kept for logs, never shown verbatim. The
  /// user-facing wording comes from `CloudBackupFailureL10n.messageFor` in
  /// the presentation layer, which is where the translations live.
  final String? detail;

  @override
  String toString() => 'CloudBackupFailure(${kind.name}'
      '${detail == null ? '' : ': $detail'})';
}

/// What is stored in the account's single backup slot.
class CloudBackupInfo {
  const CloudBackupInfo({
    required this.updatedAt,
    required this.sizeBytes,
    required this.appVersion,
    required this.dbSchemaVersion,
  });

  final DateTime updatedAt;

  /// Size of the stored payload, for the "last backed up" line. Compressed,
  /// so it reads much smaller than the export file the user would get from
  /// Settings — that is expected, not a bug.
  final int sizeBytes;

  final String appVersion;

  /// Schema the backup was written against. A restore into a different
  /// schema is refused by `DataExportService.applyImport`, so surfacing it
  /// early lets the UI explain rather than throw.
  final int dbSchemaVersion;
}

/// Reads and writes one backup slot per signed-in account.
abstract interface class CloudBackupService {
  /// Whether this build can talk to a backup backend at all.
  bool get isAvailable;

  /// Metadata for the current account's backup, or null if there is none.
  /// Does not download the payload.
  Future<CloudBackupInfo?> head();

  /// Uploads [payload], replacing whatever was stored.
  Future<CloudBackupInfo> upload({
    required String payload,
    required String appVersion,
    required int dbSchemaVersion,
  });

  /// Downloads the stored export envelope.
  Future<String> download();
}

/// Used when the build carries no credentials. ADR-6: a capability that
/// isn't there degrades, it never throws at the call site that asks whether
/// it exists.
class DisabledCloudBackupService implements CloudBackupService {
  const DisabledCloudBackupService();

  @override
  bool get isAvailable => false;

  @override
  Future<CloudBackupInfo?> head() async => null;

  @override
  Future<CloudBackupInfo> upload({
    required String payload,
    required String appVersion,
    required int dbSchemaVersion,
  }) async =>
      throw const CloudBackupFailure(CloudBackupFailureKind.notConfigured);

  @override
  Future<String> download() async =>
      throw const CloudBackupFailure(CloudBackupFailureKind.notConfigured);
}
