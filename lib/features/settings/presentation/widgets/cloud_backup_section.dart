import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/formatters/date_formatters.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../auth/domain/auth_controller.dart';
import '../../../auth/domain/auth_service.dart';
import '../../../backup/domain/cloud_backup_controller.dart';
import '../../../backup/domain/cloud_backup_service.dart';
import '../../../backup/presentation/cloud_backup_failure_messages.dart';

/// Back up and restore the whole database against the signed-in account.
///
/// Temporary — see [CloudBackupService]'s docs and TODO.md Roadmap Phase 5.
/// The copy says "while the app is in testing" out loud rather than
/// implying a finished sync feature, because a backup people over-trust is
/// worse than one they know the limits of.
class CloudBackupSection extends ConsumerStatefulWidget {
  const CloudBackupSection({super.key});

  @override
  ConsumerState<CloudBackupSection> createState() => _CloudBackupSectionState();
}

class _CloudBackupSectionState extends ConsumerState<CloudBackupSection> {
  bool _isBackingUp = false;

  @override
  Widget build(BuildContext context) {
    final bool available = ref.watch(cloudBackupAvailableProvider);
    if (!available) return const SizedBox.shrink();

    final AuthUser? user = ref.watch(authControllerProvider);
    final AsyncValue<CloudBackupInfo?> status =
        ref.watch(cloudBackupStatusProvider);
    final AppLocalizations l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title: l10n.backupSectionTitle,
          subtitle: l10n.backupSectionSubtitle,
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              if (user == null)
                ListTile(
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: Text(l10n.backupSignInTitle),
                  subtitle: Text(l10n.backupSignInSubtitle),
                )
              else ...<Widget>[
                ListTile(
                  leading: const Icon(Icons.cloud_done_outlined),
                  title: Text(l10n.backupLastBackup),
                  subtitle: Text(_statusLine(context, status)),
                ),
                ListTile(
                  leading: _isBackingUp
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.backup_outlined),
                  title: Text(_isBackingUp
                      ? l10n.backupInProgress
                      : l10n.backupNowTitle),
                  subtitle: Text(_isBackingUp
                      ? l10n.backupInProgressSubtitle
                      : l10n.backupNowSubtitle),
                  enabled: !_isBackingUp,
                  onTap: _isBackingUp ? null : () => _backUp(context, ref),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore),
                  title: Text(l10n.backupRestoreTitle),
                  subtitle: Text(l10n.backupRestoreSubtitle),
                  // Nothing to restore, so don't offer a button that can
                  // only produce an error. `.value`, not `.valueOrNull` —
                  // Riverpod 3 dropped the latter.
                  enabled: status.value != null,
                  onTap: () => _restore(context, ref),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  String _statusLine(
      BuildContext context, AsyncValue<CloudBackupInfo?> status) {
    final AppLocalizations l10n = context.l10n;
    final DateFormatters dates = DateFormatters.of(context);

    return status.when(
      loading: () => l10n.backupChecking,
      error: (error, _) => error is CloudBackupFailure
          ? error.messageFor(l10n)
          : l10n.backupCouldNotCheck,
      data: (info) => info == null
          ? l10n.backupNoneYet
          : l10n.backupStatusLine(
              dates.full(info.updatedAt),
              dates.time(info.updatedAt),
              _readableSize(context, info.sizeBytes),
            ),
    );
  }

  String _readableSize(BuildContext context, int bytes) {
    final AppLocalizations l10n = context.l10n;
    if (bytes < 1024) return l10n.sizeBytes(bytes);
    if (bytes < 1024 * 1024) return l10n.sizeKilobytes((bytes / 1024).round());
    return l10n.sizeMegabytes((bytes / (1024 * 1024)).toStringAsFixed(1));
  }

  Future<void> _backUp(BuildContext context, WidgetRef ref) async {
    if (_isBackingUp) return;
    setState(() => _isBackingUp = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    // Captured before the first `await`: `context.l10n` after one is an
    // across-async-gap lookup, and this widget can be disposed mid-upload.
    final AppLocalizations l10n = context.l10n;
    messenger.showSnackBar(SnackBar(content: Text(l10n.backupInProgress)));

    CloudBackupInfo? info;
    String? failureMessage;
    try {
      info = await ref.read(cloudBackupControllerProvider.notifier).backUpNow();
    } on CloudBackupFailure catch (failure) {
      failureMessage = failure.messageFor(l10n);
    } on Object catch (error) {
      // Anything reaching here is unmapped, i.e. a bug rather than a
      // condition the user can fix. Log it: the generic message below is all
      // the user should see, but a silent generic message is also all a
      // developer saw the last time this branch fired.
      if (kDebugMode) debugPrint('[backup] $error');
      failureMessage = l10n.backupFailedRetry;
    } finally {
      messenger.hideCurrentSnackBar();
      if (mounted) setState(() => _isBackingUp = false);
    }

    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(info == null
            ? failureMessage ?? l10n.backupFailed
            : l10n.backupSucceeded(_readableSize(context, info.sizeBytes))),
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.backupRestoreConfirmTitle),
        content: Text(l10n.backupRestoreConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.backupRestoreAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(l10n.backupRestoring)));
    try {
      await ref.read(cloudBackupControllerProvider.notifier).restoreFromCloud();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.backupRestored)));
    } on CloudBackupFailure catch (failure) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.messageFor(l10n))));
    }
  }
}
