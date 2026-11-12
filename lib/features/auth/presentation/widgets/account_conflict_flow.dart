import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error_reporting.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/providers.dart';
import '../../../settings/domain/erase_local_data.dart';
import '../../domain/auth_controller.dart';
import '../../domain/auth_service.dart';

/// The two ways a user can resolve finding another account's data already
/// on this device.
enum AccountConflictChoice { keepLocal, eraseAndContinue }

/// Runs the interactive "this device already has another account's data"
/// check that [SignInPage] and [SignUpPage] must both perform right after
/// authenticating and before calling `ProfileDao.linkAccount` — see
/// `ProfileDao.hasConflictingAccount` for why the check exists at all.
///
/// Returns true when the caller should go ahead and link [user] to the
/// local profile: either there was no conflict, or the user chose to erase
/// local data and this function already did so. Returns false when the
/// caller must not link — the user chose to keep their local data (or
/// dismissed the dialog, treated the same way), and this function has
/// already signed back out to undo the sign-in/sign-up that just completed.
Future<bool> resolveAccountConflict(
  BuildContext context,
  WidgetRef ref,
  AuthUser user,
) async {
  final bool conflict =
      await ref.read(profileDaoProvider).hasConflictingAccount(user.id);
  if (!conflict) return true;
  if (!context.mounted) return false;

  final AppLocalizations l10n = context.l10n;
  final AccountConflictChoice? choice = await showDialog<AccountConflictChoice>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.authAccountConflictTitle),
      content: Text(l10n.authAccountConflictBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(
            dialogContext,
            AccountConflictChoice.keepLocal,
          ),
          child: Text(l10n.authAccountConflictKeepLocal),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(
            dialogContext,
            AccountConflictChoice.eraseAndContinue,
          ),
          child: Text(l10n.authAccountConflictEraseAndContinue),
        ),
      ],
    ),
  );

  if (choice != AccountConflictChoice.eraseAndContinue) {
    // Keep-local, or the dialog was dismissed some other way: revert the
    // sign-in/sign-up that already completed rather than leave it
    // half-linked, since nothing else undoes that on this path.
    await ref.read(authControllerProvider.notifier).signOut();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.authAccountConflictCancelledMessage)),
      );
    }
    return false;
  }

  // The same erase as Settings' "Delete all data": the database, the
  // import snapshots, an open workout, then the built-in programs back.
  //
  // A failure escaped to the sign-in form, which catches only
  // `AuthFailure`: the new session stayed signed in, unlinked, with the old
  // account's data possibly still here and nothing on screen.
  final ScaffoldMessengerState? messenger =
      context.mounted ? ScaffoldMessenger.of(context) : null;

  // Undoes the sign-in, as "Keep my data" does, so the new account is not
  // left signed in over what is left of the old account's data.
  Future<void> signBackOut() async {
    try {
      await ref.read(authControllerProvider.notifier).signOut();
    } catch (signOutError, signOutStack) {
      reportError(
        signOutError,
        signOutStack,
        context: 'resolveAccountConflict.signOut',
      );
    }
  }

  try {
    await eraseLocalData(ref);
  } on EraseIncompleteException catch (incomplete) {
    // The database is erased. Linking is safe only if what is left is not
    // the old account's: its open workout would be saved, and backed up,
    // under the new account, and a snapshot is a full copy of its data.
    // The built-in programs are the app's, so that step alone failing
    // still links. Otherwise sign back out: Delete all data in Settings
    // finishes the job, and the next sign-in finds no conflict.
    final bool oldDataLeft = incomplete.failed.any(
      (step) => step != EraseStep.builtInPrograms,
    );
    if (oldDataLeft) {
      await signBackOut();
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.dataDeleteIncomplete)),
      );
      return false;
    }
  } catch (error, stackTrace) {
    // Nothing was erased (the database delete is the first thing that can
    // change anything).
    reportError(error, stackTrace, context: 'resolveAccountConflict.erase');
    await signBackOut();
    messenger?.showSnackBar(SnackBar(content: Text(l10n.dataDeleteFailed)));
    return false;
  }

  messenger?.showSnackBar(
    SnackBar(
      content: Text(l10n.authAccountConflictErasedMessage(user.email)),
    ),
  );
  return true;
}
