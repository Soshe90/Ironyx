import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/body_limits.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_providers.dart';
import '../../../../core/database/tables/body_metrics.dart';
import '../../../../core/formatters/date_formatters.dart';
import '../../../../core/formatters/number_input.dart';
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
            UnitFormatters.bodyWeight(entry.weightKg, unit, context.l10n),
            style: AppTypography.numeric(
              theme.textTheme.titleSmall ?? const TextStyle(),
            ),
          ),
          subtitle: Text(
            entry.bodyFatPercentage == null
                ? date
                : context.l10n.progressBodyMetricDateAndFat(
                    date,
                    UnitFormatters.oneDecimal(entry.bodyFatPercentage!),
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
  final DateTime date = entry?.date ?? DateTime.now();

  final (double, double?)? values = await showDialog<(double, double?)>(
    context: context,
    builder: (_) => _BodyMetricDialog(unit: unit, entry: entry, date: date),
  );
  if (values == null) return;

  await ref.read(bodyMetricsDaoProvider).upsert(
        BodyMetricsTableCompanion.insert(
          id: entry?.id ?? _uuid.v4(),
          date: date,
          weightKg: UnitFormatters.toKg(values.$1, unit),
          bodyFatPercentage: Value(values.$2),
        ),
      );
}

/// The dialog behind [showBodyMetricEditor]. Pops with the weight, in the
/// display unit, and the body-fat percentage (null when left empty), or
/// with nothing when cancelled.
///
/// It only pops with values it has checked. It used to pop with whatever
/// the fields held, and the caller then dropped an empty, zero or
/// unreadable weight without a word: the dialog closed as if it had saved.
/// Nothing bounded either number, so 825 for 82.5 went straight into the
/// charts.
///
/// A widget of its own so that it owns its controllers and disposes them
/// when it leaves the tree. [showBodyMetricEditor] used to create them and
/// dispose them as soon as `showDialog` returned, which is while the dialog
/// is still animating out with both fields mounted. A rebuild in that window
/// threw "TextEditingController was used after being disposed", and tearing
/// the route down afterwards failed Flutter's `_dependents.isEmpty`
/// assertion, replacing the whole screen with the error view.
class _BodyMetricDialog extends StatefulWidget {
  const _BodyMetricDialog({
    required this.unit,
    required this.entry,
    required this.date,
  });

  final WeightUnit unit;
  final BodyMetrics? entry;
  final DateTime date;

  @override
  State<_BodyMetricDialog> createState() => _BodyMetricDialogState();
}

class _BodyMetricDialogState extends State<_BodyMetricDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _weight = TextEditingController(
    text: widget.entry == null
        ? ''
        : UnitFormatters.plain(
            UnitFormatters.fromKg(widget.entry!.weightKg, widget.unit),
          ),
  );
  late final TextEditingController _bodyFat = TextEditingController(
    text: widget.entry?.bodyFatPercentage == null
        ? ''
        : UnitFormatters.plain(widget.entry!.bodyFatPercentage!),
  );

  /// Off until Save has been refused once, so the fields do not complain
  /// while they are first being filled in; on after that, so a message goes
  /// away as soon as its field is put right.
  bool _validateAsTyped = false;

  /// The weight limits in the display unit, rounded outwards to the two
  /// decimals the fields show. Rounded so that the limits the message
  /// quotes are themselves accepted: 25 kg is 55.1155… lb.
  late final double _minWeight =
      (UnitFormatters.fromKg(kMinBodyWeightKg, widget.unit) * 100)
              .floorToDouble() /
          100;
  late final double _maxWeight =
      (UnitFormatters.fromKg(kMaxBodyWeightKg, widget.unit) * 100)
              .ceilToDouble() /
          100;

  @override
  void dispose() {
    _weight.dispose();
    _bodyFat.dispose();
    super.dispose();
  }

  String? _validateWeight(String? value) => _validateNumber(
        value,
        min: _minWeight,
        max: _maxWeight,
        required: true,
      );

  String? _validateBodyFat(String? value) => _validateNumber(
        value,
        min: kMinBodyFatPercentage,
        max: kMaxBodyFatPercentage,
        required: false,
      );

  String? _validateNumber(
    String? value, {
    required double min,
    required double max,
    required bool required,
  }) {
    final AppLocalizations l10n = context.l10n;
    final String text = (value ?? '').trim();
    if (text.isEmpty) return required ? l10n.profileEnterANumber : null;
    final double? parsed = parseDecimalInput(text);
    if (parsed == null) return l10n.profileEnterANumber;
    if (parsed < min || parsed > max) {
      return l10n.profileEnterValueBetween(
        UnitFormatters.plain(min),
        UnitFormatters.plain(max),
      );
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _validateAsTyped = true);
      return;
    }
    final String fat = _bodyFat.text.trim();
    // Validated just above, so both parse.
    Navigator.pop(context, (
      parseDecimalInput(_weight.text)!,
      fat.isEmpty ? null : parseDecimalInput(fat)!,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.entry == null
            ? context.l10n.progressLogMeasurement
            : context.l10n.progressEditMeasurement,
      ),
      // With an error line under each field and the keyboard up, the
      // content can be taller than a small phone has room for.
      scrollable: true,
      content: Form(
        key: _formKey,
        autovalidateMode: _validateAsTyped
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              DateFormatters.of(context).full(widget.date),
              style: AppTypography.caption(Theme.of(context)),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _weight,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const <TextInputFormatter>[
                NumberInputFormatter.decimal(),
              ],
              decoration: InputDecoration(
                labelText: context.l10n.progressWeightField(widget.unit.label),
                errorMaxLines: 3,
              ),
              validator: _validateWeight,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _bodyFat,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const <TextInputFormatter>[
                NumberInputFormatter.decimal(),
              ],
              decoration: InputDecoration(
                labelText: context.l10n.progressBodyFatOptionalField,
                errorMaxLines: 3,
              ),
              validator: _validateBodyFat,
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(context.l10n.actionSave),
        ),
      ],
    );
  }
}
