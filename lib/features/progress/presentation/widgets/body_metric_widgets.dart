import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_providers.dart';
import '../../../../core/database/tables/body_metrics.dart';
import '../../../../core/formatters/date_formatters.dart';
import '../../../../core/formatters/unit_formatters.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';

const Uuid _uuid = Uuid();

/// One logged measurement, with its edit/delete menu.
///
/// Shared by the Progress page's recent-measurements list and the full
/// history page, so the two cannot drift apart in formatting or in what the
/// overflow menu offers.
class BodyMetricTile extends ConsumerWidget {
  const BodyMetricTile({required this.entry, required this.unit, super.key});

  final BodyMetrics entry;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final String date = DateFormatters.of(context).full(entry.date);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            UnitFormatters.weight(entry.weightKg, unit),
            style: AppTypography.numeric(
              theme.textTheme.titleSmall ?? const TextStyle(),
            ),
          ),
          subtitle: Text(
            entry.bodyFatPercentage == null
                ? date
                : context.l10n.progressBodyMetricDateAndFat(
                    date,
                    entry.bodyFatPercentage!.toStringAsFixed(1),
                  ),
            style: AppTypography.caption(theme),
          ),
          trailing: PopupMenuButton<String>(
            tooltip: context.l10n.progressMeasurementOptions,
            onSelected: (String action) {
              if (action == 'edit') {
                showBodyMetricEditor(context, ref, unit: unit, entry: entry);
              }
              if (action == 'delete') {
                ref.read(bodyMetricsDaoProvider).deleteByDate(entry.date);
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'edit',
                child: Text(context.l10n.actionEdit),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                child: Text(context.l10n.actionDelete),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Logs or edits a measurement.
///
/// Weight is entered and shown in the user's display unit and converted to
/// kilograms on save — ADR-1's boundary. The dialog used to be hard-labelled
/// "kg" and stored the raw number, so a pounds user silently recorded pounds
/// as kilograms.
Future<void> showBodyMetricEditor(
  BuildContext context,
  WidgetRef ref, {
  required WeightUnit unit,
  BodyMetrics? entry,
}) async {
  final TextEditingController weight = TextEditingController(
    text: entry == null
        ? ''
        : UnitFormatters.plain(UnitFormatters.fromKg(entry.weightKg, unit)),
  );
  final TextEditingController bodyFat = TextEditingController(
    text: entry?.bodyFatPercentage == null
        ? ''
        : UnitFormatters.plain(entry!.bodyFatPercentage!),
  );
  final DateTime date = entry?.date ?? DateTime.now();

  try {
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          entry == null
              ? context.l10n.progressLogMeasurement
              : context.l10n.progressEditMeasurement,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              DateFormatters.of(context).full(date),
              style: AppTypography.caption(Theme.of(context)),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: weight,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: context.l10n.progressWeightField(unit.label),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: bodyFat,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: context.l10n.progressBodyFatOptionalField,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.actionSave),
          ),
        ],
      ),
    );
    if (saved != true) return;

    final double? entered = double.tryParse(weight.text);
    if (entered == null || entered <= 0) return;
    final double weightKg = UnitFormatters.toKg(entered, unit);
    final double? fat = double.tryParse(bodyFat.text);

    await ref.read(bodyMetricsDaoProvider).upsert(
          BodyMetricsTableCompanion.insert(
            id: entry?.id ?? _uuid.v4(),
            date: date,
            weightKg: weightKg,
            bodyFatPercentage: Value(fat),
          ),
        );
  } finally {
    // The dialog is gone by now either way; leaving these attached leaked a
    // controller per open-and-cancel.
    weight.dispose();
    bodyFat.dispose();
  }
}
