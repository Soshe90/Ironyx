/// Account-tied backup of the whole local database.
///
/// **Temporary, and deliberately not what ADR-8 describes.** ADR-8 says
/// workouts "are never uploaded" and an account "carries identity only".
/// That is still the intended end state for the *free* tier — see PLAN.md
/// Phase 5, which replaces this with real per-table sync and amends ADR-8
/// properly. This exists so a handful of testers can reinstall the app,
/// sign in, and get their history back, which `flutter run` on a phone
/// otherwise makes impossible without exporting a file by hand first.
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

  unknown,
}

/// A failed cloud backup call.
class CloudBackupFailure implements Exception {
  const CloudBackupFailure(this.kind, {this.detail});

  final CloudBackupFailureKind kind;

  /// The backend's own message, kept for logs, never shown verbatim.
  final String? detail;

  String get message => switch (kind) {
        CloudBackupFailureKind.notSignedIn =>
          'Sign in first — a backup is stored with your account.',
        CloudBackupFailureKind.notConfigured =>
          'Backup isn\'t available in this build.',
        CloudBackupFailureKind.notProvisioned =>
          'Backup isn\'t set up on the server yet. Run the SQL in '
              'docs/cloud_backup_setup.sql against your Supabase project.',
        CloudBackupFailureKind.noBackupYet =>
          'There\'s no backup stored for this account yet.',
        CloudBackupFailureKind.offline =>
          'Couldn\'t reach the server. Check your connection and try again.',
        CloudBackupFailureKind.corrupt =>
          'That backup couldn\'t be read. It may have been made by a newer '
              'version of the app.',
        CloudBackupFailureKind.unknown => 'Something went wrong. Try again.',
      };

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
