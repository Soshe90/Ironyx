import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/formatters/unit_formatters.dart';
import '../../../core/formatters/weight_unit_controller.dart';
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
const List<String> _sexOptions = <String>[
  'Male',
  'Female',
  'Prefer not to say',
];

/// Placeholder on a pill whose value hasn't been entered yet.
///
/// Reads as a state ("Date of Birth · Not set") rather than an instruction,
/// and — unlike a bare "Set" — doesn't collide with the picker dialog's own
/// confirm button, for sighted users or for the semantics tree.
const String _unset = 'Not set';

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
      appBar: AppBar(title: const Text('Personal Details')),
      body: draftAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          title: 'Failed to load your details',
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

    final String? advisory = BmiAdvisory.message(
      weightKg: draft.weightKg,
      heightCm: draft.heightCm,
    );

    return Column(
      children: <Widget>[
        Expanded(
          child: PageBody(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              children: <Widget>[
                Text(
                  'To tailor your program and progress tracking, FitTrack '
                  'uses a few personal details. They stay on this device.',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: AppSpacing.xl),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textCapitalization: TextCapitalization.words,
                  onChanged: _notifier.setDisplayName,
                ),
                const SizedBox(height: AppSpacing.lg),
                ValuePillRow(
                  icon: Icons.calendar_today_outlined,
                  label: 'Date of Birth',
                  value: draft.dateOfBirth == null
                      ? _unset
                      : DateFormat('yyyy-MM-dd').format(draft.dateOfBirth!),
                  onPressed: _pickDateOfBirth,
                ),
                ValuePillRow(
                  icon: Icons.people_outline,
                  label: 'Sex',
                  value: draft.sex ?? _unset,
                  onPressed: _pickSex,
                ),
                ValuePillRow(
                  icon: Icons.monitor_weight_outlined,
                  label: 'Weight',
                  value: draft.weightKg == null
                      ? _unset
                      : UnitFormatters.weight(draft.weightKg!, unit),
                  onPressed: () => _pickWeight(unit),
                ),
                ValuePillRow(
                  icon: Icons.straighten,
                  label: 'Height',
                  value: draft.heightCm == null
                      ? _unset
                      : '${draft.heightCm!.round()} cm',
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
            child: const Text('Confirm'),
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
      helpText: 'Date of birth',
    );
    if (picked != null) _notifier.setDateOfBirth(picked);
  }

  Future<void> _pickSex() async {
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
                RadioListTile<String>(value: option, title: Text(option)),
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
      title: 'Weight',
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
      title: 'Height',
      suffix: 'cm',
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
    try {
      await _notifier.save();
      if (!mounted) return;
      // The BMI note is advisory, never a gate — Confirm always commits.
      if (navigator.canPop()) context.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Personal details saved')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save your details: $error')),
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
    text: widget.initial == null
        ? ''
        : UnitFormatters.plain(widget.initial!),
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
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }

  String? _validate(String? value) {
    final double? parsed = double.tryParse((value ?? '').trim());
    if (parsed == null) return 'Enter a number.';
    if (parsed < widget.min || parsed > widget.max) {
      return 'Enter a value between ${UnitFormatters.plain(widget.min)} '
          'and ${UnitFormatters.plain(widget.max)}.';
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(context, double.parse(_controller.text.trim()));
  }
}
