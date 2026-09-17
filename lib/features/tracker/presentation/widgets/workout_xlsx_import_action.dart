import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/error_reporting.dart';
import '../../../../core/formatters/unit_formatters.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/services/workout_xlsx_import_service.dart';

/// Preview-first importer for the user's historical XLSX workout log.
class WorkoutXlsxImportAction extends ConsumerWidget {
  const WorkoutXlsxImportAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      icon: const Icon(Icons.table_view_outlined),
      label: Text(context.l10n.importXlsxAction),
      onPressed: () => _run(context, ref),
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.pickFile(
      dialogTitle: context.l10n.importXlsxPickerTitle,
      type: FileType.any,
    );
    if (picked == null) return;
    if (!picked.name.toLowerCase().endsWith('.xlsx')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.importXlsxWrongType)),
        );
      }
      return;
    }
    if (!context.mounted) return;

    final sourceUnit = await _chooseUnit(context);
    if (sourceUnit == null || !context.mounted) return;

    final bytes = await picked.readAsBytes();
    if (!context.mounted) return;

    final WorkoutXlsxImportResult result;
    try {
      result = await const WorkoutXlsxImportService().parse(
        bytes,
        ref.read(appDatabaseProvider),
        sourceUnit: sourceUnit,
      );
    } on Object catch (error, stackTrace) {
      reportError(error, stackTrace, context: 'WorkoutXlsxImportService.parse');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.importXlsxReadFailed)),
        );
      }
      return;
    }
    if (!context.mounted) return;

    final confirmed = await _confirm(context, result, sourceUnit);
    if (confirmed != true || !context.mounted) return;

    try {
      await const WorkoutXlsxImportService().apply(
        ref.read(appDatabaseProvider),
        result,
      );
    } on Object catch (error, stackTrace) {
      // `apply()` runs inside a single transaction, so a failure here rolls
      // everything back rather than leaving a half-imported log — but
      // nothing previously caught it, so it would have surfaced as an
      // unhandled exception straight out of this tap handler.
      reportError(error, stackTrace, context: 'WorkoutXlsxImportService.apply');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.importXlsxApplyFailed)),
        );
      }
      return;
    }
    ref.invalidate(workoutHistoryStreamProvider);
    ref.invalidate(personalRecordWorkoutIdsProvider);
    if (!context.mounted) return;
    final appliedCount = result.workouts.length - result.duplicateCount;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.duplicateCount > 0
              ? context.l10n.importXlsxDoneWithSkips(
                  appliedCount,
                  result.duplicateCount,
                )
              : context.l10n.importXlsxDone(appliedCount),
        ),
      ),
    );
  }

  Future<WeightUnit?> _chooseUnit(BuildContext context) {
    return showDialog<WeightUnit>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.importXlsxUnitTitle),
        content: Text(context.l10n.importXlsxUnitBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, WeightUnit.kg),
            child: Text(context.l10n.importXlsxUnitKg),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, WeightUnit.lb),
            child: Text(context.l10n.importXlsxUnitLb),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirm(
    BuildContext context,
    WorkoutXlsxImportResult result,
    WeightUnit sourceUnit,
  ) {
    final firstDate =
        result.workouts.isEmpty ? null : result.workouts.first.date;
    final lastDate = result.workouts.isEmpty ? null : result.workouts.last.date;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.importXlsxConfirmTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.importXlsxConfirmSummary(
                  result.workouts.length,
                  result.totalSets,
                  firstDate?.toIso8601String().split('T').first ??
                      context.l10n.importXlsxNoDates,
                  lastDate?.toIso8601String().split('T').first ?? '',
                  sourceUnit.label,
                ),
              ),
              if (result.duplicateCount > 0) ...[
                const SizedBox(height: 16),
                Text(
                  context.l10n.importXlsxDuplicateNote(
                    result.duplicateCount,
                    result.workouts.length,
                  ),
                ),
              ],
              if (result.unknownExercises.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(context.l10n.importXlsxUnknownExercises),
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
            onPressed: result.workouts.length == result.duplicateCount
                ? null
                : () => Navigator.pop(context, true),
            child: Text(context.l10n.importXlsxConfirmAction),
          ),
        ],
      ),
    );
  }
}
