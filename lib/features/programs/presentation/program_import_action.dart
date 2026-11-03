import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/tables/templates.dart' show kMaxTargetSets;
import '../../../core/error_reporting.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/providers.dart';
import '../../../core/services/program_import_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../domain/program_providers.dart';

/// How many skipped names or rows the preview lists before summarising the
/// rest, so a badly mangled file cannot produce a dialog of thousands of
/// lines.
const int _maxListedIssues = 10;

/// Imports programs from a spreadsheet (CSV). Excel can save/export to CSV,
/// keeping the import portable and dependency-light.
///
/// Usable as an icon button, or through [run] from a menu item. A menu
/// item's own context is gone once the menu closes, so [run] takes the
/// caller's (same pattern as `WorkoutXlsxImportAction`).
class ProgramImportAction extends ConsumerWidget {
  const ProgramImportAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.upload_file_outlined),
      tooltip: context.l10n.programImportTooltip,
      onPressed: () => run(context, ref),
    );
  }

  /// Runs the whole pick → preview → confirm → import flow.
  static Future<void> run(BuildContext context, WidgetRef ref) async {
    final PlatformFile? picked = await FilePicker.pickFile(
      dialogTitle: context.l10n.programImportPickerTitle,
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (picked == null || !context.mounted) return;

    final String csv;
    try {
      csv = utf8.decode(await picked.readAsBytes());
    } on Object {
      if (!context.mounted) return;
      _showMessage(context, context.l10n.dataImportUnreadable);
      return;
    }
    if (!context.mounted) return;
    await importCsv(context, ref, csv);
  }

  /// Everything after the file has been read: parse, preview, confirm and
  /// write. Separate from [run] so tests can drive it without the platform
  /// file picker.
  @visibleForTesting
  static Future<void> importCsv(
    BuildContext context,
    WidgetRef ref,
    String csv,
  ) async {
    final service = ref.read(programImportServiceProvider);
    final db = ref.read(appDatabaseProvider);
    final ProgramImportResult result;
    try {
      result = await service.parse(csv, db);
    } on ProgramImportException {
      if (!context.mounted) return;
      _showMessage(context, context.l10n.programImportInvalidHeader);
      return;
    } on Object catch (error, stackTrace) {
      // The catalogue and program-name lookups are database reads; a failure
      // there must still end in a message, not a silent no-op.
      reportError(error, stackTrace, context: 'ProgramImportService.parse');
      if (!context.mounted) return;
      _showMessage(context, context.l10n.dataImportUnreadable);
      return;
    }

    if (!context.mounted) return;
    final confirmed = await _confirm(context, result);
    if (confirmed != true || !context.mounted) return;

    try {
      await service.apply(db, result);
    } on Object catch (error, stackTrace) {
      // `apply()` is one transaction, so a failure leaves nothing behind —
      // but uncaught it escaped this tap handler and the user was told
      // nothing at all. The raw error goes to the reporter, not the screen.
      reportError(error, stackTrace, context: 'ProgramImportService.apply');
      if (!context.mounted) return;
      _showMessage(context, context.l10n.programImportApplyFailed);
      return;
    }
    ref.invalidate(programSummariesProvider);
    if (!context.mounted) return;
    _showMessage(context, context.l10n.programImportDone);
  }

  static Future<bool?> _confirm(
    BuildContext context,
    ProgramImportResult result,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final AppLocalizations l10n = context.l10n;
        return AlertDialog(
          title: Text(l10n.programImportConfirmTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.programImportSummary(
                    result.programs.length,
                    result.totalDays,
                    result.totalExercises,
                  ),
                ),
                ..._issueSection(
                  l10n,
                  l10n.programImportSkippedExisting,
                  result.existingPrograms,
                ),
                ..._issueSection(
                  l10n,
                  l10n.programImportSkippedUnknown,
                  result.unknownExercises,
                ),
                ..._issueSection(
                  l10n,
                  l10n.programImportSkippedRows,
                  [
                    for (final issue in result.rejectedRows)
                      switch (issue.problem) {
                        ProgramImportRowProblem.missingField =>
                          l10n.programImportRowMissingField(issue.rowNumber),
                        ProgramImportRowProblem.invalidSets =>
                          l10n.programImportRowInvalidSets(
                            issue.rowNumber,
                            kMaxTargetSets,
                          ),
                      },
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.actionCancel),
            ),
            FilledButton(
              onPressed: result.programs.isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text(l10n.importXlsxConfirmAction),
            ),
          ],
        );
      },
    );
  }

  /// A heading and bulleted list, or nothing when [items] is empty. Lists
  /// at most [_maxListedIssues] and counts the rest.
  static List<Widget> _issueSection(
    AppLocalizations l10n,
    String heading,
    List<String> items,
  ) {
    if (items.isEmpty) return const [];
    return [
      const SizedBox(height: AppSpacing.lg),
      Text(heading),
      const SizedBox(height: AppSpacing.sm),
      for (final item in items.take(_maxListedIssues)) Text('• $item'),
      if (items.length > _maxListedIssues)
        Text(l10n.programImportMore(items.length - _maxListedIssues)),
    ];
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
