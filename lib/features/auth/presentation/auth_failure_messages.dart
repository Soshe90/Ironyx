import '../../../core/l10n/l10n_extension.dart';
import '../domain/auth_service.dart';

/// Turns an [AuthFailureKind] into wording a user can act on.
///
/// Lives here rather than on [AuthFailure] itself so the domain layer stays
/// free of `AppLocalizations`: the failure describes *what* went wrong, and
/// only the presentation layer decides how to say it, in which language.
extension AuthFailureL10n on AuthFailure {
  /// Plain, non-blaming wording for the UI.
  String messageFor(AppLocalizations l10n) => switch (kind) {
        AuthFailureKind.wrongCredentials => l10n.authErrorWrongCredentials,
        AuthFailureKind.emailAlreadyRegistered =>
          l10n.authErrorEmailAlreadyRegistered,
        AuthFailureKind.weakPassword => l10n.authErrorWeakPassword,
        AuthFailureKind.samePassword => l10n.authErrorSamePassword,
        AuthFailureKind.recoveryExpired => l10n.authErrorRecoveryExpired,
        AuthFailureKind.emailRejected => l10n.authErrorEmailRejected,
        AuthFailureKind.signUpDisabled => l10n.authErrorSignUpDisabled,
        AuthFailureKind.emailNotConfirmed => l10n.authErrorEmailNotConfirmed,
        AuthFailureKind.rateLimited => l10n.authErrorRateLimited,
        AuthFailureKind.offline => l10n.authErrorOffline,
        AuthFailureKind.notConfigured => l10n.authErrorNotConfigured,
        AuthFailureKind.unknown => l10n.authErrorUnknown,
      };
}
