import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/formatters/date_formatters.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../auth/domain/auth_controller.dart';
import '../../../auth/domain/auth_service.dart';
import '../../../backup/domain/cloud_backup_controller.dart';
import '../../../backup/domain/cloud_backup_service.dart';

/// Back up and restore the whole database against the signed-in account.
///
/// Temporary — see [CloudBackupService]'s docs and PLAN.md Phase 5. The
/// copy says "while the app is in testing" out loud rather than implying a
/// finished sync feature, because a backup people over-trust is worse than
/// one they know the limits of.
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SectionHeader(
          title: 'Account backup',
          subtitle: 'Temporary, while the app is in testing — one backup per '
              'account, replaced each time you back up',
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              if (user == null)
                const ListTile(
                  leading: Icon(Icons.cloud_off_outlined),
                  title: Text('Sign in to back up'),
                  subtitle: Text(
                    'A backup is stored with your account, so you can '
                    'reinstall the app and sign in to get your data back.',
                  ),
                )
              else ...<Widget>[
                ListTile(
                  leading: const Icon(Icons.cloud_done_outlined),
                  title: const Text('Last backup'),
                  subtitle: Text(_statusLine(status)),
                ),
                ListTile(
                  leading: _isBackingUp
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.backup_outlined),
                  title: Text(_isBackingUp ? 'Backing up…' : 'Back up now'),
                  subtitle: Text(_isBackingUp
                      ? 'Preparing and uploading your data'
                      : 'Uploads everything on this device'),
                  enabled: !_isBackingUp,
                  onTap: _isBackingUp ? null : () => _backUp(context, ref),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore),
                  title: const Text('Restore from my account'),
                  subtitle: const Text(
                    'Replaces the data on this device with your backup',
                  ),
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

  String _statusLine(AsyncValue<CloudBackupInfo?> status) => status.when(
        loading: () => 'Checking…',
        error: (error, _) => error is CloudBackupFailure
            ? error.message
            : 'Couldn\'t check for a backup.',
        data: (info) => info == null
            ? 'No backup yet'
            : '${DateFormatters.full(info.updatedAt)} '
                'at ${DateFormatters.time(info.updatedAt)} · '
                '${_readableSize(info.sizeBytes)}',
      );

  String _readableSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _backUp(BuildContext context, WidgetRef ref) async {
    if (_isBackingUp) return;
    setState(() => _isBackingUp = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Backing up…')));

    CloudBackupInfo? info;
    String? failureMessage;
    try {
      info = await ref.read(cloudBackupControllerProvider.notifier).backUpNow();
    } on CloudBackupFailure catch (failure) {
      failureMessage = failure.message;
    } on Object catch (error) {
      // Anything reaching here is unmapped, i.e. a bug rather than a
      // condition the user can fix. Log it: the generic message below is all
      // the user should see, but a silent generic message is also all a
      // developer saw the last time this branch fired.
      if (kDebugMode) debugPrint('[backup] $error');
      failureMessage = 'Couldn’t complete the backup. Please try again.';
    } finally {
      messenger.hideCurrentSnackBar();
      if (mounted) setState(() => _isBackingUp = false);
    }

    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(info == null
            ? failureMessage ?? 'Couldn’t complete the backup.'
            : 'Backed up (${_readableSize(info.sizeBytes)})'),
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from your account?'),
        content: const Text(
          'Everything currently on this device — workouts, programs, '
          'templates, body metrics — is replaced by your backup.\n\n'
          'A snapshot of the current data is saved first, so you can undo '
          'this from Data management.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Restoring…')));
    try {
      await ref.read(cloudBackupControllerProvider.notifier).restoreFromCloud();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Restored from your account')),
        );
    } on CloudBackupFailure catch (failure) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}
