import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/error_reporting.dart';
import '../../../../core/formatters/date_formatters.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/providers.dart';
import '../../../../core/services/data_export_service.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../backup/domain/cloud_backup_controller.dart';
import '../../domain/erase_local_data.dart';
import '../../domain/export_envelope.dart';
import '../import_problem_messages.dart';

/// Export / import / delete-all-data controls (ADR-7).
///
/// Kept as its own widget so `settings_page.dart` stays a plain list of
/// sections — all the dialog flow logic lives here.
class DataManagementSection extends ConsumerWidget {
  const DataManagementSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.upload_file_outlined),
          title: Text(l10n.dataExportTitle),
          subtitle: Text(l10n.dataExportSubtitle),
          onTap: () => _export(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: Text(l10n.dataImportTitle),
          subtitle: Text(l10n.dataImportSubtitle),
          onTap: () => _import(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.restore_outlined),
          title: Text(l10n.dataSnapshotTitle),
          subtitle: Text(l10n.dataSnapshotSubtitle),
          onTap: () => _restoreSnapshot(context, ref),
        ),
        ListTile(
          leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
          title: Text(
            l10n.dataDeleteAllTitle,
            style: TextStyle(color: scheme.error),
          ),
          subtitle: Text(l10n.dataDeleteAllSubtitle),
          onTap: () => _deleteAll(context, ref),
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = context.l10n;
    final _ExportFormat? format = await showDialog<_ExportFormat>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.dataExportTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _ExportFormat.json),
            child: Text(context.l10n.dataExportJson),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _ExportFormat.csv),
            child: Text(context.l10n.dataExportCsv),
          ),
        ],
      ),
    );
    if (format == null || !context.mounted) return;

    final DataExportService service = ref.read(dataExportServiceProvider);
    final AppDatabase db = ref.read(appDatabaseProvider);
    final String timestamp =
        DateTime.now().toIso8601String().replaceAll(RegExp('[:.]'), '-');
    final (String fileName, String mimeType) = switch (format) {
      _ExportFormat.json => (
          'ironyx_backup_$timestamp.json',
          'application/json'
        ),
      _ExportFormat.csv => ('ironyx_export_$timestamp.csv', 'text/csv'),
    };

    // Built behind a progress dialog: it reads every table, and the tile
    // stayed tappable meanwhile, so a second tap started a second export.
    // A failure here, or in saving below, escaped the tap handler, and the
    // tap seemed to do nothing.
    String content = '';
    final bool built = await _withProgress(context, () async {
      content = switch (format) {
        _ExportFormat.json => await service.buildJsonExport(db),
        _ExportFormat.csv => await service.buildCsvExport(db),
      };
    });
    if (!context.mounted) return;
    if (!built) {
      await _showError(context, l10n.dataExportFailed);
      return;
    }

    // The system's own save screen: no progress dialog can stay over it.
    final Uri? savedUri;
    try {
      savedUri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(content)),
        mimeType: mimeType,
        dialogTitle: l10n.dataExportSaveDialog,
      );
    } catch (e, stackTrace) {
      reportError(e, stackTrace, context: 'DataManagementSection.export');
      if (context.mounted) await _showError(context, l10n.dataExportFailed);
      return;
    }
    if (!context.mounted) return;
    if (savedUri != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.dataExportSaved)));
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = context.l10n;
    final PlatformFile? picked = await FilePicker.pickFile(
      dialogTitle: l10n.dataImportPickerTitle,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null || !context.mounted) return;

    // Read and checked behind a progress dialog, in the background: a
    // large backup was decoded on the UI thread, freezing the screen with
    // nothing to say why, and the tile could be tapped again meanwhile.
    final DataExportService service = ref.read(dataExportServiceProvider);
    ImportEnvelope? read;
    Object? refusal;
    // An unexpected failure (a file that cannot be read) is logged by
    // _withProgress and leaves `read` null: "could not read".
    await _withProgress(context, () async {
      try {
        read = await readImportFile(service, picked);
      } on ImportValidationException catch (e) {
        refusal = e;
      } on ImportFileTooLargeException catch (e) {
        refusal = e;
      }
    });
    if (!context.mounted) return;
    final ImportEnvelope? envelope = read;
    if (envelope == null) {
      await _showError(
        context,
        switch (refusal) {
          final ImportValidationException e => e.messageFor(l10n),
          ImportFileTooLargeException() =>
            l10n.dataImportTooLarge(kMaxImportBytes ~/ (1024 * 1024)),
          _ => l10n.dataImportUnreadable,
        },
      );
      return;
    }

    final database = ref.read(appDatabaseProvider);
    final expectedTables = {
      for (final table in database.allTables) table.actualTableName,
    };
    final missingTables =
        expectedTables.difference(envelope.tables.keys.toSet());
    final unknownTables =
        envelope.tables.keys.toSet().difference(expectedTables);
    final ImportMode? mode = await _confirmImport(
      context,
      envelope,
      missingTables,
      unknownTables,
    );
    if (mode == null || !context.mounted) return;

    unawaited(_runImport(context, ref, service, envelope, mode));
  }

  Future<void> _restoreSnapshot(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final DataExportService service = ref.read(dataExportServiceProvider);
    // Inside the error handling: finding the folder and listing it failed
    // outside it, and the tap did nothing.
    final String snapshotDir;
    final List<File> snapshots;
    try {
      snapshotDir = await ref.read(snapshotDirectoryProvider.future);
      snapshots = await service.listSnapshots(snapshotDir);
    } catch (e, stackTrace) {
      reportError(e, stackTrace, context: 'DataManagementSection.snapshots');
      if (context.mounted) {
        await _showError(context, l10n.dataSnapshotRestoreFailed);
      }
      return;
    }
    if (!context.mounted) return;
    if (snapshots.isEmpty) {
      await _showError(context, l10n.dataSnapshotNone);
      return;
    }

    final DateFormatters dates = DateFormatters.of(context);
    final File? selected = await showDialog<File>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.dataSnapshotDialogTitle),
        children: [
          for (final snapshot in snapshots)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, snapshot),
              // When it was taken, newest first; it showed the file's name,
              // "pre_import_snapshot_1794398970790.json".
              child: Text(
                switch (DataExportService.snapshotTakenAt(snapshot)) {
                  final DateTime at => '${dates.full(at)}, ${dates.time(at)}',
                  null => snapshot.uri.pathSegments.last,
                },
              ),
            ),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.dataSnapshotConfirmTitle),
        content: Text(l10n.dataSnapshotConfirmBody),
        actions: [
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

    // Behind the progress dialog: it replaces every table, with nothing on
    // screen before, and the tile could start a second restore.
    ImportValidationException? refusal;
    final bool restored = await _withProgress(context, () async {
      try {
        await service.restoreSnapshot(
          ref.read(appDatabaseProvider),
          selected,
          snapshotDirPath: snapshotDir,
        );
      } on ImportValidationException catch (e) {
        refusal = e;
      }
    });
    if (!context.mounted) return;
    final ImportValidationException? refused = refusal;
    if (refused != null) {
      await _showError(context, refused.messageFor(l10n));
    } else if (restored) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.dataSnapshotRestored)),
      );
    } else {
      await _showError(context, l10n.dataSnapshotRestoreFailed);
    }
  }

  Future<void> _runImport(
    BuildContext context,
    WidgetRef ref,
    DataExportService service,
    ImportEnvelope envelope,
    ImportMode mode,
  ) async {
    final AppLocalizations l10n = context.l10n;
    // Captured from the dialog's own `builder`, not the outer Settings
    // context: closing time needs to know whether *this* route is still
    // there to pop, which `context.mounted` (Settings' own context) cannot
    // tell — Settings stays mounted the whole time regardless of what
    // happens to the dialog on top of it.
    BuildContext? progressContext;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          progressContext = dialogContext;
          // The barrier already blocks a tap outside; `canPop: false` closes
          // the other way out — the Android system back button — which
          // `barrierDismissible` does nothing about. Without this, backing
          // out mid-import leaves the import running unattended, and the
          // `Navigator...pop()` below then has no dialog left to close and
          // pops whatever route Settings is actually showing instead.
          return const PopScope(
            canPop: false,
            child: Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );

    void closeProgressDialog() {
      final BuildContext? dialogContext = progressContext;
      if (dialogContext != null && dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
    }

    try {
      final AppDatabase db = ref.read(appDatabaseProvider);
      final supportDir = await getApplicationSupportDirectory();
      await service.applyImport(
        db,
        envelope,
        mode: mode,
        snapshotDirPath: supportDir.path,
      );
      closeProgressDialog();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.dataImportComplete)));
    } on ImportValidationException catch (e) {
      // Refused before anything changed, for a reason the user can act on;
      // it was shown as the generic "import failed", the reason lost.
      closeProgressDialog();
      if (!context.mounted) return;
      await _showError(context, e.messageFor(l10n));
    } catch (e, stackTrace) {
      reportError(e, stackTrace, context: 'DataManagementSection.runImport');
      closeProgressDialog();
      if (!context.mounted) return;
      await _showError(context, l10n.dataImportFailed);
    }
  }

  Future<ImportMode?> _confirmImport(
    BuildContext context,
    ImportEnvelope envelope,
    Set<String> missingTables,
    Set<String> unknownTables,
  ) async {
    ImportMode mode = ImportMode.merge;
    final Map<String, int> counts = envelope.counts;
    final List<String> highlights = [
      'workouts_table',
      'workout_sets_table',
      'timer_sessions_table',
      'body_metrics_table',
      'templates_table',
    ].where((t) => (counts[t] ?? 0) > 0).toList();

    return showDialog<ImportMode>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(context.l10n.dataImportBackupTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final table in highlights)
                  Text('${counts[table]} ${_friendlyName(context, table)}'),
                if (highlights.isEmpty)
                  Text(context.l10n.dataImportNoWorkoutData),
                if (missingTables.isNotEmpty || unknownTables.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    context.l10n.dataImportIntegrityWarning(
                      <String>[
                        if (missingTables.isNotEmpty)
                          context.l10n.dataImportMissingTables(
                            missingTables.length,
                          ),
                        if (unknownTables.isNotEmpty)
                          context.l10n.dataImportUnknownTables(
                            unknownTables.length,
                          ),
                      ].join('; '),
                    ),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                RadioGroup<ImportMode>(
                  groupValue: mode,
                  onChanged: (value) => setState(() => mode = value!),
                  child: Column(
                    children: <Widget>[
                      RadioListTile<ImportMode>(
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.l10n.dataImportModeMerge),
                        subtitle:
                            Text(context.l10n.dataImportModeMergeSubtitle),
                        value: ImportMode.merge,
                      ),
                      RadioListTile<ImportMode>(
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.l10n.dataImportModeReplace),
                        subtitle:
                            Text(context.l10n.dataImportModeReplaceSubtitle),
                        value: ImportMode.replace,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, mode),
              child: Text(context.l10n.dataImportConfirmAction),
            ),
          ],
        ),
      ),
    );
  }

  /// Turns a raw drift table name into something readable in a summary.
  ///
  /// The five tables a backup actually carries get a translated name; anything
  /// else falls back to de-snake-casing the identifier, which is what this
  /// did for every table before.
  String _friendlyName(BuildContext context, String rawTableName) =>
      switch (rawTableName) {
        'workouts_table' => context.l10n.dataTableWorkouts,
        'workout_sets_table' => context.l10n.dataTableWorkoutSets,
        'timer_sessions_table' => context.l10n.dataTableTimerSessions,
        'body_metrics_table' => context.l10n.dataTableBodyMetrics,
        'templates_table' => context.l10n.dataTableTemplates,
        _ => rawTableName.replaceAll('_table', '').replaceAll('_', ' '),
      };

  Future<void> _showError(BuildContext context, String message) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.dataImportProblemTitle),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.actionOk),
            ),
          ],
        ),
      );

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = context.l10n;
    final _DeleteChoice? choice = await showDialog<_DeleteChoice>(
      context: context,
      builder: (context) => const _DeleteAllDialog(),
    );
    if (!context.mounted) return;
    if (choice == _DeleteChoice.exportFirst) {
      // Keeping a copy is the user's choice, and it lands where they put
      // it. Nothing is deleted; they come back to delete once they have it.
      await _export(context, ref);
      return;
    }
    if (choice != _DeleteChoice.delete) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool done = await _withProgress(context, () => eraseLocalData(ref));
    if (!context.mounted) return;
    if (done) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.dataAllDeleted)));
    } else {
      await _showError(context, l10n.dataDeleteFailed);
    }
  }

  /// Runs [work] behind a progress dialog that cannot be dismissed, and
  /// says whether it succeeded; a failure is logged. It ran with nothing on
  /// screen, and a failure escaped the tap handler unreported.
  Future<bool> _withProgress(
    BuildContext context,
    Future<void> Function() work,
  ) async {
    // The dialog's own context, to close exactly it: Settings' context
    // stays mounted whatever happens to the dialog above it. The work waits
    // for it: started at once, a fast failure finished before the dialog
    // was built, left nothing to close, and the spinner stayed for good.
    final Completer<BuildContext> shown = Completer<BuildContext>();
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          if (!shown.isCompleted) shown.complete(dialogContext);
          // Back must not close it either: the work goes on regardless.
          return const PopScope(
            canPop: false,
            child: Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );
    final BuildContext dialogContext = await shown.future;
    try {
      await work();
      return true;
    } catch (e, stackTrace) {
      reportError(e, stackTrace, context: 'DataManagementSection');
      return false;
    } finally {
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    }
  }
}

/// What the delete-all dialog closes with.
enum _DeleteChoice { delete, exportFirst }

/// Largest file Import reads: 50 MB. A year of hard training exports to
/// about 1.4 MB; a file this size is not a backup, and reading it whole
/// could exhaust the memory.
const int kMaxImportBytes = 50 * 1024 * 1024;

/// The picked file is over [kMaxImportBytes].
class ImportFileTooLargeException implements Exception {
  const ImportFileTooLargeException(this.bytes);

  final int bytes;
}

/// Reads [file] as a backup: its size checked before anything is read,
/// then decoded and validated off the UI isolate. Throws
/// [ImportFileTooLargeException], [ImportValidationException], or what
/// reading or decoding throws for a file that cannot be read.
@visibleForTesting
Future<ImportEnvelope> readImportFile(
  DataExportService service,
  PlatformFile file,
) async {
  final int size = await file.length();
  if (size > kMaxImportBytes) throw ImportFileTooLargeException(size);
  final String content = utf8.decode(await file.readAsBytes());
  return service.parseImportInBackground(content);
}

enum _ExportFormat { json, csv }

class _DeleteAllDialog extends StatefulWidget {
  const _DeleteAllDialog();

  @override
  State<_DeleteAllDialog> createState() => _DeleteAllDialogState();
}

class _DeleteAllDialogState extends State<_DeleteAllDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _canConfirm = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AppLocalizations l10n = context.l10n;
    final String confirmWord = l10n.dataDeleteConfirmWord;
    return AlertDialog(
      title: Text(l10n.dataDeleteAllConfirmTitle),
      // Scrollable because the field autofocuses: on a phone the keyboard
      // then takes most of the height, and a plain Column overflowed (found
      // on-device, 2026-09-29), hiding part of the warning or the field.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.dataDeleteAllConfirmBody),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.dataDeleteAllTypeToConfirm(confirmWord),
              style: TextStyle(color: scheme.error),
            ),
            TextField(
              controller: _controller,
              autofocus: true,
              // Compared against the localized word shown just above, so the
              // gate always asks for something the user can actually read
              // and type on their own keyboard.
              onChanged: (value) =>
                  setState(() => _canConfirm = value.trim() == confirmWord),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _DeleteChoice.exportFirst),
          child: Text(l10n.dataDeleteExportFirst),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: _canConfirm
              ? () => Navigator.pop(context, _DeleteChoice.delete)
              : null,
          child: Text(l10n.dataDeleteEverything),
        ),
      ],
    );
  }
}
