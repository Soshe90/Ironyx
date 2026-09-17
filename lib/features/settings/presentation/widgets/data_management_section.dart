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
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/providers.dart';
import '../../../../core/services/data_export_service.dart';
import '../../domain/export_envelope.dart';

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

    final String content;
    final String fileName;
    final String mimeType;
    switch (format) {
      case _ExportFormat.json:
        content = await service.buildJsonExport(db);
        fileName = 'ironyx_backup_$timestamp.json';
        mimeType = 'application/json';
      case _ExportFormat.csv:
        content = await service.buildCsvExport(db);
        fileName = 'ironyx_export_$timestamp.csv';
        mimeType = 'text/csv';
    }

    final Uint8List bytes = Uint8List.fromList(utf8.encode(content));
    final Uri? savedUri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
      dialogTitle: l10n.dataExportSaveDialog,
    );
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

    final String content;
    try {
      content = utf8.decode(await picked.readAsBytes());
    } catch (_) {
      if (!context.mounted) return;
      await _showError(context, l10n.dataImportUnreadable);
      return;
    }

    final DataExportService service = ref.read(dataExportServiceProvider);
    final ImportEnvelope envelope;
    try {
      envelope = service.parseImport(content);
    } on ImportValidationException catch (e) {
      if (!context.mounted) return;
      await _showError(context, e.message);
      return;
    }

    if (!context.mounted) return;
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
    final service = ref.read(dataExportServiceProvider);
    final supportDir = await getApplicationSupportDirectory();
    final snapshots = await service.listSnapshots(supportDir.path);
    if (!context.mounted) return;
    if (snapshots.isEmpty) {
      await _showError(context, l10n.dataSnapshotNone);
      return;
    }

    final File? selected = await showDialog<File>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.dataSnapshotDialogTitle),
        children: [
          for (final snapshot in snapshots)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, snapshot),
              child: Text(
                snapshot.path.split(Platform.pathSeparator).last,
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

    try {
      await service.restoreSnapshot(
        ref.read(appDatabaseProvider),
        selected,
        snapshotDirPath: supportDir.path,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.dataSnapshotRestored)),
      );
    } catch (e, stackTrace) {
      reportError(e, stackTrace,
          context: 'DataManagementSection.restoreSnapshot');
      if (!context.mounted) return;
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
                  const SizedBox(height: 12),
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
                const SizedBox(height: 16),
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
              child: Text(context.l10n.importXlsxConfirmAction),
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
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _DeleteAllDialog(),
    );
    if (confirmed != true || !context.mounted) return;

    final DataExportService service = ref.read(dataExportServiceProvider);
    final AppDatabase db = ref.read(appDatabaseProvider);
    await service.deleteAllUserData(db);
    // Programs (built-in and user) were deleted along with their templates
    // above — reset the seed marker and reseed so built-ins come back the
    // same way the exercise catalogue survives a delete-all.
    //
    // This exact sequence is also used by the account-conflict "erase and
    // continue" flow (`account_conflict_flow.dart`), where it once produced
    // a hung `Future` under a specific widget-test pump interleaving with
    // `programSeederProvider` also watched app-wide by `app.dart`. It did
    // not reproduce here across several real end-to-end runs of this exact
    // button (`test/widget/settings_page_test.dart`, "tapping Delete
    // everything..."), so it looks like a test-harness artifact rather
    // than a reachable bug — but
    // it was never fully explained. See TODO.md's A2.14 for the
    // reproduction, in case this ever hangs for real.
    await ref.read(programSeederProvider.notifier).resetSeedVersion();
    ref.invalidate(programSeederProvider);
    await ref.read(programSeederProvider.future);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.l10n.dataAllDeleted)));
  }
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.dataDeleteAllConfirmBody),
          const SizedBox(height: 16),
          Text(
            l10n.dataDeleteAllTypeToConfirm(confirmWord),
            style: TextStyle(color: scheme.error),
          ),
          TextField(
            controller: _controller,
            autofocus: true,
            // Compared against the localized word shown just above, so the
            // gate always asks for something the user can actually read and
            // type on their own keyboard.
            onChanged: (value) =>
                setState(() => _canConfirm = value.trim() == confirmWord),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: _canConfirm ? () => Navigator.pop(context, true) : null,
          child: Text(l10n.dataDeleteEverything),
        ),
      ],
    );
  }
}
