import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/services/program_import_service.dart';
import '../domain/program_providers.dart';

/// Icon button that imports programs from a spreadsheet (CSV). Excel can
/// save/export to CSV, keeping the import portable and dependency-light.
class ProgramImportAction extends ConsumerWidget {
  const ProgramImportAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.upload_file_outlined),
      tooltip: 'Import programs from CSV',
      onPressed: () => _run(context, ref),
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref) async {
    final PlatformFile? picked = await FilePicker.pickFile(
      dialogTitle: 'Choose a program spreadsheet',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (picked == null || !context.mounted) return;

    final String csv;
    try {
      csv = utf8.decode(await picked.readAsBytes());
    } catch (_) {
      if (!context.mounted) return;
      _showMessage(context, 'Could not read the selected file.');
      return;
    }

    final service = ref.read(programImportServiceProvider);
    final db = ref.read(appDatabaseProvider);
    final ProgramImportResult result;
    try {
      result = await service.parse(csv, db);
    } on ProgramImportException catch (e) {
      if (!context.mounted) return;
      _showMessage(context, e.message);
      return;
    }

    if (!context.mounted) return;
    final confirmed = await _confirm(context, result);
    if (confirmed != true || !context.mounted) return;

    await service.apply(db, result);
    ref.invalidate(programSummariesProvider);
    if (!context.mounted) return;
    _showMessage(context, 'Programs imported.');
  }

  Future<bool?> _confirm(
    BuildContext context,
    ProgramImportResult result,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import programs?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${result.programs.length} programs · '
                '${result.totalDays} days · ${result.totalExercises} exercises',
              ),
              if (result.unknownExercises.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Skipped unknown exercises:'),
                const SizedBox(height: 8),
                for (final name in result.unknownExercises) Text('• $name'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: result.programs.isEmpty
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
