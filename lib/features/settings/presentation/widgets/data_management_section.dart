import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/database/app_database.dart';
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
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.upload_file_outlined),
          title: const Text('Export data'),
          subtitle: const Text('Back up your workouts, timers, and progress'),
          onTap: () => _export(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Import data'),
          subtitle: const Text('Restore from a backup file'),
          onTap: () => _import(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.restore_outlined),
          title: const Text('Restore pre-import snapshot'),
          subtitle: const Text('Undo a recent import'),
          onTap: () => _restoreSnapshot(context, ref),
        ),
        ListTile(
          leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
          title: Text('Delete all data', style: TextStyle(color: scheme.error)),
          subtitle:
              const Text('Workouts, timers, programs, templates, body metrics'),
          onTap: () => _deleteAll(context, ref),
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final _ExportFormat? format = await showDialog<_ExportFormat>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Export data'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _ExportFormat.json),
            child: const Text('JSON backup (can be imported later)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _ExportFormat.csv),
            child: const Text('CSV spreadsheet (workouts and sets only)'),
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
        fileName = 'fittrack_backup_$timestamp.json';
        mimeType = 'application/json';
      case _ExportFormat.csv:
        content = await service.buildCsvExport(db);
        fileName = 'fittrack_export_$timestamp.csv';
        mimeType = 'text/csv';
    }

    final Uint8List bytes = Uint8List.fromList(utf8.encode(content));
    final Uri? savedUri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
      dialogTitle: 'Save export',
    );
    if (!context.mounted) return;
    if (savedUri != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Export saved')));
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final PlatformFile? picked = await FilePicker.pickFile(
      dialogTitle: 'Choose a FitTrack backup',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null || !context.mounted) return;

    final String content;
    try {
      content = utf8.decode(await picked.readAsBytes());
    } catch (_) {
      if (!context.mounted) return;
      await _showError(context, 'Could not read the selected file.');
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
    final service = ref.read(dataExportServiceProvider);
    final supportDir = await getApplicationSupportDirectory();
    final snapshots = await service.listSnapshots(supportDir.path);
    if (!context.mounted) return;
    if (snapshots.isEmpty) {
      await _showError(context, 'There are no recent import snapshots.');
      return;
    }

    final File? selected = await showDialog<File>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Restore snapshot'),
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
        title: const Text('Restore snapshot?'),
        content: const Text(
          'This replaces current user data with the state saved before that import.',
        ),
        actions: [
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

    try {
      await service.restoreSnapshot(
        ref.read(appDatabaseProvider),
        selected,
        snapshotDirPath: supportDir.path,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Snapshot restored')),
      );
    } catch (e) {
      if (!context.mounted) return;
      await _showError(context, 'Snapshot restore failed: $e');
    }
  }

  Future<void> _runImport(
    BuildContext context,
    WidgetRef ref,
    DataExportService service,
    ImportEnvelope envelope,
    ImportMode mode,
  ) async {
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      ),
    );

    try {
      final AppDatabase db = ref.read(appDatabaseProvider);
      final supportDir = await getApplicationSupportDirectory();
      await service.applyImport(
        db,
        envelope,
        mode: mode,
        snapshotDirPath: supportDir.path,
      );
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Import complete')));
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await _showError(context, 'Import failed: $e');
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
          title: const Text('Import backup'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final table in highlights)
                  Text('${counts[table]} ${_friendlyName(table)}'),
                if (highlights.isEmpty)
                  const Text('This backup contains no workout data.'),
                if (missingTables.isNotEmpty || unknownTables.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${[
                      if (missingTables.isNotEmpty)
                        'Missing ${missingTables.length} database '
                            '${missingTables.length == 1 ? 'table' : 'tables'}',
                      if (unknownTables.isNotEmpty)
                        '${unknownTables.length} unknown '
                            '${unknownTables.length == 1 ? 'table' : 'tables'}',
                    ].join('; ')}. The file may be partial, truncated, or hand-edited.',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                RadioGroup<ImportMode>(
                  groupValue: mode,
                  onChanged: (value) => setState(() => mode = value!),
                  child: const Column(
                    children: [
                      RadioListTile<ImportMode>(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Merge'),
                        subtitle: Text('Keep existing data, add this on top'),
                        value: ImportMode.merge,
                      ),
                      RadioListTile<ImportMode>(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Replace'),
                        subtitle: Text(
                          'Erase everything currently on this device first',
                        ),
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
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, mode),
              child: const Text('Import'),
            ),
          ],
        ),
      ),
    );
  }

  String _friendlyName(String rawTableName) =>
      rawTableName.replaceAll('_table', '').replaceAll('_', ' ');

  Future<void> _showError(BuildContext context, String message) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import problem'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
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
    await ref.read(programSeederProvider.notifier).resetSeedVersion();
    ref.invalidate(programSeederProvider);
    await ref.read(programSeederProvider.future);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('All data deleted')));
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
    return AlertDialog(
      title: const Text('Delete all data?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently deletes every workout, timer session, '
            'program, template, and body-metrics entry (built-in programs '
            'will be restored). The exercise library is kept. This cannot '
            'be undone.',
          ),
          const SizedBox(height: 16),
          Text('Type DELETE to confirm', style: TextStyle(color: scheme.error)),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (value) =>
                setState(() => _canConfirm = value == 'DELETE'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: _canConfirm ? () => Navigator.pop(context, true) : null,
          child: const Text('Delete everything'),
        ),
      ],
    );
  }
}
