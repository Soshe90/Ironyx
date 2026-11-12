import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/error_reporting.dart';
import '../../../../core/formatters/date_formatters.dart';
import '../../../../core/formatters/unit_formatters.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/services/workout_xlsx_import_service.dart';
import '../../../../core/theme/app_spacing.dart';

/// Preview-first importer for the user's historical XLSX workout log.
///
/// Usable as a button, or through [run] from a menu item. A menu item's own
/// context is gone once the menu closes, so [run] takes the caller's.
class WorkoutXlsxImportAction extends ConsumerWidget {
  const WorkoutXlsxImportAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      icon: const Icon(Icons.table_view_outlined),
      label: Text(context.l10n.importXlsxAction),
      onPressed: () => run(context, ref),
    );
  }

  /// Runs the whole pick → preview → confirm → import flow.
  static Future<void> run(BuildContext context, WidgetRef ref) async {
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
    // Before anything is read into memory: a file this size is not a
    // training log, and reading it could exhaust the memory.
    if (await picked.length() > kMaxWorkoutXlsxBytes) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.importXlsxTooLarge)),
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

  static Future<WeightUnit?> _chooseUnit(BuildContext context) {
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

  static Future<bool?> _confirm(
    BuildContext context,
    WorkoutXlsxImportResult result,
    WeightUnit sourceUnit,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.importXlsxConfirmTitle),
        content: SingleChildScrollView(
          child: WorkoutXlsxImportPreview(
            result: result,
            sourceUnit: sourceUnit,
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

/// What the confirm dialog says will be imported: counts, the date range,
/// skipped duplicates and names that match no exercise.
///
/// Its own widget so it can be checked without the file picker. The dates
/// were ISO strings ("2026-11-04") in every language; they are formatted
/// like every other date in the app now. They are the workbook's calendar
/// dates, read as UTC midnight, and formatting keeps their fields, so no
/// time zone moves a day. The gaps use the spacing scale, not literals.
class WorkoutXlsxImportPreview extends StatelessWidget {
  const WorkoutXlsxImportPreview({
    required this.result,
    required this.sourceUnit,
    super.key,
  });

  final WorkoutXlsxImportResult result;
  final WeightUnit sourceUnit;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final DateFormatters dates = DateFormatters.of(context);
    final DateTime? firstDate =
        result.workouts.isEmpty ? null : result.workouts.first.date;
    final DateTime? lastDate =
        result.workouts.isEmpty ? null : result.workouts.last.date;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.importXlsxConfirmSummary(
            result.workouts.length,
            result.totalSets,
            firstDate == null ? l10n.importXlsxNoDates : dates.full(firstDate),
            lastDate == null ? '' : dates.full(lastDate),
            sourceUnit.label,
          ),
        ),
        if (result.duplicateCount > 0) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.importXlsxDuplicateNote(
              result.duplicateCount,
              result.workouts.length,
            ),
          ),
        ],
        if (result.negativeWeightSetsSkipped > 0) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.importXlsxNegativeWeightNote(result.negativeWeightSetsSkipped),
          ),
        ],
        if (result.unknownExercises.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.importXlsxUnknownExercises),
          const SizedBox(height: AppSpacing.sm),
          for (final name in result.unknownExercises) Text('• $name'),
        ],
      ],
    );
  }
}
