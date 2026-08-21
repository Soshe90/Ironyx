import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers.dart';
import 'unit_formatters.dart';

part 'weight_unit_controller.g.dart';

/// Persisted kg/lb display preference.
///
/// ADR-1: storage is always kilograms — this only controls how values are
/// formatted for display and how user input is converted back to kg.
///
/// Kept alive: watched from every screen that renders a weight, so letting
/// it dispose and rebuild would re-read preferences unnecessarily (mirrors
/// `ThemeModeController`).
@Riverpod(keepAlive: true)
class WeightUnitController extends _$WeightUnitController {
  static const String _prefsKey = 'weight_unit';

  @override
  WeightUnit build() {
    final String? stored = ref.watch(sharedPreferencesProvider).getString(
          _prefsKey,
        );
    return _decode(stored);
  }

  Future<void> set(WeightUnit unit) async {
    if (unit == state) {
      return;
    }
    state = unit;
    await ref.read(sharedPreferencesProvider).setString(
          _prefsKey,
          _encode(unit),
        );
  }

  static WeightUnit _decode(String? value) => switch (value) {
        'lb' => WeightUnit.lb,
        _ => WeightUnit.kg,
      };

  static String _encode(WeightUnit unit) => switch (unit) {
        WeightUnit.kg => 'kg',
        WeightUnit.lb => 'lb',
      };
}
