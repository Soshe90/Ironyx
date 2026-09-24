import '../../../core/l10n/l10n_extension.dart';
import '../domain/cloud_backup_service.dart';

/// Turns a [CloudBackupFailureKind] into wording a user can act on.
///
/// Split from the domain type for the same reason as `AuthFailureL10n`: the
/// failure says what went wrong, the presentation layer says it in the user's
/// language.
extension CloudBackupFailureL10n on CloudBackupFailure {
  String messageFor(AppLocalizations l10n) => switch (kind) {
        CloudBackupFailureKind.notSignedIn => l10n.backupErrorNotSignedIn,
        CloudBackupFailureKind.notConfigured => l10n.backupErrorNotConfigured,
        CloudBackupFailureKind.notProvisioned => l10n.backupErrorNotProvisioned,
        CloudBackupFailureKind.noBackupYet => l10n.backupErrorNoBackupYet,
        CloudBackupFailureKind.offline => l10n.backupErrorOffline,
        CloudBackupFailureKind.corrupt => l10n.backupErrorCorrupt,
        CloudBackupFailureKind.accountMismatch =>
          l10n.backupErrorAccountMismatch,
        CloudBackupFailureKind.tooLarge => l10n.backupErrorTooLarge,
        CloudBackupFailureKind.unknown => l10n.backupErrorUnknown,
      };
}
