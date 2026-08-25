import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/formatters/unit_formatters.dart';
import '../../../core/formatters/weight_unit_controller.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/page_body.dart';
import '../../../core/widgets/sticky_action_bar.dart';
import '../domain/bmi_advisory.dart';
import '../domain/profile_controller.dart';
import 'widgets/value_pill.dart';

/// The options offered for sex. Free-form storage (see `ProfilesTable.sex`),
/// but a short list covers the cases that change a training or nutrition
/// calculation, and "Prefer not to say" keeps the field answerable.
///
/// These are the values written to the database, so they stay English in
/// every locale — profiles already on disk were stored this way, and
/// translating the stored value would orphan them. [_sexLabel] does the
/// translating, at the point of display.
const List<String> _sexOptions = <String>[
  'Male',
  'Female',
  'Prefer not to say',
];

String _sexLabel(String option, AppLocalizations l10n) => switch (option) {
      'Male' => l10n.profileSexMale,
      'Female' => l10n.profileSexFemale,
      'Prefer not to say' => l10n.profileSexPreferNotToSay,
      // A value from an older build, or one this list no longer offers.
      // Showing it verbatim beats showing nothing.
      _ => option,
    };

/// Lowest and highest values the pickers offer. Wide enough not to exclude
/// anyone real, narrow enough to catch a cm/kg mix-up.
const double _minHeightCm = 90;
const double _maxHeightCm = 250;
const double _minWeightKg = 25;
const double _maxWeightKg = 350;

/// Name, date of birth, sex, height and current weight.
class PersonalDetailsPage extends ConsumerWidget {
  const PersonalDetailsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ProfileDraft> draftAsync =
        ref.watch(profileControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.accountPersonalDetailsTitle)),
      body: draftAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          title: context.l10n.profileLoadFailed,
          details: error.toString(),
          onRetry: () => ref.invalidate(profileControllerProvider),
        ),
        data: (draft) => _Body(draft: draft),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.draft});

  final ProfileDraft draft;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late final TextEditingController _name =
      TextEditingController(text: widget.draft.displayName);
  bool _saving = false;

  ProfileController get _notifier =>
      ref.read(profileControllerProvider.notifier);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ProfileDraft draft = widget.draft;
    final ThemeData theme = Theme.of(context);
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final AppLocalizations l10n = context.l10n;

    final String? advisory = BmiAdvisory.message(
      weightKg: draft.weightKg,
      heightCm: draft.heightCm,
      l10n: l10n,
    );

    return Column(
      children: <Widget>[
        Expanded(
          child: PageBody(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              children: <Widget>[
                Text(
                  l10n.profileIntro,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: AppSpacing.xl),
                TextField(
                  controller: _name,
                  decoration: InputDecoration(labelText: l10n.profileName),
                  textCapitalization: TextCapitalization.words,
                  onChanged: _notifier.setDisplayName,
                ),
                const SizedBox(height: AppSpacing.lg),
                ValuePillRow(
                  icon: Icons.calendar_today_outlined,
                  label: l10n.profileDateOfBirth,
                  value: draft.dateOfBirth == null
                      // An ISO date rather than a localized one: this is the
                      // value the user typed into a picker, and it round-trips
                      // unambiguously in any locale.
                      ? l10n.profileNotSet
                      : DateFormat('yyyy-MM-dd').format(draft.dateOfBirth!),
                  onPressed: _pickDateOfBirth,
                ),
                ValuePillRow(
                  icon: Icons.people_outline,
                  label: l10n.profileSex,
                  value: draft.sex == null
                      ? l10n.profileNotSet
                      : _sexLabel(draft.sex!, l10n),
                  onPressed: _pickSex,
                ),
                ValuePillRow(
                  icon: Icons.monitor_weight_outlined,
                  label: l10n.profileWeight,
                  value: draft.weightKg == null
                      ? l10n.profileNotSet
                      : UnitFormatters.weight(draft.weightKg!, unit),
                  onPressed: () => _pickWeight(unit),
                ),
                ValuePillRow(
                  icon: Icons.straighten,
                  label: l10n.profileHeight,
                  value: draft.heightCm == null
                      ? l10n.profileNotSet
                      : l10n.profileHeightCm(draft.heightCm!.round()),
                  onPressed: _pickHeight,
                ),
                if (advisory != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    advisory,
                    textAlign: TextAlign.center,
                    style: AppTypography.caption(theme),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
        StickyActionBar(
          child: FilledButton(
            onPressed: _saving ? null : _confirm,
            child: Text(l10n.actionConfirm),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDateOfBirth() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: widget.draft.dateOfBirth ?? DateTime(now.year - 30),
      // 120 years is comfortably past any real trainee; the lower bound
      // keeps the picker from offering an age that can't have an account.
      firstDate: DateTime(now.year - 120),
      lastDate: DateTime(now.year - 13, now.month, now.day),
      helpText: context.l10n.profileDateOfBirth,
    );
    if (picked != null) _notifier.setDateOfBirth(picked);
  }

  Future<void> _pickSex() async {
    final AppLocalizations l10n = context.l10n;
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        // RadioGroup owns the selection now; RadioListTile's own
        // groupValue/onChanged were deprecated after Flutter 3.32.
        child: RadioGroup<String>(
          groupValue: widget.draft.sex,
          onChanged: (value) => Navigator.pop(context, value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final String option in _sexOptions)
                RadioListTile<String>(
                  value: option,
                  title: Text(_sexLabel(option, l10n)),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) _notifier.setSex(picked);
  }

  Future<void> _pickWeight(WeightUnit unit) async {
    // Prompted and parsed in the user's display unit, converted to kg on the
    // way in — ADR-1: a pound value must never reach the database.
    final double? entered = await _promptForNumber(
      title: context.l10n.profileWeight,
      suffix: unit.label,
      initial: widget.draft.weightKg == null
          ? null
          : UnitFormatters.fromKg(widget.draft.weightKg!, unit),
      min: UnitFormatters.fromKg(_minWeightKg, unit),
      max: UnitFormatters.fromKg(_maxWeightKg, unit),
    );
    if (entered != null) {
      _notifier.setWeightKg(UnitFormatters.toKg(entered, unit));
    }
  }

  Future<void> _pickHeight() async {
    final double? entered = await _promptForNumber(
      title: context.l10n.profileHeight,
      suffix: context.l10n.unitCentimetres,
      initial: widget.draft.heightCm,
      min: _minHeightCm,
      max: _maxHeightCm,
    );
    if (entered != null) _notifier.setHeightCm(entered);
  }

  Future<double?> _promptForNumber({
    required String title,
    required String suffix,
    required double? initial,
    required double min,
    required double max,
  }) {
    return showDialog<double>(
      context: context,
      builder: (context) => _NumberInputDialog(
        title: title,
        suffix: suffix,
        initial: initial,
        min: min,
        max: max,
      ),
    );
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    // Resolved up front, like the two above it: by the time the snack bar is
    // shown this page has usually popped, and `context` is no longer a safe
    // place to look anything up.
    final AppLocalizations l10n = context.l10n;
    try {
      await _notifier.save();
      if (!mounted) return;
      // The BMI note is advisory, never a gate — Confirm always commits.
      if (navigator.canPop()) context.pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.profileSaved)));
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.profileSaveFailed('$error'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// A single validated numeric field in a dialog.
///
/// Stateful so it owns its own [TextEditingController]. Creating the
/// controller at the call site and disposing it in the `showDialog` future's
/// `whenComplete` looks equivalent but is not: the future resolves when the
/// route is popped, while the dialog keeps rebuilding through its exit
/// animation, and the field then reads a disposed controller. Letting the
/// framework dispose it after the route is really gone avoids that entirely.
class _NumberInputDialog extends StatefulWidget {
  const _NumberInputDialog({
    required this.title,
    required this.suffix,
    required this.initial,
    required this.min,
    required this.max,
  });

  final String title;
  final String suffix;
  final double? initial;
  final double min;
  final double max;

  @override
  State<_NumberInputDialog> createState() => _NumberInputDialogState();
}

class _NumberInputDialogState extends State<_NumberInputDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial == null ? '' : UnitFormatters.plain(widget.initial!),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: widget.suffix),
          validator: _validate,
          onFieldSubmitted: (_) => _submit(),
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

  String? _validate(String? value) {
    final AppLocalizations l10n = context.l10n;
    final double? parsed = double.tryParse((value ?? '').trim());
    if (parsed == null) return l10n.profileEnterANumber;
    if (parsed < widget.min || parsed > widget.max) {
      return l10n.profileEnterValueBetween(
        UnitFormatters.plain(widget.min),
        UnitFormatters.plain(widget.max),
      );
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(context, double.parse(_controller.text.trim()));
  }
}
