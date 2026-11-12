import '../../../core/l10n/l10n_extension.dart';
import '../domain/export_envelope.dart';

/// Turns an [ImportProblem] into a sentence in the user's language, as
/// `CloudBackupFailureL10n` does for the cloud backup: the exception says
/// what went wrong, this says it to the user. The English detail stays in
/// [ImportValidationException.message], for the log.
extension ImportValidationL10n on ImportValidationException {
  String messageFor(AppLocalizations l10n) => switch (problem) {
        ImportProblem.notAnExport => l10n.dataImportNotAnExport,
        ImportProblem.madeByNewerApp => l10n.dataImportMadeByNewerApp,
        ImportProblem.tooOld => l10n.dataImportTooOld,
        ImportProblem.incomplete => l10n.dataImportIncomplete,
        ImportProblem.exerciseConflict =>
          l10n.dataImportExerciseConflict(subject ?? '?'),
        ImportProblem.damaged => l10n.dataImportDamaged,
        ImportProblem.appMismatch => l10n.dataImportAppMismatch,
      };
}
