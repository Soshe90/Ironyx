import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/formatters/unit_formatters.dart';
import '../../../../core/services/workout_xlsx_import_service.dart';

/// Preview-first importer for the user's historical XLSX workout log.
class WorkoutXlsxImportAction extends ConsumerWidget {
  const WorkoutXlsxImportAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      icon: const Icon(Icons.table_view_outlined),
      label: const Text('Import XLSX'),
      onPressed: () => _run(context, ref),
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Choose your XLSX workout log',
      type: FileType.any,
    );
    if (picked == null) return;
    if (!picked.name.toLowerCase().endsWith('.xlsx')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please choose an .xlsx file.')),
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
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read this XLSX file: $error')),
        );
      }
      return;
    }
    if (!context.mounted) return;

    final confirmed = await _confirm(context, result, sourceUnit);
    if (confirmed != true || !context.mounted) return;

    await const WorkoutXlsxImportService().apply(
      ref.read(appDatabaseProvider),
      result,
    );
    ref.invalidate(workoutHistoryStreamProvider);
    ref.invalidate(personalRecordWorkoutIdsProvider);
    if (!context.mounted) return;
    final appliedCount = result.workouts.length - result.duplicateCount;
    final skippedSuffix = result.duplicateCount > 0
        ? ' (${result.duplicateCount} already in history skipped)'
        : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Imported $appliedCount workouts$skippedSuffix.',
        ),
      ),
    );
  }

  Future<WeightUnit?> _chooseUnit(BuildContext context) {
    return showDialog<WeightUnit>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('What unit is the workbook using?'),
        content: const Text(
          'The imported values are converted to kilograms for storage. '
          'This workbook looks like it uses pounds (lb).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, WeightUnit.kg),
            child: const Text('Kilograms'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, WeightUnit.lb),
            child: const Text('Pounds (recommended)'),
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
        title: const Text('Import workout history?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${result.workouts.length} workouts · ${result.totalSets} sets\n'
                '${firstDate?.toIso8601String().split('T').first ?? 'No dates'}'
                ' → ${lastDate?.toIso8601String().split('T').first ?? ''}\n'
                'Weights interpreted as ${sourceUnit == WeightUnit.lb ? 'lb' : 'kg'} '
                'and stored as kg.',
              ),
              if (result.duplicateCount > 0) ...[
                const SizedBox(height: 16),
                Text(
                  '${result.duplicateCount} of ${result.workouts.length} '
                  'workouts already appear in your history (same date, '
                  'exercises, and sets) and will be skipped.',
                ),
              ],
              if (result.unknownExercises.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'These exercises are not in the catalogue and will be added '
                  'as custom exercises:',
                ),
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
            onPressed: result.workouts.length == result.duplicateCount
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }
}
