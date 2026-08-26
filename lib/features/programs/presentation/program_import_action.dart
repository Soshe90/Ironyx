import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_extension.dart';
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
      tooltip: context.l10n.programImportTooltip,
      onPressed: () => _run(context, ref),
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref) async {
    final PlatformFile? picked = await FilePicker.pickFile(
      dialogTitle: context.l10n.programImportPickerTitle,
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (picked == null || !context.mounted) return;

    final String csv;
    try {
      csv = utf8.decode(await picked.readAsBytes());
    } catch (_) {
      if (!context.mounted) return;
      _showMessage(context, context.l10n.dataImportUnreadable);
      return;
    }

    final service = ref.read(programImportServiceProvider);
    final db = ref.read(appDatabaseProvider);
    final ProgramImportResult result;
    try {
      result = await service.parse(csv, db);
    } on ProgramImportException {
      if (!context.mounted) return;
      _showMessage(context, context.l10n.programImportInvalidHeader);
      return;
    }

    if (!context.mounted) return;
    final confirmed = await _confirm(context, result);
    if (confirmed != true || !context.mounted) return;

    await service.apply(db, result);
    ref.invalidate(programSummariesProvider);
    if (!context.mounted) return;
    _showMessage(context, context.l10n.programImportDone);
  }

  Future<bool?> _confirm(
    BuildContext context,
    ProgramImportResult result,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.programImportConfirmTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.programImportSummary(
                  result.programs.length,
                  result.totalDays,
                  result.totalExercises,
                ),
              ),
              if (result.unknownExercises.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(context.l10n.programImportSkippedUnknown),
                const SizedBox(height: 8),
                for (final name in result.unknownExercises) Text('• $name'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: result.programs.isEmpty
                ? null
                : () => Navigator.pop(context, true),
            child: Text(context.l10n.importXlsxConfirmAction),
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
