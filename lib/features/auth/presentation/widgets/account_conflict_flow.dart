import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  await eraseLocalData(ref);

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.authAccountConflictErasedMessage(user.email)),
      ),
    );
  }
  return true;
}
